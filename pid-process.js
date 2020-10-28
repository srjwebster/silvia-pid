const Gpio = require('pigpio').Gpio;
const spawn = require('child_process').spawn;
const fs = require('fs');
const boiler = new Gpio(16, {mode: Gpio.OUTPUT});
const liquidPID = require('liquid-pid');
const MongoClient = require('mongodb').MongoClient;

let SSROutput = 0;
let pidController;
let config_file,
    config,
    target_temp = 35,
    proportional = 3.4,
    derivative = 0.3,
    integral = 40.0;
let i = 1;

const url = 'mongodb://localhost:27017';
// Database Name
const client = new MongoClient(url, {useNewUrlParser: true});

// Use connect method to connect to the server

function insert(temperature, output) {
  client.connect(function(err, mongoClient) {
    const db = mongoClient.db('pid');
    const collection = db.collection('documents');
    // Insert some documents
    collection.insertOne([
      {
        'temperature': temperature,
        'output': output,
        'timestamp': Date.now(),
      }]);
    i++;
    if (i >= 1000) {
      collection.deleteMany({timestamp: {$lt: Date.now() - 86400000}});
    }
  });
  client.close();
}

function getTemp() {
  return new Promise((resolve, reject) => {
    let temp;
    let temperatureProcess = spawn('python3', ['temperature.py']);
    temperatureProcess.stdout.on('data', (data) => {
      temp = data.toString().trim();
    });
    temperatureProcess.on('close', function() {
      SSROutput = Math.round(pidController.calculate(temp));
      boiler.pwmWrite(SSROutput);
      insert(temp, (SSROutput / 255) * 100);
      console.log(temp);
    });
  });
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

  getTemp();

}, 1000);

function exitHandler(options, exitCode) {
  if (options.cleanup) boiler.pwmWrite(0);
  if (options.exit) process.exit();
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
