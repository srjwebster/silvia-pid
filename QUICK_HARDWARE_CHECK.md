# Quick Hardware Check - Reference Card

Fast commands to verify hardware after deployment.

## 1. Check I2C Device (30 seconds)

### Check I2C Configuration
```bash
# Check if I2C is enabled in config.txt
grep dtparam=i2c_arm=on /boot/firmware/config.txt || grep dtparam=i2c_arm=on /boot/config.txt
```

### Check I2C Modules Loaded
```bash
# Check which Pi model
cat /proc/device-tree/model

# Check if I2C hardware module is loaded
lsmod | grep i2c

# Should see:
# i2c_bcm2711  (Pi 4/5)
# OR
# i2c_bcm2835  (Pi 3/Zero)
# i2c_dev      (device module)
```

### Check I2C Device Exists
```bash
# Check if /dev/i2c-1 exists
ls -l /dev/i2c-1

# Should show: crw-rw---- 1 root i2c 89, 1 /dev/i2c-1
```

### Load I2C Modules (if missing)
```bash
# For Pi 4/5:
sudo modprobe i2c-bcm2711 i2c-dev

# For Pi 3/Zero:
sudo modprobe i2c-bcm2835 i2c-dev

# Verify device exists
ls -l /dev/i2c-1
```

### Scan I2C Bus
```bash
# Scan I2C bus for MCP9600
sudo i2cdetect -y 1

# Should show: 60 (MCP9600 at address 0x60)
```

**If no `60`:**
- Check I2C device exists: `ls -l /dev/i2c-1`
- Check I2C modules loaded: `lsmod | grep i2c`
- Check wiring (VCC→3.3V, GND→Ground, SDA→GPIO2, SCL→GPIO3)
- Check I2C enabled: `sudo raspi-config` → Interface Options → I2C
- Run diagnostic: `sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh`

---

## 2. Test Temperature Reading (30 seconds)

```bash
# Test Python script
cd /opt/silvia-pid
python3 temperature.py

# Should output: 23.5 (temperature in °C)
```

**If error:**
- Install: `pip3 install mcp9600 --break-system-packages`
- Check I2C: `sudo i2cdetect -y 1`

---

## 3. Test from Docker (30 seconds)

```bash
# Test from inside container
cd /opt/silvia-pid
sudo docker compose exec silvia-pid python3 temperature.py

# Should output: 23.5
```

**If error:**
- Check docker-compose.yml has: `devices: - /dev/i2c-1:/dev/i2c-1`
- Restart: `sudo docker compose restart silvia-pid`

---

## 4. Check PID Process Logs (1 minute)

```bash
# Watch live temperature readings
cd /opt/silvia-pid
sudo docker compose logs -f silvia-pid

# Look for: Temp: 23.5°C, Target: 100°C, Output: 0.0%
```

**Should see:**
- ✅ Temperature readings every second
- ✅ No timeout errors
- ✅ No "Failed to read temperature" errors

---

## 5. Run Validation Script (2 minutes)

```bash
# Comprehensive hardware test
cd /opt/silvia-pid
chmod +x verify-hardware.sh
./verify-hardware.sh

# Or use Node.js validation:
node scripts/validate-hardware.js
```

**Should show:** All checks passing ✓

---

## 6. Check Web UI (30 seconds)

```
Open: http://192.168.1.100
```

**Should see:**
- ✅ Current temperature displayed
- ✅ Chart populating with data
- ✅ Connection status: Connected (green dot)

---

## Quick Troubleshooting

### I2C Device Not Found
```bash
# Run diagnostic script
sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh

# Check I2C enabled in config.txt
grep dtparam=i2c_arm=on /boot/firmware/config.txt || grep dtparam=i2c_arm=on /boot/config.txt

# Load I2C modules (Pi 4/5)
sudo modprobe i2c-bcm2711 i2c-dev

# Load I2C modules (Pi 3/Zero)
sudo modprobe i2c-bcm2835 i2c-dev

# Check device exists
ls -l /dev/i2c-1

# Reboot if I2C was just enabled
sudo reboot
```

### MCP9600 Not Detected
```bash
# Check I2C device exists first (see above)
ls -l /dev/i2c-1

# Check I2C enabled
sudo raspi-config  # Interface Options → I2C → Yes

# Check wiring
# VCC → Pin 1 (3.3V)
# GND → Pin 6 (Ground)
# SDA → Pin 3 (GPIO 2)
# SCL → Pin 5 (GPIO 3)

# Run diagnostic
sudo bash /opt/silvia-pid/scripts/diagnose-i2c.sh
```

### Temperature Reading Fails
```bash
# Install Python library
pip3 install mcp9600 --break-system-packages

# Check permissions
sudo usermod -aG i2c $USER
newgrp i2c

# Test again
python3 temperature.py
```

### Docker Can't Read I2C
```bash
# Check docker-compose.yml has:
# devices:
#   - /dev/i2c-1:/dev/i2c-1

# Restart container
sudo docker compose restart silvia-pid
```

### No Data in Web UI
```bash
# Check MongoDB
sudo docker ps | grep mongodb

# Check data is being written
sudo docker compose exec mongodb mongosh pid --eval "db.temperatures.count()"

# Wait 10-30 seconds for data to accumulate
```

---

## All-in-One Verification

```bash
# Run automated verification script
cd /opt/silvia-pid
chmod +x verify-hardware.sh
./verify-hardware.sh
```

This runs all checks and shows a summary.

---

## Expected Output When Working

```
✓ I2C module loaded
✓ I2C device /dev/i2c-1 exists
✓ MCP9600 detected at address 0x60
✓ Temperature reading: 23.5°C
✓ Temperature in valid range (0-200°C)
✓ pigpiod daemon is running
✓ GPIO device /dev/gpiomem exists
✓ Silvia PID container is running
✓ MongoDB container is running
✓ Docker temperature reading: 23.5°C
✓ PID process is reading temperatures
✓ Web interface accessible (HTTP 200)

All checks passed! Hardware is working correctly.
```

---

## Next Steps

Once hardware is verified:

1. **Test PID control:**
   ```bash
   curl http://192.168.1.100/api/temp/set/100
   # Watch temperature increase in logs or web UI
   ```

2. **Test modes:**
   ```bash
   curl http://192.168.1.100/api/mode/espresso
   curl http://192.168.1.100/api/mode/steam
   ```

3. **Monitor system:**
   ```bash
   # Watch logs
   sudo docker compose logs -f silvia-pid
   
   # Check web UI
   # Open: http://192.168.1.100
   ```

**For detailed troubleshooting, see `HARDWARE_VERIFICATION.md`**

