const pigpioClient = require('pigpio-client');
const spawn = require('child_process').spawn;
const fs = require('fs');

// Debug mode - set via environment variable (default: false)
// When false, reduces verbose logging to minimize SD card wear
const DEBUG = process.env.DEBUG === 'true' || process.env.DEBUG === '1';

// Initialize GPIO with error handling - using pigpio-client to connect to pigpiod daemon
// We're using docker-alpine-pigpiod container which runs pigpiod on localhost:8888
// pigpio-client connects via socket, no direct hardware access needed
let pigpio = null;
let boiler = null;
let gpioAvailable = false;

// Connect to pigpiod daemon (running in docker-alpine-pigpiod container)
pigpio = pigpioClient.pigpio({host: 'localhost', port: 8888});

// Wait for connection
pigpio.once('connected', (info) => {
  console.log('Connected to pigpiod daemon:', info);
  // Create GPIO pin 16 as output
  boiler = pigpio.gpio(16);
  boiler.modeSet('output');
  gpioAvailable = true;
  console.log('GPIO initialized successfully (connected to pigpiod daemon on localhost:8888)');
});

pigpio.once('error', (err) => {
  console.error('WARNING: Failed to connect to pigpiod daemon:', err.message);
  console.error('Ensure pigpiod container is running: docker ps | grep pigpiod');
  gpioAvailable = false;
  console.error('Process will continue but relay control will be disabled');
});

// Start connection
pigpio.connect(); 
const liquidPID = require('liquid-pid');
const MongoClient = require('mongodb').MongoClient;

// Temperature and safety constants
const MIN_TEMP = 0.0;
const MAX_TEMP_READING = 200.0;  // Maximum valid thermocouple reading
const MAX_SAFE_TEMP = 160.0;     // Emergency shutdown temperature
const TEMP_READ_TIMEOUT = 5000;  // 5 seconds
const MAX_CONSECUTIVE_FAILURES = 5;

let SSROutput = 0;
let pidController;
let config_file,
    config,
    target_temp = 35;
let consecutiveFailures = 0;
let lastValidTemperature = null;

// PID tuning parameters for overshoot prevention
let lastKnownGoodConfig = null; // Fallback if config.json is corrupted

// PID parameters - normal and recovery modes
let proportional = 4.0;
let integral = 0.1;
let derivative = 5.0;
let recovery_proportional = 6.0;
let recovery_integral = 0.2;
let recovery_derivative = 8.0;

// Recovery phase detection - for cold water refills
const TEMP_HISTORY_SIZE = 60;
const RECOVERY_DROP_THRESHOLD = 5.0; // °C drop to trigger recovery phase
const RECOVERY_WINDOW_SECONDS = 60; // Look back 60 seconds for drop detection
let temperatureHistory = []; // Array of {temp, timestamp}
let inRecoveryPhase = false;
let lastRecoveryPhaseChange = Date.now();

// Write optimization for SD card longevity
let writeBuffer = [];
const BATCH_SIZE = 10; // Write every 10 readings
const RETENTION_DAYS = 7; // Keep last 7 days
let lastCleanupTime = Date.now();

// Track last recording time when machine is "off" - record once per 3 minutes when off
let lastOffStateRecording = 0;
const OFF_STATE_RECORDING_INTERVAL_MS = 3 * 60 * 1000; // 3 minutes

const url = process.env.MONGODB_URL || 'mongodb://localhost:27017';
const client = new MongoClient(url, {useUnifiedTopology: true});

// MongoDB connection with retry logic
let mongoConnected = false;
let mongoRetryCount = 0;
const MAX_MONGO_RETRIES = 5;
const MONGO_RETRY_DELAY = 5000; // 5 seconds

async function connectMongoDB() {
  try {
    await client.connect();
    mongoConnected = true;
    mongoRetryCount = 0;
    console.log('Connected to MongoDB');
  } catch (err) {
    mongoRetryCount++;
    if (mongoRetryCount < MAX_MONGO_RETRIES) {
      const delay = MONGO_RETRY_DELAY * Math.pow(2, mongoRetryCount - 1); // Exponential backoff
      console.error(`MongoDB connection failed (attempt ${mongoRetryCount}/${MAX_MONGO_RETRIES}), retrying in ${delay/1000}s...`);
      setTimeout(connectMongoDB, delay);
    } else {
      console.error('MongoDB connection failed after max retries. PID control will continue without data logging.');
      mongoConnected = false;
    }
  }
}

// Start MongoDB connection
connectMongoDB();

// Machine state tracking
let lastMachineState = null;
let previousMachineState = null; // Track previous state to detect transitions
let pidResetOnHeatingStart = false; // Flag to ensure we only reset PID once per heating cycle
const CONFIG_FILE = 'config.json';
const STATE_UPDATE_THROTTLE_MS = 5000; // Only update state in config.json every 5 seconds max
let lastStateUpdateTime = 0;

// Helper function to update machine state in config.json
function updateMachineState(newState) {
  const now = Date.now();
  
  // Throttle updates to avoid excessive writes
  if (now - lastStateUpdateTime < STATE_UPDATE_THROTTLE_MS) {
    return;
  }
  
  // Only update if state changed
  if (lastMachineState === newState) {
    return;
  }
  
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    config.machine_state = newState;
    config.machine_state_updated = new Date().toISOString();
    
    // Write with permission retry (similar to web-server.js)
    try {
      fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
    } catch (writeErr) {
      if (writeErr.code === 'EACCES') {
        // Permission denied - try to fix permissions and retry
        try {
          fs.chmodSync(CONFIG_FILE, 0o666);
          fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
          if (DEBUG) {
            console.warn('Fixed config.json permissions and retried state update');
          }
        } catch (retryErr) {
          console.error('Failed to update machine state in config.json:', retryErr);
          return;
        }
      } else {
        throw writeErr;
      }
    }
    
    lastMachineState = newState;
    lastStateUpdateTime = now;
    
    if (DEBUG) {
      console.log(`Machine state updated to: ${newState}`);
    }
  } catch (err) {
    console.error('Error updating machine state:', err);
  }
}

// Smart filtering: only record meaningful readings
// Returns: { shouldRecord: boolean, state: string }
function shouldRecordReading(temperature, output) {
  // Determine machine state based on temperature trends and position relative to target
  const now = Date.now();
  const STATE_DETECTION_WINDOW_MS = 60 * 1000; // Look back 60 seconds for trend analysis
  const MIN_TEMP_FOR_HEATING = 40.0; // °C - must be above this to be "heating" (40°C accounts for hot weather)
  const MIN_TEMP_RISE = 1.0; // °C - minimum rise to consider "rising"
  const MIN_TEMP_FALL = -0.3; // °C - minimum fall to consider "falling" (1°C per few minutes = ~0.2-0.3°C per 60s)
  const TARGET_TOLERANCE_PERCENT = 0.02; // 2% of target range
  
  let machineState = 'unknown';
  let shouldRecord = false;
  
  // Calculate target range (2% tolerance)
  const targetRange = target_temp * TARGET_TOLERANCE_PERCENT;
  const lowerBound = target_temp - targetRange;
  
  // Calculate temperature trend if we have enough history
  if (temperatureHistory.length >= 10) {
    const cutoffTime = now - STATE_DETECTION_WINDOW_MS;
    const recentHistory = temperatureHistory.filter(h => h.timestamp >= cutoffTime);
    
    if (recentHistory.length >= 2) {
      // Find oldest temperature in the window (current temp is passed as parameter)
      const oldestTemp = recentHistory[0].temp;
      const tempChange = temperature - oldestTemp; // Current temp vs oldest in window
      const isRising = tempChange >= MIN_TEMP_RISE; // Temperature is rising
      const isFalling = tempChange <= MIN_TEMP_FALL; // Temperature is falling
      
      // Determine state based on temperature trend and position
      // Priority 1: Off - temperature is falling despite having input (machine physically off)
      if (isFalling && output > 10) {
        machineState = 'off';
        // Record once per 3 minutes when off (to track cooling, but minimize writes)
        const timeSinceLastOffRecording = now - lastOffStateRecording;
        shouldRecord = timeSinceLastOffRecording >= OFF_STATE_RECORDING_INTERVAL_MS;
      }
      // Priority 2: If temperature > 80°C, machine is active (heating or ready), not "off"
      // This ensures we continue recording during normal use when temp fluctuates
      if (temperature > 80.0) {
        if (temperature >= lowerBound || temperature >= target_temp) {
          machineState = 'ready';
        } else {
          machineState = 'heating';
        }
        shouldRecord = true;
      }
      // Priority 3: Ready - within 2% of target OR above target (if temp <= 80°C)
      else if (temperature >= lowerBound || temperature >= target_temp) {
        machineState = 'ready';
        shouldRecord = true;
      }
      // Priority 4: Heating - temperature is rising AND over 40°C
      else if (isRising && temperature > MIN_TEMP_FOR_HEATING) {
        machineState = 'heating';
        shouldRecord = true;
      }
      // Priority 5: Default - if not rising and not at target, check if we have output
      else if (output > 20) {
        // Has output but not clearly heating - could be starting up or recovering
        // If temp is above 30, treat as heating (recovery case)
        if (temperature > MIN_TEMP_FOR_HEATING) {
          machineState = 'heating';
          shouldRecord = true;
        } else {
          // Cold with output - likely off (not actually heating)
          machineState = 'off';
          // Record once per 3 minutes when off
          const timeSinceLastOffRecording = now - lastOffStateRecording;
          shouldRecord = timeSinceLastOffRecording >= OFF_STATE_RECORDING_INTERVAL_MS;
        }
      } else {
        // No significant output - machine is off
        machineState = 'off';
        // Record once per 3 minutes when off
        const timeSinceLastOffRecording = now - lastOffStateRecording;
        shouldRecord = timeSinceLastOffRecording >= OFF_STATE_RECORDING_INTERVAL_MS;
      }
    } else {
      // Not enough history in window - use simple heuristics
      if (temperature > 80.0) {
        // If temp > 80°C, machine is active
        if (temperature >= lowerBound || temperature >= target_temp) {
          machineState = 'ready';
        } else {
          machineState = 'heating';
        }
        shouldRecord = true;
      } else if (temperature >= lowerBound || temperature >= target_temp) {
        machineState = 'ready';
        shouldRecord = true;
      } else if (output > 20 && temperature > MIN_TEMP_FOR_HEATING) {
        machineState = 'heating';
        shouldRecord = true;
      } else {
        machineState = 'off';
        // Record once per 3 minutes when off
        const timeSinceLastOffRecording = now - lastOffStateRecording;
        shouldRecord = timeSinceLastOffRecording >= OFF_STATE_RECORDING_INTERVAL_MS;
      }
    }
  } else {
    // Not enough history yet - use simple heuristics
    if (temperature > 80.0) {
      // If temp > 80°C, machine is active
      if (temperature >= lowerBound || temperature >= target_temp) {
        machineState = 'ready';
      } else {
        machineState = 'heating';
      }
      shouldRecord = true;
    } else if (temperature >= lowerBound || temperature >= target_temp) {
      machineState = 'ready';
      shouldRecord = true;
    } else if (output > 20 && temperature > MIN_TEMP_FOR_HEATING) {
      machineState = 'heating';
      shouldRecord = true;
    } else {
      machineState = 'off';
      // Record once per 3 minutes when off
      const timeSinceLastOffRecording = now - lastOffStateRecording;
      shouldRecord = timeSinceLastOffRecording >= OFF_STATE_RECORDING_INTERVAL_MS;
    }
  }
  
  // Track state transition for PID reset
  previousMachineState = lastMachineState;
  
  updateMachineState(machineState);
  return { shouldRecord: shouldRecord, state: machineState };
}

// Batch insert to reduce write operations
async function insert(temperature, output) {
  try {
    // Check if this reading is worth recording and update state
    const recordCheck = shouldRecordReading(temperature, output);
    if (!recordCheck.shouldRecord) {
      return;
    }
    
    // Update last "off" state recording time if we're recording in off state
    if (recordCheck.state === 'off') {
      lastOffStateRecording = Date.now();
    }
    
    // Add to buffer
    writeBuffer.push({
      temperature: temperature,
      output: output,
      timestamp: Date.now(),
      pid_mode: inRecoveryPhase ? 'recovery' : 'normal'
    });
    
    // Write batch when buffer is full
    if (writeBuffer.length >= BATCH_SIZE) {
      await flushBuffer();
    }
    
    // Periodic cleanup (once per hour)
    const now = Date.now();
    if (now - lastCleanupTime > 60 * 60 * 1000) {
      await cleanup();
      lastCleanupTime = now;
    }
    
  } catch (e) {
    console.error('Error in insert:', e);
  }
}

// Write buffered data to MongoDB
async function flushBuffer() {
  if (writeBuffer.length === 0) return;
  
  // Only attempt write if MongoDB is connected
  if (!mongoConnected) {
    if (DEBUG) {
      console.warn('MongoDB not connected, skipping buffer flush');
    }
    return;
  }
  
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    await collection.insertMany(writeBuffer);
    if (DEBUG) {
      console.log(`Wrote batch of ${writeBuffer.length} readings to MongoDB`);
    }
    writeBuffer = [];
    
  } catch (err) {
    console.error('Error flushing buffer:', err);
    // If connection lost, mark as disconnected and let retry logic handle it
    if (err.message && (err.message.includes('connection') || err.message.includes('ECONNREFUSED'))) {
      mongoConnected = false;
      // Trigger reconnection attempt
      connectMongoDB();
    }
  }
}

// Clean up old data
async function cleanup() {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    const cutoffTime = Date.now() - (RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const result = await collection.deleteMany({ timestamp: { $lt: cutoffTime } });
    
    if (result.deletedCount > 0 && DEBUG) {
      console.log(`Cleaned up ${result.deletedCount} old records (older than ${RETENTION_DAYS} days)`);
    }
  } catch (e) {
    console.error('Error during cleanup:', e);
  }
}

// Flush any remaining buffer on shutdown
function exitHandler(options, exitCode) {
  if (options.cleanup) {
    if (gpioAvailable && boiler) {
      try {
        boiler.analogWrite(0);
      } catch (err) {
        console.error('Error shutting down GPIO:', err);
      }
    }
    flushBuffer().then(() => {
      if (pigpio) {
        pigpio.end();
      }
      client.close();
      if (options.exit) process.exit();
    });
  } else {
    if (options.exit) process.exit();
  }
}

// PWM output limits
const MAX_OUTPUT = 255; // Maximum PWM output

// Initialize PID controller once (not every loop!)
function initializePID() {
  let configValid = false;
  
  try {
    config_file = fs.readFileSync('config.json');
    config = JSON.parse(config_file.toString());
    
    // Validate and extract PID parameters with safe defaults
    target_temp = typeof config['target_temperature'] === 'number' && config['target_temperature'] >= 0 && config['target_temperature'] <= 200
      ? config['target_temperature']
      : (lastKnownGoodConfig?.target_temp || 100);
    
    proportional = typeof config['proportional'] === 'number' && config['proportional'] >= 0 && config['proportional'] <= 10
      ? config['proportional']
      : (lastKnownGoodConfig?.proportional || 4.0);
    
    integral = typeof config['integral'] === 'number' && config['integral'] >= 0 && config['integral'] <= 5
      ? config['integral']
      : (lastKnownGoodConfig?.integral || 0.1);
    
    derivative = typeof config['derivative'] === 'number' && config['derivative'] >= 0 && config['derivative'] <= 100
      ? config['derivative']
      : (lastKnownGoodConfig?.derivative || 5.0);
    
    // Recovery mode PID parameters (for cold water refills - faster heating, but still good damping)
    recovery_proportional = typeof config['recovery_proportional'] === 'number' && config['recovery_proportional'] >= 0 && config['recovery_proportional'] <= 10
      ? config['recovery_proportional']
      : (lastKnownGoodConfig?.recovery_proportional || 6.0);
    
    recovery_integral = typeof config['recovery_integral'] === 'number' && config['recovery_integral'] >= 0 && config['recovery_integral'] <= 5
      ? config['recovery_integral']
      : (lastKnownGoodConfig?.recovery_integral || 0.2);
    
    recovery_derivative = typeof config['recovery_derivative'] === 'number' && config['recovery_derivative'] >= 0 && config['recovery_derivative'] <= 100
      ? config['recovery_derivative']
      : (lastKnownGoodConfig?.recovery_derivative || 8.0);
    
    // Save as last known good config
    lastKnownGoodConfig = {
      target_temp,
      proportional,
      integral,
      derivative,
      recovery_proportional,
      recovery_integral,
      recovery_derivative
    };
    
    configValid = true;
    
  } catch (err) {
    console.error('Error reading/parsing config.json:', err.message);
    if (lastKnownGoodConfig) {
      console.log('Using last known good config values');
      target_temp = lastKnownGoodConfig.target_temp;
      proportional = lastKnownGoodConfig.proportional;
      integral = lastKnownGoodConfig.integral;
      derivative = lastKnownGoodConfig.derivative;
      recovery_proportional = lastKnownGoodConfig.recovery_proportional;
      recovery_integral = lastKnownGoodConfig.recovery_integral;
      recovery_derivative = lastKnownGoodConfig.recovery_derivative;
      configValid = true;
    } else {
      console.error('No valid config available, using safe defaults');
      // Use safe defaults
      target_temp = 100;
      proportional = 2.5;
      integral = 0.05;
      derivative = 10.0;
      recovery_proportional = 4.0;
      recovery_integral = 0.1;
      recovery_derivative = 12.0;
    }
  }

  // Use recovery or normal PID parameters based on current mode
  const currentKp = inRecoveryPhase ? recovery_proportional : proportional;
  const currentKi = inRecoveryPhase ? recovery_integral : integral;
  const currentKd = inRecoveryPhase ? recovery_derivative : derivative;
  
  pidController = new liquidPID({
    temp: {
      ref: target_temp,
    },
    Pmax: MAX_OUTPUT,
    Kp: currentKp,
    Ki: currentKi,
    Kd: currentKd,
  });
  
  const modeStr = inRecoveryPhase ? 'RECOVERY' : 'NORMAL';
  console.log(`PID initialized (${modeStr}): Kp=${currentKp}, Ki=${currentKi}, Kd=${currentKd}, Target=${target_temp}°C`);
}

// Switch PID mode (normal vs recovery)
function switchPIDMode(recovery) {
  if (recovery !== inRecoveryPhase) {
    inRecoveryPhase = recovery;
    // Reinitialize PID with new parameters
    initializePID();
    if (DEBUG) {
      console.log(`Switched to ${recovery ? 'RECOVERY' : 'NORMAL'} PID mode`);
    }
  }
}

// Initialize PID on startup
initializePID();

// Reload config every 10 seconds (not every loop!)
setInterval(() => {
  try {
    const newConfig = JSON.parse(fs.readFileSync('config.json', 'utf8'));
    
    // Validate new config values
    const newTarget = typeof newConfig.target_temperature === 'number' ? newConfig.target_temperature : target_temp;
    const newProportional = typeof newConfig.proportional === 'number' ? newConfig.proportional : proportional;
    const newIntegral = typeof newConfig.integral === 'number' ? newConfig.integral : integral;
    const newDerivative = typeof newConfig.derivative === 'number' ? newConfig.derivative : derivative;
    const newRecoveryProportional = typeof newConfig.recovery_proportional === 'number' ? newConfig.recovery_proportional : recovery_proportional;
    const newRecoveryIntegral = typeof newConfig.recovery_integral === 'number' ? newConfig.recovery_integral : recovery_integral;
    const newRecoveryDerivative = typeof newConfig.recovery_derivative === 'number' ? newConfig.recovery_derivative : recovery_derivative;
    
    // Only reinitialize if config changed
    if (newTarget !== target_temp ||
        newProportional !== proportional ||
        newIntegral !== integral ||
        newDerivative !== derivative ||
        newRecoveryProportional !== recovery_proportional ||
        newRecoveryIntegral !== recovery_integral ||
        newRecoveryDerivative !== recovery_derivative) {
      
      console.log('Config changed, reinitializing PID controller');
      initializePID();
    }
  } catch (err) {
    // Error already handled in initializePID, just log here
    if (DEBUG) {
      console.error('Error reading config:', err);
    }
  }
}, 10000); // Check config every 10 seconds

// Control loop - prevent overlapping executions
let controlLoopRunning = false;

setInterval(async () => {
  // Prevent overlapping control loops
  if (controlLoopRunning) {
    console.warn('Previous control loop still running, skipping this cycle');
    return;
  }
  
  controlLoopRunning = true;
  
  try {
    // Get temperature (async, with timeout)
    const temperature = await getTemp((temp) => temp);
    
    // Safety check: Emergency shutdown if temperature too high
    if (temperature > MAX_SAFE_TEMP) {
      console.error(`EMERGENCY: Temperature ${temperature}°C exceeds maximum safe limit ${MAX_SAFE_TEMP}°C! Shutting down heater.`);
      if (gpioAvailable && boiler) {
        try {
          boiler.analogWrite(0);
        } catch (err) {
          console.error('Error in emergency shutdown:', err);
        }
      } else {
        console.error('WARNING: GPIO unavailable - cannot shut down heater!');
      }
      consecutiveFailures = MAX_CONSECUTIVE_FAILURES; // Trigger safety shutdown
      controlLoopRunning = false;
      return;
    }
    
    // Update temperature history for recovery phase detection
    const now = Date.now();
    temperatureHistory.push({ temp: temperature, timestamp: now });
    
    // Keep only last TEMP_HISTORY_SIZE readings
    if (temperatureHistory.length > TEMP_HISTORY_SIZE) {
      temperatureHistory.shift();
    }
    
    // Detect recovery phase: check if temperature dropped significantly (cold water refill)
    let recoveryPhaseDetected = false;
    if (temperatureHistory.length >= 10) { // Need at least 10 seconds of history
      const cutoffTime = now - (RECOVERY_WINDOW_SECONDS * 1000);
      const recentHistory = temperatureHistory.filter(h => h.timestamp >= cutoffTime);
      
      if (recentHistory.length >= 2) {
        // Find max temperature in the window (before drop)
        const maxTemp = Math.max(...recentHistory.map(h => h.temp));
        const currentTemp = temperature;
        const tempDrop = maxTemp - currentTemp;
        
        // If we dropped significantly and we're below target, we're in recovery
        // Exit recovery when we reach target or exceed it
        if (tempDrop >= RECOVERY_DROP_THRESHOLD && temperature < target_temp && temperature < maxTemp) {
          recoveryPhaseDetected = true;
        }
      }
    }
    
    // Switch PID mode if recovery phase changed
    // Exit recovery mode when we're close to target (within 5°C) to prevent overshoot
    if (inRecoveryPhase && temperature >= target_temp - 5.0) {
      recoveryPhaseDetected = false;
    }
    switchPIDMode(recoveryPhaseDetected);
    
    // Calculate PID output - PID will use appropriate parameters based on mode (normal or recovery)
    // Backoff behavior is achieved through proper PID tuning (especially derivative), not JavaScript logic
    SSROutput = Math.round(pidController.calculate(temperature));
    
    // Check for state transition from "off" to "heating" and reset PID to clear integral wind-up
    // This prevents overshoot when machine starts heating after being off (integral accumulated to MAX)
    // We need to check state after calculating output to get accurate state detection
    let outputPercent = (SSROutput / MAX_OUTPUT) * 100;
    const recordCheck = shouldRecordReading(temperature, outputPercent);
    const currentState = recordCheck.state;
    
    // Detect transition from "off" to "heating" and reset PID once per heating cycle
    if (previousMachineState === 'off' && currentState === 'heating' && !pidResetOnHeatingStart) {
      console.log('Detected transition from "off" to "heating" - resetting PID controller to clear integral wind-up');
      initializePID(); // This creates a new PID instance, resetting _I=0
      pidResetOnHeatingStart = true; // Prevent multiple resets in same heating cycle
      // Recalculate output with fresh PID controller
      SSROutput = Math.round(pidController.calculate(temperature));
      outputPercent = (SSROutput / MAX_OUTPUT) * 100; // Recalculate outputPercent after reset
    }
    
    // Reset flag when machine goes back to "off" state
    if (currentState === 'off') {
      pidResetOnHeatingStart = false;
    }
    
    // CRITICAL: If temperature is at or above target, output must be 0
    // The boiler has thermal mass and will continue heating even after power is cut
    
    if (temperature >= target_temp) {
      // At or above target - shut off immediately (no exceptions)
      SSROutput = 0;
      if (DEBUG) {
        const overshoot = temperature - target_temp;
        console.log(`At/Above target: ${temperature.toFixed(1)}°C (${overshoot > 0 ? overshoot.toFixed(1) + '°C over' : 'at target'}), output = 0`);
      }
    }
    
    // Safety: If temperature is significantly above target, log error (output already 0 from above)
    if (temperature > target_temp + 10.0) {
      console.error(`EMERGENCY: Temperature ${temperature.toFixed(1)}°C is ${(temperature - target_temp).toFixed(1)}°C above target!`);
    }
    
    // Integral wind-up protection: If output is saturated, don't accumulate more integral
    // This is handled by clamping, but we can also check if we're at limits
    if (SSROutput >= MAX_OUTPUT || SSROutput <= 0) {
      // Output saturated - the PID library should handle this, but we log it
      if (DEBUG && SSROutput >= MAX_OUTPUT) {
        console.warn(`Output saturated at maximum (${SSROutput}) - integral may be accumulating`);
      }
    }
    
    // Clamp output to safe range
    SSROutput = Math.max(0, Math.min(MAX_OUTPUT, SSROutput));
    
    // Apply output to heater (only if GPIO available)
    if (gpioAvailable && boiler) {
      try {
        boiler.analogWrite(SSROutput);
      } catch (err) {
        console.error('Failed to set PWM output:', err);
      }
    } else {
      console.warn('GPIO unavailable - PID calculated output but cannot control heater');
    }
    
    // Log and record data (conditional on DEBUG mode)
    // outputPercent already calculated above for state detection
    if (DEBUG) {
      const recoveryStatus = inRecoveryPhase ? ' [RECOVERY]' : '';
      console.log(`Temp: ${temperature.toFixed(1)}°C, Target: ${target_temp}°C, Output: ${outputPercent.toFixed(1)}%, Error: ${error.toFixed(1)}°C${recoveryStatus}`);
    }
    
    // Insert to database (non-blocking)
    insert(temperature, outputPercent).catch(err => {
      console.error('Failed to insert temperature data:', err);
    });
    
  } catch (err) {
    console.error('Control loop error:', err.message);
    // Temperature read failed - don't update PID or heater
    // Safety mechanism in getTemp() will handle shutdown if needed
  } finally {
    controlLoopRunning = false;
  }
}, 1000);

async function getTemp(callback) {
  return new Promise((resolve, reject) => {
    let temp = null;
    let errorOutput = '';
    let timeoutHandle;
    
    const temperatureProcess = spawn('python3', ['temperature.py']);
    
    // Set timeout for temperature reading
    timeoutHandle = setTimeout(() => {
      temperatureProcess.kill();
      console.error('ERROR: Temperature read timeout after 5 seconds');
      reject(new Error('Temperature read timeout'));
    }, TEMP_READ_TIMEOUT);
    
    temperatureProcess.stdout.on('data', (data) => {
      temp = data.toString().trim();
    });
    
    temperatureProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });
    
    temperatureProcess.on('close', function(code) {
      clearTimeout(timeoutHandle);
      
      // Check exit code
      if (code !== 0) {
        console.error(`ERROR: Temperature script exited with code ${code}`);
        if (errorOutput) {
          console.error(`Temperature script error: ${errorOutput}`);
        }
        consecutiveFailures++;
        
        if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
          console.error(`CRITICAL: ${MAX_CONSECUTIVE_FAILURES} consecutive temperature read failures. Shutting down heater for safety.`);
          if (gpioAvailable && boiler) {
            try {
              boiler.analogWrite(0); // Turn off heater for safety
            } catch (err) {
              console.error('Error shutting down heater:', err);
            }
          } else {
            console.error('WARNING: GPIO unavailable - cannot shut down heater!');
          }
          reject(new Error('Too many consecutive temperature read failures'));
          return;
        }
        
        reject(new Error(`Temperature read failed with exit code ${code}`));
        return;
      }
      
      // Validate temperature
      const temperature = parseFloat(temp);
      if (isNaN(temperature)) {
        console.error(`ERROR: Invalid temperature value: ${temp}`);
        consecutiveFailures++;
        reject(new Error('Invalid temperature value'));
        return;
      }
      
      if (temperature < MIN_TEMP || temperature > MAX_TEMP_READING) {
        console.error(`ERROR: Temperature ${temperature}°C out of valid range (${MIN_TEMP}-${MAX_TEMP_READING}°C)`);
        consecutiveFailures++;
        reject(new Error('Temperature out of valid range'));
        return;
      }
      
      // Success - reset failure counter
      consecutiveFailures = 0;
      lastValidTemperature = temperature;
      callback(temperature);
      resolve(temperature);
    });
    
    temperatureProcess.on('error', (err) => {
      clearTimeout(timeoutHandle);
      console.error(`ERROR: Failed to spawn temperature process: ${err}`);
      consecutiveFailures++;
      reject(err);
    });
  });
}

//do something when app is closing
process.on('exit', exitHandler.bind(null, {cleanup: true}));
//catches ctrl+c event
process.on('SIGINT', exitHandler.bind(null, {exit: true}));
// catches "kill pid" (for example: nodemon restart)
process.on('SIGUSR1', exitHandler.bind(null, {exit: true}));
process.on('SIGUSR2', exitHandler.bind(null, {exit: true}));
//catches uncaught exceptions
process.on('uncaughtException', exitHandler.bind(null, {exit: true}));
