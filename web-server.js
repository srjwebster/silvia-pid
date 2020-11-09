// import required packages
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const MongoClient = require('mongodb').MongoClient;
// create new express app and save it as "app"
const app = express();
// Listen both http & https ports
const https = require('https');
const httpsServer = https.createServer({
  key: fs.readFileSync(
      '/etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem'),
  cert: fs.readFileSync(
      '/etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem'),
  requestCert: false,
  rejectUnauthorized: false,
}, app);
httpsServer.listen(443, () => {
  console.log('HTTPS Server running on port 443');
});


let http = express();
http.get('*', function(req, res) {
  res.redirect('https://' + req.headers.host + req.url);
})
http.listen(80, () => {
  console.log("Port 80 redirect");
});


const io = require('socket.io').listen(httpsServer);
const client = new MongoClient('mongodb://localhost',
    {useUnifiedTopology: true});
client.connect().then(() => {
});

app.use(cors());
// create a route for the app
app.get('/', (req, res) => {
  res.sendFile(__dirname + '/index.html');
});

// another route
app.get('/api/temp/set/:temp', (req, res) => {
  res.send(req.params);
});
app.get('/api/temp/get/:limit', (req, res) => {
  read(parseInt(req.params.limit)).then(temps => {
    //console.log(temps);
    res.send(temps);
  });

});
app.get('/api/pid/set/:p-:i-:d', (req, res) => {
  res.send(req.params);
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