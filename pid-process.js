const Gpio = require('pigpio').Gpio;
const spawn = require('child_process').spawn;
const fs = require('fs');
const boiler = new Gpio(16, {mode: Gpio.OUTPUT}); 
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
    target_temp = 35,
    proportional = 3.4,
    derivative = 0.3,
    integral = 40.0;
let consecutiveFailures = 0;
let lastValidTemperature = null;

// Write optimization for SD card longevity
let writeBuffer = [];
const BATCH_SIZE = 10; // Write every 10 readings
const RETENTION_DAYS = 7; // Keep last 7 days
let lastCleanupTime = Date.now();

const url = process.env.MONGODB_URL || 'mongodb://localhost:27017';
const client = new MongoClient(url, {useUnifiedTopology: true});
client.connect().then(() => {
  console.log('Connected to MongoDB');
});

// Smart filtering: only record meaningful readings
function shouldRecordReading(temperature, output) {
  // Don't record when machine is off (cold + no output)
  if (temperature < 60 && output < 10) {
    return false;
  }
  
  // Don't record initial heating phase (100% output, still cold)
  if (output > 95 && temperature < 80) {
    return false;
  }
  
  // Always record when in operating range
  return true;
}

// Batch insert to reduce write operations
async function insert(temperature, output) {
  try {
    // Check if this reading is worth recording
    if (!shouldRecordReading(temperature, output)) {
      return;
    }
    
    // Add to buffer
    writeBuffer.push({
      temperature: temperature,
      output: output,
      timestamp: Date.now()
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
  
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    await collection.insertMany(writeBuffer);
    console.log(`Wrote batch of ${writeBuffer.length} readings to MongoDB`);
    writeBuffer = [];
    
  } catch (err) {
    console.error('Error flushing buffer:', err);
  }
}

// Clean up old data
async function cleanup() {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    const cutoffTime = Date.now() - (RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const result = await collection.deleteMany({ timestamp: { $lt: cutoffTime } });
    
    if (result.deletedCount > 0) {
      console.log(`Cleaned up ${result.deletedCount} old records (older than ${RETENTION_DAYS} days)`);
    }
  } catch (e) {
    console.error('Error during cleanup:', e);
  }
}

// Flush any remaining buffer on shutdown
function exitHandler(options, exitCode) {
  if (options.cleanup) {
    boiler.pwmWrite(0);
    flushBuffer().then(() => {
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
  config_file = fs.readFileSync('config.json');
  config = JSON.parse(config_file.toString());
  target_temp = config['target_temperature'];
  proportional = config['proportional'];
  derivative = config['derivative'];
  integral = config['integral'];

  pidController = new liquidPID({
    temp: {
      ref: target_temp,
    },
    Pmax: MAX_OUTPUT,
    Kp: proportional,
    Ki: integral,      // ✅ Fixed: Ki = integral
    Kd: derivative,    // ✅ Fixed: Kd = derivative
  });
  
  console.log(`PID initialized: Kp=${proportional}, Ki=${integral}, Kd=${derivative}, Target=${target_temp}°C`);
}

// Initialize PID on startup
initializePID();

// Reload config every 10 seconds (not every loop!)
setInterval(() => {
  try {
    const newConfig = JSON.parse(fs.readFileSync('config.json', 'utf8'));
    
    // Only reinitialize if config changed
    if (newConfig.target_temperature !== target_temp ||
        newConfig.proportional !== proportional ||
        newConfig.integral !== integral ||
        newConfig.derivative !== derivative) {
      
      console.log('Config changed, reinitializing PID controller');
      initializePID();
    }
  } catch (err) {
    console.error('Error reading config:', err);
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
      boiler.pwmWrite(0);
      consecutiveFailures = MAX_CONSECUTIVE_FAILURES; // Trigger safety shutdown
      controlLoopRunning = false;
      return;
    }
    
    // Calculate PID output
    SSROutput = Math.round(pidController.calculate(temperature));
    
    // Clamp output to safe range
    SSROutput = Math.max(0, Math.min(MAX_OUTPUT, SSROutput));
    
    // Apply output to heater
    boiler.pwmWrite(SSROutput);
    
    // Log and record data
    const outputPercent = (SSROutput / MAX_OUTPUT) * 100;
    console.log(`Temp: ${temperature.toFixed(1)}°C, Target: ${target_temp}°C, Output: ${outputPercent.toFixed(1)}%`);
    
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
          boiler.pwmWrite(0); // Turn off heater for safety
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
