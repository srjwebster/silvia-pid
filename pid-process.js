const Gpio = require('pigpio').Gpio;
const spawn = require('child_process').spawn;
const fs = require('fs');
const boiler = new Gpio(16, {mode: Gpio.OUTPUT}); 
const liquidPID = require('liquid-pid');
const MongoClient = require('mongodb').MongoClient;

// Temperature validation constants
const MIN_TEMP = 0.0;
const MAX_TEMP = 200.0;
const TEMP_READ_TIMEOUT = 5000; // 5 seconds
const MAX_CONSECUTIVE_FAILURES = 5;

let SSROutput = 0;
let pidController;
let config_file,
    config,
    target_temp = 35,
    proportional = 3.4,
    derivative = 0.3,
    integral = 40.0;
let i = 1;
let consecutiveFailures = 0;
let lastValidTemperature = null;

const url = process.env.MONGODB_URL || 'mongodb://localhost:27017';
// Database Name
const client = new MongoClient(url, {useUnifiedTopology: true});
client.connect().then(() => {
});

// Use connect method to connect to the server
async function insert(temperature, output) {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    await collection.insertOne(
        {
          'temperature': temperature,
          'output': output,
          'timestamp': Date.now(),
        }).catch(function(err) {
      console.log(err);
    });
    i++;
    if (i >= 1000) {
      await collection.deleteMany({timestamp: {$lt: Date.now() - 86400000}});
      i = 1;
    }
  } catch (e) {
    console.log(e);
  } finally {

  }
}

setInterval(() => {
  config_file = fs.readFileSync('config.json');
  config = JSON.parse(config_file.toString());
  target_temp = config['target_temperature'];
  proportional = config['proportional'];
  derivative = config['derivative'];
  integral = config['integral'];

  pidController = new liquidPID({
    // Point temperature
    temp: {
      ref: target_temp,
    },
    Pmax: 255,       // Max power (output),
    // Tune the PID Controller
    Kp: proportional,           // PID: Kp
    Ki: derivative,         // PID: Ki
    Kd: integral,             // PID: Kd
  });

  getTemp(function(temperature) {
    SSROutput = Math.round(pidController.calculate(temperature));
    boiler.pwmWrite(SSROutput);
    insert(temperature, (SSROutput / 255) * 100).then(() => {
      console.log(`Temperature: ${temperature}°C, Output: ${(SSROutput / 255) * 100}%`);
    }).catch(err => {
      console.error('Failed to insert temperature data:', err);
    });
  }).catch(err => {
    console.error('Failed to read temperature:', err.message);
    // Don't update PID or heater if temperature read failed
  });

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
      
      if (temperature < MIN_TEMP || temperature > MAX_TEMP) {
        console.error(`ERROR: Temperature ${temperature}°C out of valid range (${MIN_TEMP}-${MAX_TEMP}°C)`);
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

function exitHandler(options, exitCode) {

  if (options.cleanup) boiler.pwmWrite(0);
  if (options.exit) process.exit();
  client.close();
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
