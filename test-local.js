#!/usr/bin/env node
/**
 * Local Test Script
 * Tests web server endpoints without requiring full hardware/MongoDB setup
 */

const express = require('express');
const app = express();
const PORT = 3000;

// Mock health endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy (test mode)',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    checks: {
      web_server: {
        status: 'healthy',
        port: PORT
      },
      mongodb: {
        status: 'not connected (test mode)',
        connected: false
      },
      temperature_readings: {
        status: 'not available (test mode)',
        note: 'Requires hardware'
      }
    },
    note: 'This is a local test server. Deploy to Pi for full functionality.'
  });
});

// Mock mode endpoint
app.get('/api/mode', (req, res) => {
  res.json({
    mode: 'espresso',
    target_temperature: 100,
    note: 'Test mode - not connected to hardware'
  });
});

// Mock mode set endpoints
app.get('/api/mode/espresso', (req, res) => {
  res.json({
    success: true,
    mode: 'espresso',
    temperature: 100,
    message: 'Test mode - would switch to espresso'
  });
});

app.get('/api/mode/steam/:duration?', (req, res) => {
  const duration = req.params.duration || 300;
  res.json({
    success: true,
    mode: 'steam',
    temperature: 140,
    timeout_seconds: duration,
    message: 'Test mode - would switch to steam'
  });
});

// Serve index.html
app.get('/', (req, res) => {
  res.sendFile(__dirname + '/index.html');
});

// Start server
app.listen(PORT, () => {
  console.log('='.repeat(50));
  console.log('Silvia PID - Local Test Server');
  console.log('='.repeat(50));
  console.log('');
  console.log(`Server running at: http://localhost:${PORT}`);
  console.log('');
  console.log('Test endpoints:');
  console.log(`  - http://localhost:${PORT}/`);
  console.log(`  - http://localhost:${PORT}/health`);
  console.log(`  - http://localhost:${PORT}/api/mode`);
  console.log(`  - http://localhost:${PORT}/api/mode/espresso`);
  console.log(`  - http://localhost:${PORT}/api/mode/steam`);
  console.log('');
  console.log('Note: This is a test server without hardware/MongoDB.');
  console.log('      Deploy to Raspberry Pi for full functionality.');
  console.log('');
  console.log('Press Ctrl+C to stop');
  console.log('='.repeat(50));
});

