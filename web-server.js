// import required packages
const express = require('express');
const cors = require('cors');
const https = require('https');
const http = require('http');
const mongoClient = require('mongodb').MongoClient();
const fs = require('fs');
// create new express app and save it as "app"
const app = express();
app.use(cors());

async function read(limit) {

  let database = await mongoClient.connect('mongodb://localhost:27017/pid');
  let read = await database.collection('temperatures').
      find({'timestamp': {$gt: Date.now() - 3600000}}).
      sort({'timestamp': -1}).
      limit(limit);
  let result = read.toArray();
  database.close();

  return result;

}

// create a route for the app
app.get('/', (req, res) => {
  res.send(``);
});

// another route
app.get('/api/temp/set/:temp', (req, res) => {
  res.send(req.params);
});
app.get('/api/temp/get/:limit', (req, res) => {
  read(parseInt(req.params.limit)).then(r => {
    console.log(r);
    res.send(r);
  });

});
app.get('/api/pid/set/:p-:i-:d', (req, res) => {
  res.send(req.params);
});

// Listen both http & https ports
const httpServer = http.createServer(app);
const httpsServer = https.createServer({
  key: fs.readFileSync(
      '/etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem'),
  cert: fs.readFileSync(
      '/etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem'),
}, app);

httpServer.listen(80, () => {
  console.log('HTTP Server running on port 80');
});

httpsServer.listen(443, () => {
  console.log('HTTPS Server running on port 443');
});