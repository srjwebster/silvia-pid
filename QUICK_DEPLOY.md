# Quick Deployment Guide for Raspberry Pi (Debian Trixie)

## Transfer Files to Raspberry Pi

From your development machine:

```bash
# Using rsync (recommended)
cd /home/sam/Code/silvia-pid
rsync -avz --exclude 'node_modules' --exclude 'silvia-pid/' --exclude '.git' . pi@192.168.1.100:~/silvia-pid

# OR using scp
scp -r . pi@192.168.1.100:~/silvia-pid
```

## SSH into Raspberry Pi and Install

```bash
# SSH into the Pi
ssh pi@192.168.1.100

# Navigate to the project
cd ~/silvia-pid

# Make install script executable
chmod +x deploy/install.sh

# Run installation (installs Docker, pigpio from source, I2C, etc.)
sudo bash deploy/install.sh

# The script will prompt to reboot - do so
sudo reboot
```

## After Reboot

```bash
# SSH back in
ssh pi@192.168.1.100

# Start the service
sudo systemctl start silvia-pid

# Check status
sudo systemctl status silvia-pid

# Watch logs
sudo journalctl -u silvia-pid -f

# OR watch Docker logs
cd /opt/silvia-pid
sudo docker compose logs -f
```

## Access Web Interface

Open browser to: **http://192.168.1.100**

## Important Notes for Debian Trixie

- ✅ **pigpio**: Automatically compiled from source (v79) during installation
- ✅ **MongoDB**: Runs in Docker container (no manual 64-bit install needed)
- ✅ **I2C**: Automatically enabled by installation script
- ✅ **GPIO**: Permissions automatically configured

## Testing Hardware

Before starting the service, test the hardware:

```bash
cd /opt/silvia-pid

# Test thermocouple
node scripts/test-thermocouple.js

# Full hardware validation
node scripts/validate-hardware.js
```

## Troubleshooting

### Check I2C
```bash
sudo i2cdetect -y 1
# Should show device at 0x60
```

### Check pigpiod daemon
```bash
sudo systemctl status pigpiod
# Should be active (running)
```

### Check Docker containers
```bash
cd /opt/silvia-pid
sudo docker compose ps
# Both silvia-pid-app and silvia-mongodb should be Up
```

### View logs
```bash
# System logs
sudo journalctl -u silvia-pid -f

# Docker logs
cd /opt/silvia-pid
sudo docker compose logs -f

# Specific container
sudo docker compose logs -f silvia-pid
```

## Configuration

Edit PID parameters:
```bash
sudo nano /opt/silvia-pid/config.json
```

Changes apply automatically within 1 second!

## Service Management

```bash
# Start
sudo systemctl start silvia-pid

# Stop
sudo systemctl stop silvia-pid

# Restart
sudo systemctl restart silvia-pid

# Status
sudo systemctl status silvia-pid

# Enable auto-start on boot (done by install script)
sudo systemctl enable silvia-pid
```

## Updating Code

```bash
# Transfer updated files from dev machine
rsync -avz --exclude 'node_modules' --exclude '.git' /home/sam/Code/silvia-pid/ pi@192.168.1.100:/opt/silvia-pid/

# SSH into Pi
ssh pi@192.168.1.100

# Rebuild and restart
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

## File Locations

- **Application**: `/opt/silvia-pid/`
- **Config**: `/opt/silvia-pid/config.json`
- **Environment**: `/opt/silvia-pid/.env` (optional)
- **Systemd service**: `/etc/systemd/system/silvia-pid.service`
- **Docker volumes**: 
  - MongoDB data: `silvia-pid_mongodb_data`
  - Logs: `silvia-pid_silvia_logs`

## Safety Features

The system will automatically:
- Shut down heater after 5 consecutive temperature read failures
- Validate temperature readings (0-200°C range)
- Log all errors comprehensively

## API Endpoints

- Web UI: `http://192.168.1.100/`
- Get temps: `http://192.168.1.100/api/temp/get/600`
- Set target: `http://192.168.1.100/api/temp/set/100`
- Set PID: `http://192.168.1.100/api/pid/set/2.6-0.8-80.0`

For full documentation, see [DEPLOYMENT.md](DEPLOYMENT.md)

