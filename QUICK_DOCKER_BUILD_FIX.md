# Quick Fix: Docker Build Stuck

## Problem
Docker build is stuck downloading a layer (48.36MB / 48.36MB for 10+ minutes).

## Root Cause
WiFi connection dropped during Docker layer download, causing the build to hang.

## Immediate Fix

### 1. Kill Stuck Build
```bash
# On your Pi, kill the stuck build
sudo bash scripts/kill-stuck-docker.sh

# Or manually:
sudo pkill -f "docker.*compose.*build"
sudo systemctl restart docker
```

### 2. Retry Build in Screen (Recommended)
```bash
# Install screen (if not installed)
sudo apt install screen

# Start screen session
screen -S docker-build

# Navigate to your project
cd /opt/silvia-pid

# Retry build
sudo docker compose build --no-cache

# Detach: Press Ctrl+A, then D
# Process continues even if SSH disconnects!

# Reattach later:
screen -r docker-build
```

### 3. Alternative: Retry with Increased Timeout
```bash
# Set longer timeout
export DOCKER_CLIENT_TIMEOUT=600

# Retry build
cd /opt/silvia-pid
sudo docker compose build --no-cache
```

## Permanent Fix

### Fix WiFi Connection Drops
```bash
# Disable WiFi power management (causes drops)
sudo bash scripts/fix-wifi-drops.sh

# Reboot
sudo reboot
```

## Why This Happens

1. **WiFi power management** - Pi goes to sleep, connection drops
2. **Network timeout** - Long download times out
3. **Connection instability** - WiFi signal fluctuations

## Prevention

1. **Use screen/tmux** for all long-running builds
2. **Fix WiFi power management** - prevents drops
3. **Use Ethernet** if possible (more stable)
4. **Monitor connection** during builds

## Alternative: Use Docker Registry Mirror

If Docker Hub is consistently slow:

```bash
# Edit Docker daemon config
sudo nano /etc/docker/daemon.json

# Add registry mirror:
{
  "registry-mirrors": ["https://mirror.gcr.io"]
}

# Restart Docker
sudo systemctl restart docker
```

## Quick Commands

```bash
# Kill stuck build
sudo bash scripts/kill-stuck-docker.sh

# Retry in screen
screen -S build
sudo docker compose build --no-cache
# Ctrl+A, D to detach

# Check build progress
screen -r build

# Fix WiFi drops
sudo bash scripts/fix-wifi-drops.sh
```

