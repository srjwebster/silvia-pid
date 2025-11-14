// import required packages
const express = require('express');
const cors = require('cors');
const cookieParser = require('cookie-parser');
const fs = require('fs');
const path = require('path');
const MongoClient = require('mongodb').MongoClient;

// Environment configuration
const USE_SSL = process.env.USE_SSL === 'true';
const SSL_KEY_PATH = process.env.SSL_KEY_PATH || '/etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem';
const SSL_CERT_PATH = process.env.SSL_CERT_PATH || '/etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem';
const HTTP_PORT = parseInt(process.env.HTTP_PORT || '80');
const HTTPS_PORT = parseInt(process.env.HTTPS_PORT || '443');
const MONGODB_URL = process.env.MONGODB_URL || 'mongodb://localhost';
const CONFIG_FILE = process.env.CONFIG_FILE || path.join(__dirname, 'config.json');
const API_KEY = process.env.API_KEY || ''; // API key for write operations

// create new express app and save it as "app"
const app = express();
app.use(cors());

// Security headers for HTTPS
if (USE_SSL) {
  app.use((req, res, next) => {
    // Force HTTPS
    if (req.header('x-forwarded-proto') !== 'https' && req.secure === false) {
      return res.redirect(`https://${req.header('host')}${req.url}`);
    }
    // Security headers
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    next();
  });
}

app.use(express.json()); // Add JSON body parsing for API endpoints
app.use(cookieParser()); // Parse cookies for API key

// API Key authentication middleware (only for write operations)
function requireApiKey(req, res, next) {
  // If no API key is configured, allow all requests (backward compatible)
  if (!API_KEY || API_KEY === '') {
    return next();
  }
  
  // Get API key from header or cookie
  const providedKey = req.headers['x-api-key'] || req.cookies?.api_key || req.query.api_key;
  
  if (!providedKey) {
    return res.status(403).json({
      error: 'Authentication required',
      message: 'API key required for this operation. Please enter your API key.'
    });
  }
  
  // Constant-time comparison to prevent timing attacks
  const crypto = require('crypto');
  const providedKeyBuffer = Buffer.from(providedKey, 'utf8');
  const expectedKeyBuffer = Buffer.from(API_KEY, 'utf8');
  
  if (providedKeyBuffer.length !== expectedKeyBuffer.length) {
    return res.status(403).json({
      error: 'Invalid API key',
      message: 'The provided API key is incorrect.'
    });
  }
  
  if (!crypto.timingSafeEqual(providedKeyBuffer, expectedKeyBuffer)) {
    return res.status(403).json({
      error: 'Invalid API key',
      message: 'The provided API key is incorrect.'
    });
  }
  
  // Key is valid, proceed
  next();
}

// Helper function to write config.json with permission retry
function writeConfigFile(config) {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
  } catch (writeErr) {
    if (writeErr.code === 'EACCES') {
      // Permission denied - try to fix permissions and retry
      try {
        fs.chmodSync(CONFIG_FILE, 0o666);
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
        console.warn('Fixed config.json permissions and retried write');
      } catch (retryErr) {
        throw new Error(`Permission denied: Cannot write to ${CONFIG_FILE}. Please run: sudo chmod 666 ${CONFIG_FILE} && sudo chown 999:999 ${CONFIG_FILE}`);
      }
    } else {
      throw writeErr;
    }
  }
}

let server;
let io;

// Set up HTTPS if SSL is enabled and certificates exist
if (USE_SSL) {
  try {
    const https = require('https');
    const httpsServer = https.createServer({
      key: fs.readFileSync(SSL_KEY_PATH),
      cert: fs.readFileSync(SSL_CERT_PATH),
      requestCert: false,
      rejectUnauthorized: false,
    }, app);
    
    httpsServer.listen(HTTPS_PORT, () => {
      console.log(`HTTPS Server running on port ${HTTPS_PORT}`);
    });
    
    // HTTP redirect to HTTPS
    let httpRedirect = express();
    httpRedirect.get('*', function(req, res) {
      res.redirect('https://' + req.headers.host + req.url);
    });
    httpRedirect.listen(HTTP_PORT, () => {
      console.log(`HTTP redirect running on port ${HTTP_PORT}`);
    });
    
    server = httpsServer;
  } catch (err) {
    console.error('Failed to start HTTPS server:', err);
    console.log('Falling back to HTTP only');
    server = app.listen(HTTP_PORT, () => {
      console.log(`HTTP Server running on port ${HTTP_PORT}`);
    });
  }
} else {
  // HTTP only
  server = app.listen(HTTP_PORT, () => {
    console.log(`HTTP Server running on port ${HTTP_PORT}`);
  });
}

// Initialize Socket.IO v4.x server
const { Server } = require('socket.io');
io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const client = new MongoClient(MONGODB_URL, {useUnifiedTopology: true});
client.connect().then(() => {
  console.log('Connected to MongoDB');
}).catch(err => {
  console.error('Failed to connect to MongoDB:', err);
});

// Routes
app.get('/', (req, res) => {
  res.sendFile(__dirname + '/index.html');
});

// API endpoint to set target temperature (saves to current mode's preference)
app.get('/api/temp/set/:temp', requireApiKey, (req, res) => {
  try {
    const temp = parseFloat(req.params.temp);
    
    // Validate temperature
    if (isNaN(temp) || temp < 0 || temp > 200) {
      return res.status(400).json({
        error: 'Invalid temperature',
        message: 'Temperature must be between 0 and 200°C'
      });
    }
    
    // Read current config
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    
    // Update target temperature (active setting)
    config.target_temperature = temp;
    
    // Save temperature preference for current mode
    if (currentMode === 'espresso') {
      config.espresso_temperature = temp;
      console.log(`Espresso temperature preference saved: ${temp}°C`);
    } else if (currentMode === 'steam') {
      config.steam_temperature = temp;
      console.log(`Steam temperature preference saved: ${temp}°C`);
    }
    
    // Write updated config (with permission retry)
    writeConfigFile(config);
    
    console.log(`Target temperature updated to ${temp}°C (saved for ${currentMode} mode)`);
    res.json({
      success: true,
      target_temperature: temp,
      mode: currentMode,
      message: 'Target temperature updated'
    });
  } catch (err) {
    console.error('Failed to update target temperature:', err);
    res.status(500).json({
      error: 'Failed to update configuration',
      message: err.message
    });
  }
});

// API endpoint to get temperature history
app.get('/api/temp/get/:limit', (req, res) => {
  read(parseInt(req.params.limit)).then(temps => {
    res.send(temps);
  }).catch(err => {
    console.error('Failed to read temperature data:', err);
    res.status(500).json({error: 'Failed to read temperature data'});
  });
});

// API endpoint to set PID parameters (all at once)
app.get('/api/pid/set/:p-:i-:d', requireApiKey, (req, res) => {
  try {
    const p = parseFloat(req.params.p);
    const i = parseFloat(req.params.i);
    const d = parseFloat(req.params.d);
    
    // Validate PID values
    if (isNaN(p) || isNaN(i) || isNaN(d)) {
      return res.status(400).json({
        error: 'Invalid PID values',
        message: 'All PID parameters must be valid numbers'
      });
    }
    
    if (p < 0 || i < 0 || d < 0) {
      return res.status(400).json({
        error: 'Invalid PID values',
        message: 'PID parameters must be non-negative'
      });
    }
    
    // Read current config
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    config.proportional = p;
    config.integral = i;
    config.derivative = d;
    
    // Write updated config (with permission retry)
    writeConfigFile(config);
    
    console.log(`PID parameters updated: Kp=${p}, Ki=${i}, Kd=${d}`);
    res.json({
      success: true,
      proportional: p,
      integral: i,
      derivative: d,
      message: 'PID parameters updated'
    });
  } catch (err) {
    console.error('Failed to update PID parameters:', err);
    res.status(500).json({
      error: 'Failed to update configuration',
      message: err.message
    });
  }
});

// API endpoint to update individual PID parameter
// Usage: POST /api/pid/update with body: {"parameter": "proportional", "value": 4.5}
// Or: GET /api/pid/update?parameter=proportional&value=4.5
app.post('/api/pid/update', requireApiKey, express.json(), (req, res) => {
  try {
    const { parameter, value } = req.body;
    
    if (!parameter || value === undefined) {
      return res.status(400).json({
        error: 'Missing parameters',
        message: 'Must provide "parameter" and "value" in request body'
      });
    }
    
    // Valid PID parameter names
    const validParams = [
      'proportional', 'integral', 'derivative',
      'recovery_proportional', 'recovery_integral', 'recovery_derivative'
    ];
    
    if (!validParams.includes(parameter)) {
      return res.status(400).json({
        error: 'Invalid parameter',
        message: `Parameter must be one of: ${validParams.join(', ')}`
      });
    }
    
    const numValue = parseFloat(value);
    if (isNaN(numValue) || numValue < 0) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Value must be a non-negative number'
      });
    }
    
    // Validate ranges
    if (parameter.includes('proportional') && numValue > 10) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Proportional gain should be <= 10'
      });
    }
    if (parameter.includes('integral') && numValue > 5) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Integral gain should be <= 5'
      });
    }
    if (parameter.includes('derivative') && numValue > 100) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Derivative gain should be <= 100'
      });
    }
    
    // Read current config
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    config[parameter] = numValue;
    
    // Write updated config (with permission retry)
    writeConfigFile(config);
    
    console.log(`PID parameter updated: ${parameter} = ${numValue}`);
    res.json({
      success: true,
      parameter: parameter,
      value: numValue,
      message: `Updated ${parameter} to ${numValue}`
    });
  } catch (err) {
    console.error('Failed to update PID parameter:', err);
    res.status(500).json({
      error: 'Failed to update configuration',
      message: err.message
    });
  }
});

// GET version for convenience (same logic as POST)
app.get('/api/pid/update', requireApiKey, (req, res) => {
  try {
    const parameter = req.query.parameter;
    const value = req.query.value;
    
    if (!parameter || value === undefined) {
      return res.status(400).json({
        error: 'Missing parameters',
        message: 'Must provide "parameter" and "value" query parameters'
      });
    }
    
    // Valid PID parameter names
    const validParams = [
      'proportional', 'integral', 'derivative',
      'recovery_proportional', 'recovery_integral', 'recovery_derivative'
    ];
    
    if (!validParams.includes(parameter)) {
      return res.status(400).json({
        error: 'Invalid parameter',
        message: `Parameter must be one of: ${validParams.join(', ')}`
      });
    }
    
    const numValue = parseFloat(value);
    if (isNaN(numValue) || numValue < 0) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Value must be a non-negative number'
      });
    }
    
    // Validate ranges
    if (parameter.includes('proportional') && numValue > 10) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Proportional gain should be <= 10'
      });
    }
    if (parameter.includes('integral') && numValue > 5) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Integral gain should be <= 5'
      });
    }
    if (parameter.includes('derivative') && numValue > 100) {
      return res.status(400).json({
        error: 'Invalid value',
        message: 'Derivative gain should be <= 100'
      });
    }
    
    // Read current config
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    config[parameter] = numValue;
    
    // Write updated config (with permission retry)
    writeConfigFile(config);
    
    console.log(`PID parameter updated: ${parameter} = ${numValue}`);
    res.json({
      success: true,
      parameter: parameter,
      value: numValue,
      message: `Updated ${parameter} to ${numValue}`
    });
  } catch (err) {
    console.error('Failed to update PID parameter:', err);
    res.status(500).json({
      error: 'Failed to update configuration',
      message: err.message
    });
  }
});

// Mode management
let currentMode = 'espresso';
let steamTimer = null;
const STEAM_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes default

// Helper function to set mode
function setMode(mode, duration = null) {
  if (mode !== 'espresso' && mode !== 'steam' && mode !== 'off') {
    throw new Error('Invalid mode');
  }
  
  // Read config to get saved temperature for this mode
  const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  
  let targetTemp;
  if (mode === 'off') {
    targetTemp = 0;
  } else if (mode === 'steam') {
    // Use saved steam temperature, or default to 140
    targetTemp = config.steam_temperature || 140;
  } else {
    // Use saved espresso temperature, or default to 100
    targetTemp = config.espresso_temperature || 100;
  }
  
      // Update target temperature
      config.target_temperature = targetTemp;
      
      // Write updated config (with permission retry)
      writeConfigFile(config);
  
  currentMode = mode;
  
  // Clear any existing steam timer
  if (steamTimer) {
    clearTimeout(steamTimer);
    steamTimer = null;
  }
  
  // Set timer for steam mode
  if (mode === 'steam') {
    const timeoutMs = duration ? duration * 1000 : STEAM_TIMEOUT_MS;
    console.log(`Steam mode activated, will auto-switch to espresso in ${timeoutMs / 1000}s`);
    
    steamTimer = setTimeout(() => {
      console.log('Steam timeout reached, switching to espresso mode');
      setMode('espresso');
      // Emit event to connected clients
      io.emit('mode_change', { mode: 'espresso', reason: 'steam_timeout' });
    }, timeoutMs);
  }
  
  const modeNames = {
    espresso: 'Espresso',
    steam: 'Steam',
    off: 'Off'
  };
  
  console.log(`Mode changed to: ${modeNames[mode]} (${targetTemp}°C)`);
  return { temp: targetTemp, name: modeNames[mode] };
}

// API endpoint to set mode to espresso
app.get('/api/mode/espresso', requireApiKey, (req, res) => {
  try {
    const modeConfig = setMode('espresso');
    res.json({
      success: true,
      mode: 'espresso',
      temperature: modeConfig.temp,
      message: 'Switched to espresso mode'
    });
  } catch (err) {
    console.error('Failed to set espresso mode:', err);
    res.status(500).json({
      error: 'Failed to set mode',
      message: err.message
    });
  }
});

// API endpoint to set mode to steam (with optional duration in seconds)
app.get('/api/mode/steam/:duration?', requireApiKey, (req, res) => {
  try {
    const duration = req.params.duration ? parseInt(req.params.duration) : null;
    
    // Validate duration if provided
    if (duration !== null && (isNaN(duration) || duration < 10 || duration > 600)) {
      return res.status(400).json({
        error: 'Invalid duration',
        message: 'Duration must be between 10 and 600 seconds (10min max)'
      });
    }
    
    const modeConfig = setMode('steam', duration);
    const timeoutSeconds = duration || (STEAM_TIMEOUT_MS / 1000);
    
    res.json({
      success: true,
      mode: 'steam',
      temperature: modeConfig.temp,
      timeout_seconds: timeoutSeconds,
      message: `Switched to steam mode, will auto-switch to espresso in ${timeoutSeconds}s`
    });
  } catch (err) {
    console.error('Failed to set steam mode:', err);
    res.status(500).json({
      error: 'Failed to set mode',
      message: err.message
    });
  }
});

// API endpoint to turn off
app.get('/api/mode/off', requireApiKey, (req, res) => {
  try {
    const modeConfig = setMode('off');
    res.json({
      success: true,
      mode: 'off',
      temperature: modeConfig.temp,
      message: 'Machine turned off'
    });
  } catch (err) {
    console.error('Failed to turn off:', err);
    res.status(500).json({
      error: 'Failed to set mode',
      message: err.message
    });
  }
});

// Helper function to determine mode from temperature
function getModeFromTemperature(temp) {
  // Determine mode based on temperature (with some tolerance)
  if (temp === 0) {
    return 'off';
  } else if (temp >= 130) {
    return 'steam';  // Steam mode typically 140°C
  } else {
    return 'espresso';  // Espresso mode typically 100°C
  }
}

// API endpoint to get current mode
app.get('/api/mode', (req, res) => {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    
    // If steam timer is active, we're definitely in steam mode
    // Otherwise use currentMode (which should be accurate)
    const actualMode = steamTimer ? 'steam' : currentMode;
    
    const steamTimeRemaining = steamTimer ? Math.ceil((steamTimer._idleStart + steamTimer._idleTimeout - Date.now()) / 1000) : null;
    
    res.json({
      mode: actualMode,
      target_temperature: config.target_temperature,
      espresso_temperature: config.espresso_temperature || 100,
      steam_temperature: config.steam_temperature || 140,
      steam_time_remaining: steamTimeRemaining,
      machine_state: config.machine_state || 'unknown',
      machine_state_updated: config.machine_state_updated || null
    });
  } catch (err) {
    console.error('Failed to get mode:', err);
    res.status(500).json({
      error: 'Failed to get mode',
      message: err.message
    });
  }
});

// API endpoint to get machine state
app.get('/api/machine-state', (req, res) => {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    
    res.json({
      machine_state: config.machine_state || 'unknown',
      machine_state_updated: config.machine_state_updated || null,
      description: getMachineStateDescription(config.machine_state)
    });
  } catch (err) {
    console.error('Failed to get machine state:', err);
    res.status(500).json({
      error: 'Failed to get machine state',
      message: err.message
    });
  }
});

// Helper function to get human-readable state description
function getMachineStateDescription(state) {
  const descriptions = {
    'off': 'Machine is off (temperature not rising)',
    'heating': 'Machine is heating up (temperature rising)',
    'ready': 'Machine is ready (at or near target temperature)',
    'unknown': 'Machine state unknown'
  };
  return descriptions[state] || 'Unknown state';
}

// Health check endpoint
let lastTemperatureUpdate = Date.now();
let healthStatus = {
  status: 'starting',
  lastCheck: Date.now()
};

// Update health status when temperature readings succeed
function updateHealthStatus(healthy, reason = null) {
  if (healthy) {
    healthStatus = {
      status: 'healthy',
      lastCheck: Date.now(),
      lastTemperatureUpdate: lastTemperatureUpdate
    };
  } else {
    healthStatus = {
      status: 'unhealthy',
      lastCheck: Date.now(),
      reason: reason,
      lastTemperatureUpdate: lastTemperatureUpdate
    };
  }
}

app.get('/health', (req, res) => {
  try {
    const uptime = process.uptime();
    const now = Date.now();
    const timeSinceLastTemp = now - lastTemperatureUpdate;
    
    // Check if MongoDB is connected
    let mongoHealthy = false;
    try {
      mongoHealthy = client && client.topology && client.topology.isConnected();
    } catch (e) {
      mongoHealthy = false;
    }
    
    // Consider unhealthy if no temperature update in 30 seconds
    const tempHealthy = timeSinceLastTemp < 30000;
    
    // Overall health
    const isHealthy = mongoHealthy && tempHealthy;
    
    const health = {
      status: isHealthy ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      uptime: Math.floor(uptime),
      checks: {
        mongodb: {
          status: mongoHealthy ? 'healthy' : 'unhealthy',
          connected: mongoHealthy
        },
        temperature_readings: {
          status: tempHealthy ? 'healthy' : 'unhealthy',
          last_update_seconds_ago: Math.floor(timeSinceLastTemp / 1000),
          threshold_seconds: 30
        },
        web_server: {
          status: 'healthy',
          port: USE_SSL ? HTTPS_PORT : HTTP_PORT,
          ssl: USE_SSL
        }
      },
      details: {
        mode: currentMode,
        steam_timer_active: steamTimer !== null,
        connected_clients: io ? io.sockets.sockets.size : 0
      }
    };
    
    // Return 503 if unhealthy, 200 if healthy
    const statusCode = isHealthy ? 200 : 503;
    res.status(statusCode).json(health);
    
  } catch (err) {
    console.error('Health check error:', err);
    res.status(503).json({
      status: 'unhealthy',
      error: err.message
    });
  }
});

// Track temperature updates for health check
function recordTemperatureUpdate() {
  lastTemperatureUpdate = Date.now();
}

// Track last broadcast time for incremental updates
let lastBroadcastTime = Date.now();

// Track last machine state for change detection
let lastMachineState = null;

// Send current machine state to a client
function sendMachineState(socket) {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    const state = {
      machine_state: config.machine_state || 'unknown',
      machine_state_updated: config.machine_state_updated || null,
      description: getMachineStateDescription(config.machine_state)
    };
    socket.emit('machine_state', state);
  } catch (err) {
    console.error('Error sending machine state:', err);
  }
}

// Broadcast machine state to all connected clients
function broadcastMachineState() {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    const currentState = config.machine_state || 'unknown';
    
    // Only broadcast if state changed
    if (currentState !== lastMachineState) {
      const state = {
        machine_state: currentState,
        machine_state_updated: config.machine_state_updated || null,
        description: getMachineStateDescription(currentState)
      };
      
      io.emit('machine_state', state);
      lastMachineState = currentState;
      
      if (io.sockets.sockets.size > 0) {
        console.log(`Broadcasted machine state change: ${currentState} to ${io.sockets.sockets.size} client(s)`);
      }
    }
  } catch (err) {
    console.error('Error broadcasting machine state:', err);
  }
}

// WebSocket connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);
  
  // Send full history on initial connection
  read(600).then(data => {
    socket.emit('temp_history', data);
    console.log(`Sent ${data.length} historical records to client ${socket.id}`);
  }).catch(err => {
    console.error('Error sending history:', err);
  });
  
  // Send current machine state on connection
  sendMachineState(socket);
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
  
  socket.on('error', (err) => {
    console.error('Socket error:', err);
  });
});

// Poll config.json for machine state changes every 2 seconds
setInterval(broadcastMachineState, 2000);

// Broadcast only new temperature readings
async function broadcastNewReadings() {
  // Skip if no clients connected (Socket.IO v4.x API)
  const connectedClients = io.sockets.sockets.size;
  if (connectedClients === 0) {
    return;
  }
  
  try {
    const newReadings = await getNewReadings(lastBroadcastTime);
    
    if (newReadings.length > 0) {
      io.emit('temp_update', newReadings);
      lastBroadcastTime = Date.now();
      recordTemperatureUpdate(); // Update health check timestamp
      console.log(`Broadcasted ${newReadings.length} new reading(s) to ${connectedClients} client(s)`);
    }
  } catch (err) {
    console.error('Error broadcasting readings:', err);
  }
}

// Get new readings since last broadcast
async function getNewReadings(since) {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    const query = { timestamp: { $gt: since } };
    const options = {
      sort: { timestamp: 1 }, // Ascending order for new readings
      projection: { _id: 0 }
    };
    
    const cursor = collection.find(query, options);
    const result = await cursor.toArray();
    
    return result;
  } catch (err) {
    console.error('Error getting new readings:', err);
    return [];
  }
}

// Get historical readings
async function read(limit) {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');

    // Last hour of data
    const query = { timestamp: { $gt: Date.now() - 3600000 } };

    const options = {
      sort: { timestamp: -1 }, // Most recent first
      limit: limit,
      projection: { _id: 0 }
    };

    const cursor = collection.find(query, options);
    const count = await collection.countDocuments(query);
    
    if (count === 0) {
      console.log('No documents found!');
      return [];
    }

    const result = await cursor.toArray();
    return result.reverse(); // Reverse to get chronological order

  } catch (err) {
    console.error('Error reading from database:', err);
    return [];
  }
}

// Start broadcasting new readings every second
setInterval(broadcastNewReadings, 1000);

// Periodically check for most recent temperature reading to update health check
// This ensures health check works even when machine is off (not recording new data)
async function checkLatestTemperatureReading() {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    // Get the most recent reading (even if it's old)
    const options = {
      sort: { timestamp: -1 }, // Most recent first
      limit: 1,
      projection: { timestamp: 1 }
    };
    
    const latest = await collection.findOne({}, options);
    
    if (latest && latest.timestamp) {
      // Update health check timestamp if reading is recent (within last 5 minutes)
      // This allows health check to work even when machine is off
      const now = Date.now();
      const readingAge = now - latest.timestamp;
      const MAX_READING_AGE = 5 * 60 * 1000; // 5 minutes
      
      if (readingAge < MAX_READING_AGE) {
        lastTemperatureUpdate = latest.timestamp;
      }
    }
  } catch (err) {
    // Silently fail - health check will show unhealthy if MongoDB is down
    if (process.env.DEBUG === 'true') {
      console.error('Error checking latest temperature reading:', err);
    }
  }
}

// Check for latest reading every 10 seconds (independent of WebSocket broadcasts)
setInterval(checkLatestTemperatureReading, 10000);

// Error handling to prevent crashes
process.on('uncaughtException', (err) => {
  console.error('UNCAUGHT EXCEPTION - Web server error:', err);
  console.error('Stack trace:', err.stack);
  // Don't exit - keep the server running
  // Log the error and continue
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('UNHANDLED REJECTION at:', promise);
  console.error('Reason:', reason);
  // Don't exit - keep the server running
  // Log the error and continue
});

// Graceful shutdown handlers
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully...');
  if (server) {
    server.close(() => {
      console.log('HTTP/HTTPS server closed');
      if (client) {
        client.close();
      }
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
});

process.on('SIGINT', () => {
  console.log('SIGINT received, shutting down gracefully...');
  if (server) {
    server.close(() => {
      console.log('HTTP/HTTPS server closed');
      if (client) {
        client.close();
      }
      process.exit(0);
    });
  } else {
    process.exit(0);
  }
});