# Hardware Verification Guide

Step-by-step process to verify I2C pins, thermocouple, and relay on Raspberry Pi.

## Prerequisites

- ✅ Raspberry Pi with Debian Trixie
- ✅ Code deployed to `/opt/silvia-pid`
- ✅ Docker containers running
- ✅ Hardware connected (MCP9600, thermocouple, relay)

---

## Step 1: Verify I2C is Enabled (2 minutes)

### Check I2C Configuration

```bash
# SSH to Pi
ssh pi@192.168.1.100

# Check if I2C is enabled in config.txt
grep dtparam=i2c_arm=on /boot/firmware/config.txt || grep dtparam=i2c_arm=on /boot/config.txt

# Should see:
# dtparam=i2c_arm=on
```

**If not enabled:**
```bash
# Enable I2C via raspi-config (recommended)
sudo raspi-config
# Navigate to: Interface Options → I2C → Yes
# Reboot
sudo reboot

# Or manually enable
echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt
sudo reboot
```

### Check I2C Hardware Module is Loaded

```bash
# Check which Pi model you have
cat /proc/device-tree/model

# Check if I2C hardware module is loaded
lsmod | grep i2c

# Should see:
# i2c_bcm2711  (Pi 4/5)
# OR
# i2c_bcm2835  (Pi 3/Zero)
# i2c_dev      (device module)
```

**If hardware module not loaded:**
```bash
# Determine your Pi model
PI_MODEL=$(cat /proc/device-tree/model)

# Load appropriate module
# For Pi 4/5:
sudo modprobe i2c-bcm2711

# For Pi 3/Zero:
sudo modprobe i2c-bcm2835

# Then load device module
sudo modprobe i2c-dev

# Add to /etc/modules for auto-loading
echo "i2c-bcm2711" | sudo tee -a /etc/modules  # or i2c-bcm2835 for Pi 3
echo "i2c-dev" | sudo tee -a /etc/modules
```

### Check I2C Device Module is Loaded

```bash
# Check if i2c-dev module is loaded
lsmod | grep "^i2c_dev"

# Should see:
# i2c_dev
```

**If not loaded:**
```bash
# Load module
sudo modprobe i2c-dev

# Add to /etc/modules for auto-loading
echo "i2c-dev" | sudo tee -a /etc/modules
```

### Check I2C Device Exists

```bash
# Verify /dev/i2c-1 exists
ls -l /dev/i2c-1

# Should show:
# crw-rw---- 1 root i2c 89, 1 [date] /dev/i2c-1
```

**If missing:**
1. **I2C not enabled in config.txt** - Enable and reboot (see above)
2. **I2C modules not loaded** - Load modules (see above) or reboot
3. **Run diagnostic script:**
   ```bash
   sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh
   ```

### Quick Diagnostic

```bash
# Run automated I2C diagnostic
sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh
```

This script will:
- Check I2C configuration
- Detect Pi model
- Load missing modules
- Verify device file exists
- Check permissions
- Scan for I2C devices

---

## Step 2: Detect MCP9600 on I2C Bus (2 minutes)

### Scan I2C Bus for Devices

```bash
# Install i2c-tools if not already installed
sudo apt-get update
sudo apt-get install -y i2c-tools

# Scan I2C bus 1 (default on Pi 3/4/5)
sudo i2cdetect -y 1
```

**Expected Output:**
```
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
00:          -- -- -- -- -- -- -- -- -- -- -- -- --
10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
60: 60 -- -- -- -- -- -- -- -- -- -- -- -- -- -- --  <-- MCP9600 here!
70: -- -- -- -- -- -- -- --
```

**What to look for:**
- ✅ `60` appears = MCP9600 detected at address 0x60
- ❌ No `60` = Check wiring or I2C address

**If MCP9600 not detected:**

1. **Check wiring:**
   ```
   MCP9600 → Raspberry Pi
   VCC  → Pin 1  (3.3V)
   GND  → Pin 6  (Ground)
   SDA  → Pin 3  (GPIO 2 / SDA)
   SCL  → Pin 5  (GPIO 3 / SCL)
   ```

2. **Check I2C address:**
   - Default MCP9600 address is 0x60
   - If you see a different address (e.g., 0x67), update `temperature.py`:
     ```python
     sensor = mcp9600.MCP9600(0x67)  # Use your address
     ```

3. **Check power:**
   ```bash
   # Measure voltage on MCP9600 VCC pin (should be 3.3V)
   # Use multimeter if available
   ```

4. **Check pull-up resistors:**
   - MCP9600 should have built-in pull-ups
   - If not, add 2.2kΩ resistors on SDA and SCL to 3.3V

---

## Step 3: Test Python Script Directly (3 minutes)

### Test Temperature Reading Script

```bash
# Navigate to app directory
cd /opt/silvia-pid

# Test Python script directly (outside Docker)
python3 temperature.py

# Expected output:
# 23.5
# (Temperature in Celsius)
```

**What you should see:**
- ✅ Number output (e.g., `23.5`) = Thermocouple working!
- ✅ Room temperature (~20-25°C) = Normal
- ✅ Slightly higher (~30-40°C) = Near coffee machine (normal)

**If it errors:**

```bash
# Check Python dependencies
pip3 list | grep mcp9600

# Should show:
# mcp9600  [version]

# If missing:
pip3 install mcp9600 --break-system-packages
```

**Common errors:**

1. **"No module named 'mcp9600'"**
   ```bash
   pip3 install mcp9600 --break-system-packages
   ```

2. **"Device not found" or "I2C error"**
   - Check I2C device detected (Step 2)
   - Check wiring
   - Check I2C address

3. **"Permission denied" on /dev/i2c-1**
   ```bash
   # Add user to i2c group
   sudo usermod -aG i2c $USER
   # Log out and log back in, or:
   newgrp i2c
   ```

4. **"Temperature out of range"**
   - Check thermocouple is connected to MCP9600
   - Check T+ and T- are not swapped
   - Try unplugging and replugging thermocouple

---

## Step 4: Test Inside Docker Container (3 minutes)

### Test from Docker Container

```bash
# Test Python script inside container
sudo docker compose exec silvia-pid python3 temperature.py

# Expected output:
# 23.5
```

**If it works:** Docker can access I2C! ✅

**If it fails:** Check device mounting in docker-compose.yml:

```yaml
devices:
  - /dev/i2c-1:/dev/i2c-1  # Should be present
```

**Also check permissions:**
```bash
# Check /dev/i2c-1 permissions
ls -l /dev/i2c-1

# Should be readable by group i2c
# If not:
sudo chmod 666 /dev/i2c-1  # Temporary fix
# Or add container user to i2c group in Dockerfile
```

---

## Step 5: Run Hardware Validation Script (5 minutes)

### Comprehensive Hardware Test

```bash
# Run validation script
cd /opt/silvia-pid
node scripts/validate-hardware.js
```

**Expected output:**
```
=== Silvia PID Hardware Validation ===

1. Checking Python3 installation...
   ✓ Python3 installed: Python 3.11.2

2. Checking I2C device...
   ✓ I2C device: crw-rw---- 1 root i2c 89, 1 /dev/i2c-1

3. Checking I2C device detection...
   ✓ MCP9600 detected at address 0x60

4. Checking thermocouple reading...
   ✓ Thermocouple reading: 23.5°C (OK)

5. Checking pigpiod daemon...
   ✓ pigpiod daemon is running

6. Checking GPIO pin 16 (Relay)...
   ✓ GPIO pin 16 (Relay) accessible

7. Checking MongoDB connection...
   ✓ MongoDB connection successful

8. Checking config file...
   ✓ Config file loaded and appears valid

=== Validation Summary ===
All essential hardware and software components are working correctly!
```

**If any check fails:**
- Follow the error message
- Refer to troubleshooting section below
- Fix the issue and re-run validation

---

## Step 6: Verify PID Process is Reading Temperatures (5 minutes)

### Check PID Process Logs

```bash
# View live logs from PID process
sudo docker compose logs -f silvia-pid

# Look for temperature readings:
# Temp: 23.5°C, Target: 100°C, Output: 0.0%
# Temp: 24.1°C, Target: 100°C, Output: 0.0%
```

**What you should see:**
- ✅ Temperature readings every second
- ✅ Temperature increasing when heater is on
- ✅ No timeout errors
- ✅ No "Failed to read temperature" errors

**If you see errors:**

1. **"Temperature read timeout"**
   - Check I2C connection
   - Check thermocouple is connected
   - Check MCP9600 power

2. **"Too many consecutive failures"**
   - Sensor is disconnected or faulty
   - Check wiring
   - Test Python script directly (Step 3)

3. **"Temperature out of valid range"**
   - Check thermocouple connection
   - Verify MCP9600 is reading correctly
   - May need to adjust validation range in code

### Check Heater Output

```bash
# Watch logs for output percentage
sudo docker compose logs -f silvia-pid | grep "Output:"

# Should see:
# Output: 0.0%  (when temp > target)
# Output: 50.0% (when heating)
# Output: 100.0% (when cold and heating)
```

**Expected behavior:**
- Room temp (20-25°C) with target 100°C = High output (80-100%)
- As temperature approaches target = Output decreases
- At target temperature = Low output (0-20%)

---

## Step 7: Verify Web UI Shows Data (2 minutes)

### Check Web Interface

Open browser:
```
http://192.168.1.100
```

**What you should see:**
- ✅ Current temperature displayed (e.g., "23.5 °C")
- ✅ Target temperature (e.g., "100.0 °C")
- ✅ Heater output percentage (e.g., "85.2 %")
- ✅ Chart populating with data
- ✅ Connection status: "Connected" (green dot)

**If chart is empty:**
- Check MongoDB is running: `sudo docker ps | grep mongodb`
- Check data is being written: `sudo docker compose exec mongodb mongosh pid --eval "db.temperatures.count()"`
- Wait 10-30 seconds for data to accumulate

**If temperature shows dashes:**
- Check PID process logs (Step 6)
- Check temperature reading works (Step 3)
- Check WebSocket connection (should show "Connected")

---

## Step 8: Test Relay/GPIO Control (5 minutes)

### Verify GPIO 16 is Accessible

```bash
# Check pigpiod is running
sudo systemctl status pigpiod

# Should show: Active: active (running)
```

### Test Relay Control

**⚠️ SAFETY WARNING:**
- The relay controls your coffee machine heater
- Do NOT connect relay to heater until you're ready
- Test with multimeter or LED first

```bash
# Test GPIO from inside container
sudo docker compose exec silvia-pid node -e "
const Gpio = require('pigpio').Gpio;
const relay = new Gpio(16, {mode: Gpio.OUTPUT});

console.log('Turning relay ON...');
relay.digitalWrite(1);  // ON
setTimeout(() => {
  console.log('Turning relay OFF...');
  relay.digitalWrite(0);  // OFF
  process.exit(0);
}, 2000);
"

# Should see relay click (if connected)
# Or measure continuity on relay output
```

**Expected behavior:**
- Relay clicks on/off
- Multimeter shows continuity change
- LED on relay module lights up/dims

**If relay doesn't respond:**
- Check wiring (GPIO 16, power, ground)
- Check pigpiod is running
- Check Docker has GPIO access:
  ```yaml
  devices:
    - /dev/gpiomem:/dev/gpiomem
  privileged: true  # Required for GPIO
  ```

---

## Step 9: Verify Temperature Changes (5 minutes)

### Test Temperature Response

If your coffee machine is connected and ready:

1. **Set target temperature:**
   ```bash
   curl http://192.168.1.100/api/temp/set/100
   ```

2. **Watch temperature increase:**
   ```bash
   # In one terminal, watch logs
   sudo docker compose logs -f silvia-pid | grep "Temp:"
   
   # In another terminal, check web UI
   # Or check API:
   watch -n 1 'curl -s http://192.168.1.100/api/mode | jq .target_temperature'
   ```

3. **Verify heater output:**
   - Output should be high initially (80-100%)
   - As temperature approaches target, output decreases
   - At target, output should be low (0-20%)
   - Temperature should stabilize near target (±1-2°C)

**Expected behavior:**
- Room temp → 100°C takes ~5-10 minutes
- Temperature overshoots slightly, then settles
- Output oscillates around setpoint (PID control)
- Stable temperature maintained

---

## Step 10: Run Full System Test (10 minutes)

### Complete Validation

```bash
# 1. Run hardware validation
cd /opt/silvia-pid
node scripts/validate-hardware.js

# 2. Check all services
sudo docker ps
# Should show: silvia-pid-app, mongodb, uptime-kuma (all healthy)

# 3. Check systemd service
sudo systemctl status silvia-pid
# Should show: Active: active (exited)

# 4. Test API endpoints
curl http://192.168.1.100/health
curl http://192.168.1.100/api/mode
curl http://192.168.1.100/api/temp/set/100

# 5. Check web UI
# Open: http://192.168.1.100
# Should show live temperature data

# 6. Check logs (no errors)
sudo docker compose logs --tail 100 silvia-pid | grep -i error
# Should show minimal or no errors
```

**All tests passing = System is ready! ✅**

---

## Troubleshooting

### I2C Device Not Found (/dev/i2c-1 missing)

**Symptoms:** `/dev/i2c-1` does not exist, I2C modules not loaded

**Root Causes:**
1. I2C not enabled in config.txt
2. I2C hardware module not loaded (i2c-bcm2711 or i2c-bcm2835)
3. I2C device module not loaded (i2c-dev)
4. Reboot required after enabling I2C

**Solutions:**

1. **Run diagnostic script:**
   ```bash
   sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh
   ```
   This will check and fix most issues automatically.

2. **Check I2C configuration:**
   ```bash
   # Check if I2C is enabled
   grep dtparam=i2c_arm=on /boot/firmware/config.txt || grep dtparam=i2c_arm=on /boot/config.txt
   
   # If not found, enable it
   echo "dtparam=i2c_arm=on" | sudo tee -a /boot/firmware/config.txt
   sudo reboot
   ```

3. **Load I2C modules manually:**
   ```bash
   # Detect Pi model
   PI_MODEL=$(cat /proc/device-tree/model)
   
   # Load hardware module (Pi 4/5)
   sudo modprobe i2c-bcm2711
   
   # OR (Pi 3/Zero)
   sudo modprobe i2c-bcm2835
   
   # Load device module
   sudo modprobe i2c-dev
   
   # Verify device exists
   ls -l /dev/i2c-1
   ```

4. **Add modules to /etc/modules for auto-loading:**
   ```bash
   # Add hardware module (use appropriate one for your Pi)
   echo "i2c-bcm2711" | sudo tee -a /etc/modules  # Pi 4/5
   # OR
   echo "i2c-bcm2835" | sudo tee -a /etc/modules  # Pi 3/Zero
   
   # Add device module
   echo "i2c-dev" | sudo tee -a /etc/modules
   ```

5. **Reboot if I2C was just enabled:**
   ```bash
   sudo reboot
   ```

6. **Verify after reboot:**
   ```bash
   # Check modules are loaded
   lsmod | grep i2c
   
   # Check device exists
   ls -l /dev/i2c-1
   
   # Scan for devices
   sudo i2cdetect -y 1
   ```

### MCP9600 Not Detected

**Symptoms:** `i2cdetect -y 1` shows no device at 0x60

**Solutions:**
1. **Check I2C device exists first** (see above troubleshooting)
2. Check wiring (VCC, GND, SDA, SCL)
3. Check power (3.3V on VCC pin)
4. Verify I2C is enabled: `sudo raspi-config`
5. Check I2C address (may be different)
6. Try another MCP9600 board (could be faulty)

### Temperature Reading Fails

**Symptoms:** Python script errors or returns invalid values

**Solutions:**
1. Test Python script directly (Step 3)
2. Check thermocouple connection (T+, T-)
3. Check I2C permissions: `sudo usermod -aG i2c $USER`
4. Verify MCP9600 is detected (Step 2)
5. Check thermocouple type (should be K-type)
6. Try unplugging/replugging thermocouple

### Docker Can't Access I2C

**Symptoms:** Works outside Docker, fails inside container

**Solutions:**
1. Check docker-compose.yml has:
   ```yaml
   devices:
     - /dev/i2c-1:/dev/i2c-1
   ```
2. Check permissions: `ls -l /dev/i2c-1`
3. Restart Docker: `sudo systemctl restart docker`
4. Rebuild container: `sudo docker compose build --no-cache`

### Relay Not Responding

**Symptoms:** No click, no continuity change

**Solutions:**
1. Check pigpiod is running: `sudo systemctl status pigpiod`
2. Check wiring (GPIO 16, power, ground)
3. Check Docker has GPIO access:
   ```yaml
   devices:
     - /dev/gpiomem:/dev/gpiomem
   privileged: true
   ```
4. Test relay module with multimeter
5. Try different GPIO pin (update code if needed)

### Temperature Stuck at Room Temp

**Symptoms:** Temperature doesn't increase when heater is on

**Solutions:**
1. Check thermocouple is attached to boiler (not just hanging)
2. Check heater is actually on (relay clicking, power to heater)
3. Wait longer (boiler takes 5-10 minutes to heat)
4. Verify thermocouple type (K-type for high temps)
5. Check for air gaps between thermocouple and boiler

### Web UI Shows No Data

**Symptoms:** Chart empty, temperature shows dashes

**Solutions:**
1. Check MongoDB is running: `sudo docker ps | grep mongodb`
2. Check data is being written:
   ```bash
   sudo docker compose exec mongodb mongosh pid --eval "db.temperatures.count()"
   ```
3. Wait 10-30 seconds for data to accumulate
4. Check WebSocket connection (should show "Connected")
5. Refresh browser (hard refresh: Ctrl+Shift+R)

---

## Quick Verification Checklist

Run through this checklist after hardware is connected:

- [ ] I2C enabled: `lsmod | grep i2c`
- [ ] MCP9600 detected: `sudo i2cdetect -y 1` shows `60`
- [ ] Python script works: `python3 temperature.py` outputs temperature
- [ ] Docker can read I2C: `sudo docker compose exec silvia-pid python3 temperature.py`
- [ ] Hardware validation passes: `node scripts/validate-hardware.js`
- [ ] PID process logs show temperatures: `sudo docker compose logs -f silvia-pid`
- [ ] Web UI shows data: `http://192.168.1.100`
- [ ] Relay responds: Test GPIO control
- [ ] Temperature increases when heater on (if connected)
- [ ] Health endpoint works: `curl http://192.168.1.100/health`

**All checked = Hardware is verified and working! ✅**

---

## Next Steps

Once hardware is verified:

1. ✅ **Test PID control** - Set target temperature and watch it stabilize
2. ✅ **Calibrate PID parameters** - Tune Kp, Ki, Kd if needed
3. ✅ **Test steam mode** - Switch to 140°C and verify timeout
4. ✅ **Set up SSL** - Enable HTTPS (see SSL_SETUP.md)
5. ✅ **Set up monitoring** - Configure Uptime Kuma (see UPTIME_KUMA_SETUP.md)
6. ✅ **Test Google Assistant** - Set up IFTTT (see SSL_SETUP.md)

**Your coffee machine is now fully operational! ☕✅**

