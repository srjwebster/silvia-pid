#!/usr/bin/env node

/**
 * Thermocouple Test Script
 * 
 * Tests the MCP9600 thermocouple to ensure it's working correctly.
 * Reads temperature multiple times and validates the readings.
 */

const { spawn } = require('child_process');
const path = require('path');

const MIN_TEMP = 0.0;
const MAX_TEMP = 200.0;
const NUM_READINGS = 10;
const DELAY_MS = 500;

let readings = [];
let failures = 0;

console.log('=== MCP9600 Thermocouple Test ===\n');
console.log(`Reading temperature ${NUM_READINGS} times...\n`);

function readTemperature() {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(__dirname, '..', 'temperature.py');
    const tempProcess = spawn('python3', [scriptPath]);
    let output = '';
    let errorOutput = '';
    
    const timeout = setTimeout(() => {
      tempProcess.kill();
      reject(new Error('Timeout'));
    }, 5000);
    
    tempProcess.stdout.on('data', (data) => {
      output += data.toString();
    });
    
    tempProcess.stderr.on('data', (data) => {
      errorOutput += data.toString();
    });
    
    tempProcess.on('close', (code) => {
      clearTimeout(timeout);
      
      if (code !== 0) {
        reject(new Error(`Exit code ${code}: ${errorOutput}`));
      } else {
        const temp = parseFloat(output.trim());
        if (isNaN(temp)) {
          reject(new Error(`Invalid temperature: ${output}`));
        } else {
          resolve(temp);
        }
      }
    });
    
    tempProcess.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

async function runTest() {
  for (let i = 1; i <= NUM_READINGS; i++) {
    try {
      const temp = await readTemperature();
      readings.push(temp);
      
      const status = (temp >= MIN_TEMP && temp <= MAX_TEMP) ? '✓' : '✗';
      console.log(`Reading ${i}/${NUM_READINGS}: ${temp.toFixed(2)}°C ${status}`);
      
      if (temp < MIN_TEMP || temp > MAX_TEMP) {
        console.log(`  WARNING: Temperature out of valid range (${MIN_TEMP}-${MAX_TEMP}°C)`);
      }
      
      // Wait before next reading
      if (i < NUM_READINGS) {
        await new Promise(resolve => setTimeout(resolve, DELAY_MS));
      }
    } catch (err) {
      failures++;
      console.log(`Reading ${i}/${NUM_READINGS}: FAILED - ${err.message}`);
    }
  }
  
  console.log('\n=== Test Results ===\n');
  
  if (readings.length === 0) {
    console.log('❌ FAILED: No successful temperature readings');
    console.log('\nPossible issues:');
    console.log('  - MCP9600 not connected or not accessible');
    console.log('  - I2C not enabled (run: sudo raspi-config)');
    console.log('  - Python mcp9600 library not installed (run: pip3 install mcp9600)');
    console.log('  - Wrong I2C address (script uses 0x60)');
    process.exit(1);
  }
  
  const successRate = ((readings.length / NUM_READINGS) * 100).toFixed(1);
  const average = (readings.reduce((a, b) => a + b, 0) / readings.length).toFixed(2);
  const min = Math.min(...readings).toFixed(2);
  const max = Math.max(...readings).toFixed(2);
  const range = (max - min).toFixed(2);
  
  console.log(`Success Rate: ${successRate}% (${readings.length}/${NUM_READINGS})`);
  console.log(`Average Temperature: ${average}°C`);
  console.log(`Min Temperature: ${min}°C`);
  console.log(`Max Temperature: ${max}°C`);
  console.log(`Temperature Range: ${range}°C`);
  
  // Check for stability (range should be small over short period)
  if (parseFloat(range) > 10) {
    console.log('\n⚠️  WARNING: Large temperature variation detected');
    console.log('   This could indicate:');
    console.log('   - Thermocouple not properly attached');
    console.log('   - Electrical noise or interference');
    console.log('   - Faulty thermocouple');
  }
  
  // Check if readings are in valid range
  const invalidReadings = readings.filter(t => t < MIN_TEMP || t > MAX_TEMP);
  if (invalidReadings.length > 0) {
    console.log(`\n⚠️  WARNING: ${invalidReadings.length} reading(s) out of valid range`);
  }
  
  if (failures > 0) {
    console.log(`\n⚠️  WARNING: ${failures} failed reading(s)`);
  }
  
  if (successRate >= 90 && invalidReadings.length === 0 && parseFloat(range) <= 10) {
    console.log('\n✅ PASSED: Thermocouple is working correctly');
    process.exit(0);
  } else if (successRate >= 70) {
    console.log('\n⚠️  PARTIAL: Thermocouple has issues but may work');
    process.exit(1);
  } else {
    console.log('\n❌ FAILED: Thermocouple is not working correctly');
    process.exit(1);
  }
}

runTest().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});

