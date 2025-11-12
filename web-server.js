// import required packages
const express = require('express');
const cors = require('cors');
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

// create new express app and save it as "app"
const app = express();
app.use(cors());
app.use(express.json()); // Add JSON body parsing for API endpoints

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

io = require('socket.io').listen(server);

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

// API endpoint to set target temperature
app.get('/api/temp/set/:temp', (req, res) => {
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
    config.target_temperature = temp;
    
    // Write updated config
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
    
    console.log(`Target temperature updated to ${temp}°C`);
    res.json({
      success: true,
      target_temperature: temp,
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

// API endpoint to set PID parameters
app.get('/api/pid/set/:p-:i-:d', (req, res) => {
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
    
    // Write updated config
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
    
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

// Mode management
let currentMode = 'espresso';
let steamTimer = null;
const STEAM_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes default

// Helper function to set mode
function setMode(mode, duration = null) {
  const modes = {
    espresso: { temp: 100, name: 'Espresso' },
    steam: { temp: 140, name: 'Steam' },
    off: { temp: 0, name: 'Off' }
  };
  
  if (!modes[mode]) {
    throw new Error('Invalid mode');
  }
  
  const modeConfig = modes[mode];
  
  // Update temperature
  const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  config.target_temperature = modeConfig.temp;
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2));
  
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
  
  console.log(`Mode changed to: ${modeConfig.name} (${modeConfig.temp}°C)`);
  return modeConfig;
}

// API endpoint to set mode to espresso
app.get('/api/mode/espresso', (req, res) => {
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
app.get('/api/mode/steam/:duration?', (req, res) => {
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
app.get('/api/mode/off', (req, res) => {
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

// API endpoint to get current mode
app.get('/api/mode', (req, res) => {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    const steamTimeRemaining = steamTimer ? Math.ceil((steamTimer._idleStart + steamTimer._idleTimeout - Date.now()) / 1000) : null;
    
    res.json({
      mode: currentMode,
      target_temperature: config.target_temperature,
      steam_time_remaining: steamTimeRemaining
    });
  } catch (err) {
    console.error('Failed to get mode:', err);
    res.status(500).json({
      error: 'Failed to get mode',
      message: err.message
    });
  }
});

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
        connected_clients: io ? io.engine.clientsCount : 0
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
  
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
  
  socket.on('error', (err) => {
    console.error('Socket error:', err);
  });
});

// Broadcast only new temperature readings
async function broadcastNewReadings() {
  // Skip if no clients connected
  if (io.engine.clientsCount === 0) {
    return;
  }
  
  try {
    const newReadings = await getNewReadings(lastBroadcastTime);
    
    if (newReadings.length > 0) {
      io.emit('temp_update', newReadings);
      lastBroadcastTime = Date.now();
      recordTemperatureUpdate(); // Update health check timestamp
      console.log(`Broadcasted ${newReadings.length} new reading(s) to ${io.engine.clientsCount} client(s)`);
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