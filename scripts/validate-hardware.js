#!/usr/bin/env node

/**
 * Hardware Validation Script
 * 
 * Validates all hardware components required for the Silvia PID controller:
 * - MCP9600 thermocouple (I2C)
 * - GPIO pin 16 (relay/SSR control)
 * - Python installation and mcp9600 library
 * - MongoDB connection (if available)
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

let allTestsPassed = true;

console.log('=== Silvia PID Hardware Validation ===\n');

// Test 1: Check if Python3 is installed
async function testPython() {
  console.log('1. Checking Python3 installation...');
  return new Promise((resolve) => {
    const python = spawn('python3', ['--version']);
    let output = '';
    
    python.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    python.stderr.on('data', (data) => {
      output += data.toString();
    });
    
    python.on('close', (code) => {
      if (code === 0) {
        console.log(`   ✓ Python3 installed: ${output.trim()}`);
        resolve(true);
      } else {
        console.log('   ✗ Python3 not found');
        console.log('     Install with: sudo apt-get install python3');
        allTestsPassed = false;
        resolve(false);
      }
    });
    
    python.on('error', () => {
      console.log('   ✗ Python3 not found');
      allTestsPassed = false;
      resolve(false);
    });
  });
}

// Test 2: Check if mcp9600 Python library is installed
async function testMCP9600Library() {
  console.log('\n2. Checking mcp9600 Python library...');
  return new Promise((resolve) => {
    const python = spawn('python3', ['-c', 'import mcp9600; print("OK")']);
    let output = '';
    let error = '';
    
    python.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    python.stderr.on('data', (data) => {
      error += data.toString();
    });
    
    python.on('close', (code) => {
      if (code === 0 && output.includes('OK')) {
        console.log('   ✓ mcp9600 library installed');
        resolve(true);
      } else {
        console.log('   ✗ mcp9600 library not found');
        console.log('     Install with: pip3 install mcp9600');
        allTestsPassed = false;
        resolve(false);
      }
    });
    
    python.on('error', () => {
      console.log('   ✗ Failed to check mcp9600 library');
      allTestsPassed = false;
      resolve(false);
    });
  });
}

// Test 3: Check if I2C is enabled
async function testI2C() {
  console.log('\n3. Checking I2C interface...');
  return new Promise((resolve) => {
    fs.access('/dev/i2c-1', fs.constants.R_OK | fs.constants.W_OK, (err) => {
      if (err) {
        console.log('   ✗ I2C device /dev/i2c-1 not accessible');
        console.log('     Enable I2C with: sudo raspi-config');
        console.log('     Navigate to: Interface Options -> I2C -> Enable');
        console.log('     Then reboot');
        allTestsPassed = false;
        resolve(false);
      } else {
        console.log('   ✓ I2C device /dev/i2c-1 accessible');
        resolve(true);
      }
    });
  });
}

// Test 4: Try to read from MCP9600 thermocouple
async function testThermocouple() {
  console.log('\n4. Testing MCP9600 thermocouple...');
  return new Promise((resolve) => {
    const scriptPath = path.join(__dirname, '..', 'temperature.py');
    const tempProcess = spawn('python3', [scriptPath]);
    let output = '';
    let errorOutput = '';
    
    const timeout = setTimeout(() => {
      tempProcess.kill();
      console.log('   ✗ Thermocouple read timeout');
      allTestsPassed = false;
      resolve(false);
    }, 5000);
    
    tempProcess.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    tempProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });
    
    tempProcess.on('close', (code) => {
      clearTimeout(timeout);
      
      if (code === 0) {
        const temp = parseFloat(output.trim());
        if (!isNaN(temp)) {
          console.log(`   ✓ Thermocouple reading: ${temp.toFixed(2)}°C`);
          if (temp < 0 || temp > 200) {
            console.log('     ⚠ WARNING: Temperature reading seems unusual');
            console.log('       Check thermocouple connection');
          }
          resolve(true);
        } else {
          console.log(`   ✗ Invalid temperature reading: ${output}`);
          allTestsPassed = false;
          resolve(false);
        }
      } else {
        console.log(`   ✗ Thermocouple read failed: ${errorOutput}`);
        console.log('     Check:');
        console.log('       - MCP9600 is connected to I2C pins');
        console.log('       - I2C address is correct (0x60)');
        console.log('       - Wiring is correct (SDA, SCL, VCC, GND)');
        allTestsPassed = false;
        resolve(false);
      }
    });
  });
}

// Test 5: Check GPIO access
async function testGPIO() {
  console.log('\n5. Checking GPIO access...');
  return new Promise((resolve) => {
    fs.access('/dev/gpiomem', fs.constants.R_OK | fs.constants.W_OK, (err) => {
      if (err) {
        console.log('   ✗ GPIO device /dev/gpiomem not accessible');
        console.log('     User needs to be in gpio group:');
        console.log('     sudo usermod -a -G gpio $USER');
        console.log('     Then log out and back in');
        allTestsPassed = false;
        resolve(false);
      } else {
        console.log('   ✓ GPIO device /dev/gpiomem accessible');
        resolve(true);
      }
    });
  });
}

// Test 6: Check if pigpio library is installed (Node.js)
async function testPigpioLibrary() {
  console.log('\n6. Checking pigpio Node.js library...');
  try {
    require('pigpio');
    console.log('   ✓ pigpio library installed');
    return true;
  } catch (err) {
    console.log('   ✗ pigpio library not found');
    console.log('     Install with: npm install');
    allTestsPassed = false;
    return false;
  }
}

// Test 7: Check MongoDB connection (optional for initial setup)
async function testMongoDB() {
  console.log('\n7. Checking MongoDB connection (optional)...');
  try {
    const MongoClient = require('mongodb').MongoClient;
    const url = process.env.MONGODB_URL || 'mongodb://localhost:27017';
    
    const client = new MongoClient(url, {
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 3000
    });
    
    await client.connect();
    console.log('   ✓ MongoDB connection successful');
    await client.close();
    return true;
  } catch (err) {
    console.log('   ⚠ MongoDB connection failed (not critical for hardware test)');
    console.log(`     ${err.message}`);
    console.log('     MongoDB will be needed for production deployment');
    return false;
  }
}

// Test 8: Check config.json exists
async function testConfig() {
  console.log('\n8. Checking config.json...');
  const configPath = path.join(__dirname, '..', 'config.json');
  return new Promise((resolve) => {
    fs.access(configPath, fs.constants.R_OK, (err) => {
      if (err) {
        console.log('   ✗ config.json not found');
        console.log('     Create config.json with PID parameters');
        allTestsPassed = false;
        resolve(false);
      } else {
        try {
          const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
          console.log('   ✓ config.json found and valid');
          console.log(`     Target temperature: ${config.target_temperature}°C`);
          console.log(`     PID: Kp=${config.proportional}, Ki=${config.integral}, Kd=${config.derivative}`);
          resolve(true);
        } catch (parseErr) {
          console.log('   ✗ config.json is invalid JSON');
          allTestsPassed = false;
          resolve(false);
        }
      }
    });
  });
}

// Run all tests
async function runValidation() {
  await testPython();
  await testMCP9600Library();
  await testI2C();
  await testThermocouple();
  await testGPIO();
  await testPigpioLibrary();
  await testMongoDB();
  await testConfig();
  
  console.log('\n=== Validation Summary ===\n');
  
  if (allTestsPassed) {
    console.log('✅ All critical hardware tests passed!');
    console.log('   System is ready for deployment.');
    process.exit(0);
  } else {
    console.log('❌ Some tests failed.');
    console.log('   Fix the issues above before deploying.');
    process.exit(1);
  }
}

runValidation().catch(err => {
  console.error('\nValidation error:', err);
  process.exit(1);
});

