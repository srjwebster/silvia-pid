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

function emitToSockets(){
  read(600).then(function(response){
    io.emit('temp_refresh', response);
  })
  setTimeout(emitToSockets, 3000);
}

emitToSockets();
async function read(limit) {
  let result;
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');

    // ten minutes in milliseconds
    const query = {'timestamp': {$gt: Date.now() - 3600000}};

    const options = {
      // sort returned documents in reverse timestamp order (most recent first)
      sort: {timestamp: -1},
      // only give us the limited number
      limit: limit,
      // Don't include the _id field
      projection: {_id: 0},
    };

    const cursor = await collection.find(query, options);

    // print a message if no documents were found
    if ((await cursor.count()) === 0) {
      console.log('No documents found!');
    }

    result = await cursor.toArray();

  } catch (err) {
    console.log(err);
  } finally {

  }

  return result;
}