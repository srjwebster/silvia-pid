# Silvia PID Deployment Guide

Complete guide for deploying the Silvia PID controller on Raspberry Pi.

## Table of Contents
- [Hardware Requirements](#hardware-requirements)
- [Software Prerequisites](#software-prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Testing](#testing)
- [Starting the Service](#starting-the-service)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)

## Hardware Requirements

### Required Components
1. **Raspberry Pi** (tested on Pi 3/4/5)
   - 64-bit Raspberry Pi OS (Bookworm or later recommended)
   - At least 1GB RAM
   - SD card with at least 8GB

2. **MCP9600 Thermocouple Amplifier**
   - I2C address: 0x60 (default)
   - Connected to Raspberry Pi I2C pins:
     - SDA → GPIO 2 (Pin 3)
     - SCL → GPIO 3 (Pin 5)
     - VCC → 3.3V (Pin 1 or 17)
     - GND → Ground (Pin 6, 9, 14, 20, 25, 30, 34, or 39)

3. **K-Type Thermocouple**
   - Connected to MCP9600
   - Attached to Silvia boiler

4. **Solid State Relay (SSR) or Relay Module**
   - Control pin connected to GPIO 16 (Pin 36)
   - Controls Silvia heating element
   - Must be rated for your machine's voltage and current

### Wiring Diagram
```
Raspberry Pi                MCP9600
-----------                 -------
GPIO 2 (SDA) -------------- SDA
GPIO 3 (SCL) -------------- SCL
3.3V        ---------------- VCC
Ground      ---------------- GND

Raspberry Pi                SSR/Relay
-----------                 ---------
GPIO 16     ---------------- Control Input
Ground      ---------------- Control Ground
```

## Software Prerequisites

### Operating System
- **Raspberry Pi OS (64-bit)** - Bookworm or later recommended
  - Download from: https://www.raspberrypi.com/software/
  - Use Raspberry Pi Imager for easy installation
  - MongoDB requires 64-bit OS
  - **Note**: Works with Debian Bookworm and Trixie (installation script compiles pigpio from source)

### Initial Setup
After installing Raspberry Pi OS:

1. Update the system:
```bash
sudo apt-get update
sudo apt-get upgrade -y
```

2. Enable I2C:
```bash
sudo raspi-config
# Navigate to: Interface Options → I2C → Enable
sudo reboot
```

**Important:** I2C device tree overlay changes require a reboot to take effect. After enabling I2C, you must reboot before the `/dev/i2c-1` device will appear.

3. Verify I2C is working:
```bash
# Check I2C modules are loaded
lsmod | grep i2c
# Should see: i2c_bcm2711 (Pi 4/5) or i2c_bcm2835 (Pi 3), and i2c_dev

# Check I2C device exists
ls -l /dev/i2c-1
# Should show: crw-rw---- 1 root i2c 89, 1 /dev/i2c-1

# Scan for I2C devices
sudo i2cdetect -y 1
# Should show device at address 0x60 (MCP9600)
```

**If /dev/i2c-1 is missing:**
- I2C may not be enabled (check config.txt)
- I2C modules may not be loaded (run: `sudo modprobe i2c-bcm2711 i2c-dev` for Pi 4/5, or `sudo modprobe i2c-bcm2835 i2c-dev` for Pi 3)
- Reboot may be required if I2C was just enabled
- Run diagnostic script: `sudo bash scripts/diagnose-i2c.sh`

## Installation

### Automated Installation (Recommended)

1. Clone or copy the repository to your Raspberry Pi:
```bash
cd ~
git clone <repository-url> silvia-pid
cd silvia-pid
```

2. Run the installation script:
```bash
sudo bash deploy/install.sh
```

The script will:
- Install Docker and Docker Compose
- Enable I2C interface
- Set up GPIO and I2C permissions
- Install Python dependencies
- Install Node.js (for validation scripts)
- Copy files to `/opt/silvia-pid`
- Install systemd service
- Run hardware validation

3. Reboot the system:
```bash
sudo reboot
```

### Manual Installation

If you prefer to install manually:

1. Install Docker:
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
```

2. Install Docker Compose:
```bash
sudo apt-get install docker-compose-plugin
```

3. Enable I2C (see above)

4. Install Python dependencies:
```bash
sudo apt-get install python3 python3-pip python3-smbus i2c-tools
pip3 install --break-system-packages mcp9600
```

5. Copy application to `/opt/silvia-pid`

6. Install systemd service:
```bash
sudo cp deploy/silvia-pid.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable silvia-pid
```

## Configuration

### PID Parameters

Edit `/opt/silvia-pid/config.json`:

```json
{
  "target_temperature": 100,
  "proportional": 2.6,
  "integral": 0.8,
  "derivative": 80.0
}
```

**Parameters:**
- `target_temperature`: Desired brew temperature in °C (typically 90-100°C)
- `proportional` (Kp): Proportional gain (affects immediate response)
- `integral` (Ki): Integral gain (eliminates steady-state error)
- `derivative` (Kd): Derivative gain (dampens oscillations)

**Tuning Tips:**
- Start with these defaults and adjust based on your machine
- Increase Kp for faster response
- Increase Ki to eliminate temperature offset
- Increase Kd to reduce overshoot
- Changes take effect within 1 second (config is reloaded automatically)

### Environment Variables (Optional)

Copy `env.example` to `.env` in `/opt/silvia-pid`:

```bash
cd /opt/silvia-pid
cp env.example .env
nano .env
```

Available options:
- `USE_SSL`: Set to `true` to enable HTTPS
- `SSL_KEY_PATH`: Path to SSL private key
- `SSL_CERT_PATH`: Path to SSL certificate
- `HTTP_PORT`: HTTP port (default: 80)
- `HTTPS_PORT`: HTTPS port (default: 443)
- `MONGODB_URL`: MongoDB connection URL (default: mongodb://mongodb:27017)

## Testing

### Test Thermocouple

Before starting the service, verify the thermocouple is working:

```bash
cd /opt/silvia-pid
node scripts/test-thermocouple.js
```

Expected output:
```
=== MCP9600 Thermocouple Test ===

Reading temperature 10 times...

Reading 1/10: 23.45°C ✓
Reading 2/10: 23.50°C ✓
...

=== Test Results ===

Success Rate: 100% (10/10)
Average Temperature: 23.48°C
...

✅ PASSED: Thermocouple is working correctly
```

### Full Hardware Validation

Run the complete hardware validation:

```bash
cd /opt/silvia-pid
node scripts/validate-hardware.js
```

This tests:
- Python installation
- mcp9600 library
- I2C interface
- Thermocouple reading
- GPIO access
- Node.js libraries
- MongoDB connection (optional)
- config.json validity

## Starting the Service

### Start the Service

```bash
sudo systemctl start silvia-pid
```

### Check Status

```bash
sudo systemctl status silvia-pid
```

Expected output:
```
● silvia-pid.service - Silvia PID Controller with Docker Compose
   Loaded: loaded (/etc/systemd/system/silvia-pid.service; enabled)
   Active: active (running) since ...
```

### View Logs

```bash
# Systemd logs
sudo journalctl -u silvia-pid -f

# Docker container logs
cd /opt/silvia-pid
sudo docker compose logs -f
```

### Access Web Interface

Open a browser and navigate to:
- **Local**: `http://raspberrypi.local` or `http://<raspberry-pi-ip>`
- **Custom domain**: `http://your-domain.com` (if configured)

You should see a real-time temperature graph and current temperature reading.

## Monitoring

### Check Container Status

```bash
cd /opt/silvia-pid
sudo docker compose ps
```

Should show two containers running:
- `silvia-pid-app` (PID controller + web server)
- `silvia-mongodb` (database)

### Monitor Temperature

Watch the temperature in real-time:

```bash
cd /opt/silvia-pid
sudo docker compose logs -f silvia-pid
```

You should see output like:
```
Temperature: 95.23°C, Output: 45.2%
Temperature: 95.45°C, Output: 43.8%
...
```

### System Resources

Monitor CPU and memory usage:

```bash
docker stats
```

## Troubleshooting

### Thermocouple Not Reading

**Symptoms**: Temperature read failures, error code 1 or 2

**Solutions**:
1. Check I2C is enabled: `sudo i2cdetect -y 1` should show device at 0x60
2. Verify wiring (SDA, SCL, VCC, GND)
3. Check thermocouple is properly connected to MCP9600
4. Try Python script directly: `python3 temperature.py`

### GPIO Not Working

**Symptoms**: Cannot control relay, "GPIO device not accessible"

**Solutions**:
1. Check pigpiod daemon is running: `sudo systemctl status pigpiod`
2. Start pigpiod if needed: `sudo systemctl start pigpiod`
3. Check user is in gpio group: `groups`
4. Add user to group: `sudo usermod -aG gpio $USER` (logout and login)
5. Check `/dev/gpiomem` permissions: `ls -l /dev/gpiomem`
6. Verify relay wiring to GPIO 16

**Note for Debian Bookworm/Trixie**: The installation script compiles pigpio from source since it's no longer in the repos.

### Container Won't Start

**Symptoms**: Docker container exits immediately

**Solutions**:
1. Check logs: `sudo docker compose logs`
2. Verify devices exist: `ls -l /dev/gpiomem /dev/i2c-1`
3. Check MongoDB is running: `sudo docker compose ps`
4. Rebuild container: `sudo docker compose down && sudo docker compose build --no-cache && sudo docker compose up -d`

### Temperature Out of Range

**Symptoms**: Temperature readings are 0, negative, or >200°C

**Solutions**:
1. Check thermocouple polarity
2. Verify thermocouple is K-type
3. Check for loose connections
4. Test with `node scripts/test-thermocouple.js`

### Web Interface Not Accessible

**Symptoms**: Cannot connect to web interface

**Solutions**:
1. Check service is running: `sudo systemctl status silvia-pid`
2. Check container is running: `sudo docker compose ps`
3. Check port is listening: `sudo netstat -tlnp | grep 80`
4. Check firewall: `sudo ufw status`
5. Try local IP instead of hostname

### MongoDB Connection Failed

**Symptoms**: "Failed to connect to MongoDB" in logs

**Solutions**:
1. Check MongoDB container: `sudo docker compose ps`
2. Check MongoDB logs: `sudo docker compose logs mongodb`
3. Restart containers: `sudo docker compose restart`

### Service Won't Start on Boot

**Symptoms**: Service doesn't start after reboot

**Solutions**:
1. Enable service: `sudo systemctl enable silvia-pid`
2. Check service status: `sudo systemctl status silvia-pid`
3. Check Docker is started: `sudo systemctl status docker`

## Updating

### Update Application Code

1. Stop the service:
```bash
sudo systemctl stop silvia-pid
```

2. Update code in `/opt/silvia-pid`

3. Rebuild containers:
```bash
cd /opt/silvia-pid
sudo docker compose build --no-cache
```

4. Start the service:
```bash
sudo systemctl start silvia-pid
```

### Update System Packages

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

### Update Docker Images

```bash
cd /opt/silvia-pid
sudo docker compose pull
sudo docker compose up -d
```

## Safety Notes

1. **Electrical Safety**: This system controls a high-voltage heating element. Ensure proper electrical installation.

2. **Fail-Safe**: The system automatically shuts off the heater if:
   - 5 consecutive temperature read failures occur
   - Temperature reading is out of range (0-200°C)

3. **Manual Override**: Always maintain a way to manually shut off power to the machine.

4. **Testing**: Thoroughly test the system before leaving it unattended.

5. **Backup**: Keep backups of your `config.json` and any customizations.

## API Endpoints

The web server provides REST API endpoints:

- `GET /` - Web interface
- `GET /api/temp/get/:limit` - Get temperature history (last N readings)
- `GET /api/temp/set/:temp` - Set target temperature
- `GET /api/pid/set/:p-:i-:d` - Set PID parameters (Kp, Ki, Kd)

WebSocket connection provides real-time temperature updates.

## Support

For issues, questions, or contributions, please open an issue on the repository.

