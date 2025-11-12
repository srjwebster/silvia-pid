# Fresh Deployment Guide - Debian Trixie to Production

This guide takes you from a fresh Debian Trixie Raspberry Pi OS installation to a fully running Silvia PID controller.

## Prerequisites

- ✅ Raspberry Pi (3/4/5) with Debian Trixie installed
- ✅ Pi is on your network and accessible via SSH
- ✅ You know the Pi's IP address (e.g., 192.168.1.100)
- ✅ SSH access: `ssh pi@192.168.1.100`
- ⚠️ Hardware NOT yet required (we'll test without it first)

## Overview

We'll deploy in stages:
1. **Transfer code** - Copy files to Pi
2. **Run installer** - Automated setup script
3. **Test without hardware** - Verify everything works
4. **Connect hardware** - MCP9600 and relay
5. **Enable SSL** - HTTPS with Let's Encrypt
6. **Set up monitoring** - Uptime Kuma with alerts

**Total time:** ~30 minutes

---

## Stage 1: Transfer Code to Pi (5 minutes)

### Step 1: Prepare on Your Local Machine

```bash
# Navigate to your project
cd /home/sam/Code/silvia-pid

# Verify you have the latest code
ls -la
# Should see: docker-compose.yml, Dockerfile, pid-process.js, web-server.js, etc.
```

### Step 2: Transfer Files to Raspberry Pi

```bash
# From your local machine (/home/sam/Code/silvia-pid)
rsync -avz \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'silvia-pid/' \
  --exclude '*.md' \
  . pi@192.168.1.100:~/silvia-pid/

# This copies everything except:
# - node_modules (will be installed in Docker)
# - .git history
# - Old Go binary directory
# - Documentation (we'll copy important ones separately)
```

### Step 3: Transfer Important Documentation

```bash
# Copy essential docs
rsync -avz \
  README.md \
  DEPLOYMENT.md \
  SAFETY.md \
  SSL_SETUP.md \
  QUICK_START_MONITORING.md \
  UPTIME_KUMA_SETUP.md \
  FRESH_DEPLOYMENT.md \
  pi@192.168.1.100:~/silvia-pid/
```

### Step 4: Verify Transfer

```bash
# SSH to Pi
ssh pi@192.168.1.100

# Check files
cd ~/silvia-pid
ls -la

# Should see:
# - docker-compose.yml
# - Dockerfile
# - package.json
# - pid-process.js
# - web-server.js
# - temperature.py
# - index.html
# - config.json
# - deploy/ directory
# - scripts/ directory
# - README.md and other docs
```

---

## Stage 2: Run Automated Installer (15 minutes)

The installer will:
- Install Docker & Docker Compose
- Compile pigpio from source (for Debian Trixie)
- Set up I2C and GPIO permissions
- Enable pigpiod daemon
- Copy files to `/opt/silvia-pid`
- Build Docker images
- Set up systemd service for auto-start

### Step 1: Run Installer

```bash
# Still on the Pi, in ~/silvia-pid
cd ~/silvia-pid/deploy
chmod +x install.sh

# Run installer (takes ~10-15 minutes)
sudo bash install.sh
```

The script will:
1. ✅ Check for Raspberry Pi OS
2. ✅ Install Docker
3. ✅ Install Docker Compose
4. ✅ Enable I2C interface
5. ✅ Set up GPIO/I2C permissions
6. ✅ Install Python and dependencies
7. ✅ Compile pigpio from source
8. ✅ Enable pigpiod daemon
9. ✅ Copy files to `/opt/silvia-pid`
10. ✅ Build Docker images (takes longest)
11. ✅ Start services
12. ✅ Set up systemd auto-start

**Expected output:**
```
Installing Silvia PID Controller...
Step 1: Checking prerequisites...
  ✓ Running on Raspberry Pi
Step 2: Installing Docker...
  ✓ Docker installed
...
Installation complete!
```

### Step 2: Reboot (Required)

```bash
sudo reboot
```

This ensures:
- I2C module loaded
- GPIO permissions applied
- pigpiod daemon starts
- Docker configured for user

**Wait 2-3 minutes for Pi to reboot, then SSH back in:**
```bash
ssh pi@192.168.1.100
```

### Step 3: Verify Services Started

```bash
# Check Docker containers
sudo docker ps

# Should see 2 containers running:
# - silvia-pid_mongodb_1
# - silvia-pid-app

# Check service status
sudo systemctl status silvia-pid

# Should see: Active: active (exited)
```

---

## Stage 3: Test Without Hardware (5 minutes)

You can test the system even without the thermocouple or relay connected!

### Expected Behavior Without Hardware

- ❌ Temperature readings will fail (no thermocouple)
- ✅ Web server will work
- ✅ Web UI will load
- ✅ MongoDB will work
- ⚠️ System will show "unhealthy" (expected - no sensor)

### Step 1: Check Logs

```bash
# View logs
cd /opt/silvia-pid
sudo docker compose logs -f

# You'll see errors like:
# - "ERROR: Failed to read temperature from MCP9600"
# - "Temperature read timeout"
# - This is EXPECTED without hardware connected

# Press Ctrl+C to exit logs
```

### Step 2: Test Web UI

Open in your browser (from your computer):
```
http://192.168.1.100
```

**Expected:**
- ✅ Page loads (beautiful ECharts UI)
- ✅ Connection status: Connected
- ⚠️ Temperature: Shows dashes or old data
- ⚠️ Chart: Empty or shows "No documents found"

**This is normal without hardware!**

### Step 3: Test API Endpoints

```bash
# From your computer or from the Pi:

# Health check (will show unhealthy - expected)
curl http://192.168.1.100/health

# Should return JSON with status: "unhealthy"
# Reason: temperature_readings not updating

# Mode endpoint
curl http://192.168.1.100/api/mode

# Should return: {"mode":"espresso","target_temperature":100,...}

# Set mode (will work even without hardware)
curl http://192.168.1.100/api/mode/steam

# Should return: {"success":true,"mode":"steam",...}
```

### Step 4: Verify MongoDB

```bash
# Check MongoDB is storing data
sudo docker compose exec mongodb mongosh

# In MongoDB shell:
use pid
db.temperatures.count()

# Will show 0 or very few (since sensor isn't connected)

# Exit MongoDB shell:
exit
```

### Summary of Stage 3

At this point:
- ✅ Software is fully deployed
- ✅ Web server works
- ✅ API works
- ✅ Docker containers running
- ✅ Auto-start configured
- ⚠️ Temperature readings fail (hardware not connected yet)

**This is exactly what we expect!** Now let's connect the hardware.

---

## Stage 4: Connect Hardware (10 minutes)

### Hardware Checklist

You need:
- ✅ MCP9600 thermocouple amplifier board
- ✅ K-type thermocouple
- ✅ Solid-state relay (SSR) or relay module
- ✅ Jumper wires

### Wiring Diagram

#### MCP9600 Thermocouple (I2C)

```
MCP9600 → Raspberry Pi
-----------------------
VCC     → Pin 1  (3.3V)
GND     → Pin 6  (Ground)
SDA     → Pin 3  (GPIO 2 / SDA)
SCL     → Pin 5  (GPIO 3 / SCL)

Thermocouple → MCP9600
----------------------
Red  (+) → T+
Blue (-) → T-
```

#### SSR Relay (GPIO)

```
Relay Module → Raspberry Pi
----------------------------
VCC  → Pin 2  (5V)
GND  → Pin 9  (Ground)
IN   → Pin 36 (GPIO 16)

Relay Output → Boiler
---------------------
NO (Normally Open) → Heater circuit
COM (Common)       → Heater circuit
```

### Step 1: Shutdown Pi

```bash
# From SSH session
sudo shutdown -h now

# Wait for Pi to fully shutdown (green LED stops blinking)
```

### Step 2: Connect Hardware

1. **Disconnect power** from Raspberry Pi
2. **Connect MCP9600** to I2C pins (pins 1, 3, 5, 6)
3. **Connect thermocouple** to MCP9600 (T+, T-)
4. **Connect relay module** to GPIO 16 (pin 36) and power
5. **Double-check all connections**

### Step 3: Test I2C Connection

```bash
# Power on Pi, SSH back in
ssh pi@192.168.1.100

# Test I2C device detection
i2cdetect -y 1

# Should show device at address 0x60:
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00:          -- -- -- -- -- -- -- -- -- -- -- -- --
# 10: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 20: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 30: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 40: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 50: -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
# 60: 60 -- -- -- -- -- -- -- -- -- -- -- -- -- -- --  <-- MCP9600
# 70: -- -- -- -- -- -- -- --
```

**If you don't see `60`:**
- Check wiring (SDA/SCL swapped?)
- Verify I2C is enabled: `sudo raspi-config` → Interface Options → I2C
- Check 3.3V power to MCP9600

### Step 4: Test Temperature Reading

```bash
# Manual test
cd /opt/silvia-pid
python3 temperature.py

# Should output temperature in °C:
# 23.5

# If it errors:
# - Check MCP9600 wiring
# - Verify thermocouple is connected
# - Check I2C address (should be 0x60)
```

### Step 5: Restart Service and Verify

```bash
# Restart Docker containers
sudo docker compose restart

# Watch logs
sudo docker compose logs -f silvia-pid

# Should now see:
# - "Temp: 23.5°C, Target: 100°C, Output: 85.2%"
# - No more timeout errors!

# Press Ctrl+C to exit
```

### Step 6: Test Web UI Again

Open browser:
```
http://192.168.1.100
```

**Expected:**
- ✅ Temperature shows current reading (~20-25°C room temp)
- ✅ Chart populating with data
- ✅ Heater output percentage showing
- ✅ Connection status: Connected

### Step 7: Test Relay Control

**⚠️ SAFETY WARNING:**
- The relay will control your coffee machine heater
- Do NOT connect relay to heater yet unless you're ready for testing
- Always monitor first few heating cycles

```bash
# Test relay without heater connected (if possible)
# Watch for relay clicking on/off

# Or test with multimeter on relay output contacts
# - Measure continuity between NO and COM
# - Should switch based on temperature vs target
```

### Step 8: Run Hardware Validation

```bash
# Run comprehensive hardware test
cd /opt/silvia-pid
node scripts/validate-hardware.js

# Should show:
# ✓ Python3 installed
# ✓ I2C device accessible
# ✓ pigpiod running
# ✓ Thermocouple reading valid
# ✓ GPIO accessible
# ✓ MongoDB connected
# ✓ Config file valid
```

**If all checks pass: Hardware is ready! ✅**

---

## Stage 5: Enable SSL/HTTPS (10 minutes)

Now that everything works, let's secure it with HTTPS.

### Step 1: Edit SSL Setup Script

```bash
cd /opt/silvia-pid/deploy
nano setup-ssl.sh

# Change this line:
EMAIL="your-email@example.com"

# To your actual email:
EMAIL="your-actual-email@gmail.com"

# Save: Ctrl+O, Enter
# Exit: Ctrl+X
```

### Step 2: Run SSL Setup

```bash
sudo bash setup-ssl.sh
```

The script will:
1. ✅ Check DNS resolution
2. ✅ Install certbot
3. ✅ Stop service temporarily
4. ✅ Obtain SSL certificate from Let's Encrypt
5. ✅ Create `.env` with SSL config
6. ✅ Set up auto-renewal
7. ✅ Restart service with HTTPS
8. ✅ Test HTTPS connection

**Expected output:**
```
============================================
Silvia PID SSL Setup
Domain: coffee.srjwebster.com
============================================

Step 1: Checking DNS resolution...
  Domain resolves to: [Your IP]
Step 2: Installing certbot...
  Certbot installed
...
Step 9: Testing HTTPS connection...
  HTTPS test: PASSED ✓

============================================
SSL Setup Complete!
============================================
```

### Step 3: Test HTTPS

```bash
# From your computer:
curl https://coffee.srjwebster.com

# Should return: HTML content (no SSL errors)

# Test health endpoint:
curl https://coffee.srjwebster.com/health

# Should return: {"status":"healthy",...}
```

Open browser:
```
https://coffee.srjwebster.com
```

**Expected:**
- ✅ 🔒 Secure padlock in address bar
- ✅ Valid SSL certificate
- ✅ Coffee machine UI loads
- ✅ Real-time temperature data

---

## Stage 6: Set Up Monitoring (10 minutes)

### Step 1: Start Uptime Kuma

```bash
cd /opt/silvia-pid
sudo docker compose up -d uptime-kuma

# Wait for it to start
sleep 10

# Check it's running
sudo docker ps | grep uptime-kuma
```

### Step 2: Access Web Interface

Open browser:
```
http://192.168.1.100:3001
```

Create admin account:
- Username: `admin`
- Password: [choose secure password]
- Click **Create**

### Step 3: Set Up Email Notifications

Follow `QUICK_START_MONITORING.md`:

1. Click **Settings** → **Notifications**
2. Click **Setup Notification**
3. Select **Email (SMTP)**
4. Configure Gmail (or your provider)
5. **Test** → **Save**

### Step 4: Create Monitor

1. Click **Add New Monitor**
2. Configure:
   ```
   Monitor Type: HTTP(s)
   Friendly Name: Coffee Machine Health
   URL: https://coffee.srjwebster.com/health
   Heartbeat Interval: 60
   Accepted Status Codes: 200
   ```
3. Enable email notification
4. Click **Save**

### Step 5: Create Status Page

1. Click **Status Pages** → **New Status Page**
2. Title: `Coffee Machine`
3. Slug: `coffee`
4. Drag monitor to page
5. **Save**

Access at: `http://192.168.1.100:3001/status/coffee`

### Step 6: Test Alerts

```bash
# Stop service to trigger alert
sudo docker compose stop silvia-pid

# Wait 60-90 seconds
# You should receive email: "Coffee Machine Health is DOWN"

# Restart service
sudo docker compose start silvia-pid

# Wait 60-90 seconds
# You should receive email: "Coffee Machine Health is UP"
```

**If you get both emails: Monitoring is working! ✅**

---

## Final Verification Checklist

### On Raspberry Pi:

```bash
# Check all services running
sudo docker ps

# Should show 3 containers:
# - silvia-pid-app (healthy)
# - mongodb (healthy)
# - uptime-kuma (healthy)

# Check systemd service
sudo systemctl status silvia-pid
# Should be: Active: active (exited)

# Check logs (no errors)
sudo docker compose logs --tail 50 silvia-pid
```

### From Your Computer/Phone:

- [ ] ✅ `https://coffee.srjwebster.com` loads
- [ ] ✅ Shows real-time temperature
- [ ] ✅ Chart populating with data
- [ ] ✅ Mode buttons work (Espresso/Steam)
- [ ] ✅ Valid SSL certificate (🔒)
- [ ] ✅ Health endpoint returns 200: `curl https://coffee.srjwebster.com/health`
- [ ] ✅ Uptime Kuma status page accessible
- [ ] ✅ Email alerts working

### Hardware:

- [ ] ✅ Temperature reading correctly (~20-25°C room temp)
- [ ] ✅ Heater output percentage shown
- [ ] ✅ Relay clicks when output changes
- [ ] ✅ No error messages in logs

---

## Post-Deployment

### Clean Up Old Files

```bash
# Remove transferred files from home directory
rm -rf ~/silvia-pid

# Everything is now in /opt/silvia-pid
```

### Bookmark Important URLs

**On your computer/phone:**
- Dashboard: `https://coffee.srjwebster.com`
- Status Page: `http://192.168.1.100:3001/status/coffee`
- Uptime Kuma: `http://192.168.1.100:3001`

### Set Up Google Assistant (Optional)

Follow `SSL_SETUP.md` section on IFTTT:
1. Create IFTTT account
2. Add webhook applet for espresso mode
3. Add webhook applet for steam mode
4. Test voice commands

---

## Maintenance

### Daily:
- ✅ Automatic (no action needed)
- System monitors itself
- Email alerts on problems
- Auto-restart on failures

### Weekly:
- Check Uptime Kuma dashboard
- Verify no errors in logs: `sudo docker compose logs --tail 100`

### Monthly:
- Check SSL certificate: `sudo certbot certificates`
- Review temperature logs for anomalies
- Backup Uptime Kuma config (optional)

### Updates:

```bash
# When you make code changes:
cd /home/sam/Code/silvia-pid
rsync -avz . pi@192.168.1.100:/opt/silvia-pid/

# Rebuild and restart:
ssh pi@192.168.1.100
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

---

## Troubleshooting

### Service won't start

```bash
# Check logs
sudo docker compose logs silvia-pid

# Check Docker daemon
sudo systemctl status docker

# Restart everything
sudo docker compose down
sudo docker compose up -d
```

### Temperature reads 0 or errors

```bash
# Test I2C
i2cdetect -y 1
# Should show 0x60

# Test Python script
python3 /opt/silvia-pid/temperature.py
# Should output temperature

# Check wiring (SDA, SCL, VCC, GND)
```

### SSL certificate issues

```bash
# Check certificate exists
sudo ls -la /etc/letsencrypt/live/coffee.srjwebster.com/

# Test renewal
sudo certbot renew --dry-run

# Recreate certificate
sudo certbot delete -d coffee.srjwebster.com
sudo bash /opt/silvia-pid/deploy/setup-ssl.sh
```

### Can't access from internet

```bash
# Check port forwarding on router
# Ports 80 and 443 should forward to 192.168.1.100

# Check DNS
nslookup coffee.srjwebster.com
# Should resolve to your public IP

# Check from Pi
curl -I http://localhost:80
# Should work locally
```

---

## You're Done! 🎉

Your Silvia PID controller is now:
- ✅ Fully deployed on Raspberry Pi
- ✅ Secured with HTTPS
- ✅ Accessible from anywhere
- ✅ Monitoring with email alerts
- ✅ Auto-starting on boot
- ✅ Self-healing (auto-restart on failures)
- ✅ Production-grade and reliable

**Enjoy your perfectly temperature-controlled espresso!** ☕🎉

---

## Quick Reference

```bash
# View logs
sudo docker compose -f /opt/silvia-pid/docker-compose.yml logs -f

# Restart service
sudo docker compose -f /opt/silvia-pid/docker-compose.yml restart

# Stop service
sudo docker compose -f /opt/silvia-pid/docker-compose.yml stop

# Start service
sudo docker compose -f /opt/silvia-pid/docker-compose.yml start

# Check status
sudo systemctl status silvia-pid

# Update code (after rsync)
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

