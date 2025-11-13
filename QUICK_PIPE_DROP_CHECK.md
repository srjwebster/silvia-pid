# Quick Pipe Drop Check

Quick reference for diagnosing pipe drops during installation.

## What Are "Pipe Drops"?

"Pipe drops" refer to:
- Broken pipe errors (`Broken pipe`, `EPIPE`)
- Network timeouts
- Process interruptions
- Connection drops

## Most Common Causes

### 1. SD Card Issues (40% of cases)
- **Symptoms:** Random failures, slow writes, corruption
- **Fix:** Use high-quality SD card (SanDisk Extreme, Samsung EVO Plus)

### 2. Power Supply Issues (30% of cases)
- **Symptoms:** Undervoltage warnings, random reboots
- **Fix:** Use official Raspberry Pi power supply (5V, 3A)

### 3. Overheating (20% of cases)
- **Symptoms:** CPU throttling, random crashes
- **Fix:** Add cooling (heatsinks, fan, ventilation)

### 4. Network Issues (10% of cases)
- **Symptoms:** SSH drops, package download failures
- **Fix:** Use wired Ethernet, check network stability

## Quick Diagnostic

### Run Diagnostic Script

```bash
# Transfer diagnostic script to Pi
cd /home/sam/Code/silvia-pid
rsync -avz scripts/diagnose-pipe-drops.sh pi@192.168.1.100:~/diagnose-pipe-drops.sh

# SSH to Pi and run
ssh pi@192.168.1.100
chmod +x diagnose-pipe-drops.sh
sudo bash diagnose-pipe-drops.sh
```

### Manual Checks

```bash
# Check power supply
vcgencmd get_throttled
# Should show: throttled=0x0 (no throttling)
# If non-zero: Power supply issue

# Check temperature
vcgencmd measure_temp
# Should show: temp=XX.X'C (<80°C)
# If >80°C: Overheating issue

# Check disk space
df -h
# Should show: >2GB free
# If <2GB: Disk space issue

# Check network
ping -c 10 8.8.8.8
# Should show: 0% packet loss
# If >5%: Network issue

# Check recent errors
sudo dmesg | tail -20 | grep -i "error\|fail\|mmc\|sd"
# Should show: No errors
# If errors found: Hardware issue
```

## Quick Fixes

### Fix 1: Use Better SD Card

```bash
# Replace with high-quality SD card:
# - SanDisk Extreme or Ultra
# - Samsung EVO Plus
# - Class 10 or higher
# - At least 32GB

# Reinstall OS on new SD card
# Then retry installation
```

### Fix 2: Fix Power Supply

```bash
# Use official Raspberry Pi power supply
# - 5V, 3A minimum
# - High-quality USB-C power supply
# - Avoid USB hubs
# - Use shorter USB cable

# Check voltage
vcgencmd measure_volts
# Should show: volt=5.0V (or close)
```

### Fix 3: Fix Overheating

```bash
# Add cooling:
# - Heatsinks
# - Fan cooling
# - Improve ventilation

# Check temperature
vcgencmd measure_temp
# Should show: <80°C
```

### Fix 4: Fix Network

```bash
# Use wired Ethernet instead of Wi-Fi
# - More stable
# - Faster downloads
# - Less connection drops

# Check network
ping -c 10 8.8.8.8
# Should show: 0% packet loss
```

## Use Screen/Tmux for Installation

Prevent SSH disconnections from killing installation:

```bash
# Install screen
sudo apt-get install screen

# Start screen session
screen

# Run installation
sudo bash deploy/install.sh

# Detach: Ctrl+A, D
# Reattach: screen -r

# Or use tmux
sudo apt-get install tmux
tmux
sudo bash deploy/install.sh
# Detach: Ctrl+B, D
# Reattach: tmux attach
```

## Log Installation Output

```bash
# Log all output to file
sudo bash deploy/install.sh 2>&1 | tee install.log

# Check for errors
grep -i "error\|fail\|timeout\|broken pipe" install.log

# Check for specific issues
grep -i "mmc\|sd\|i/o" install.log
```

## If Hardware Issues Found

### Replace SD Card

1. Backup current SD card (if possible)
2. Get high-quality SD card (SanDisk Extreme, Samsung EVO Plus)
3. Reinstall OS on new SD card
4. Retry installation

### Replace Power Supply

1. Get official Raspberry Pi power supply (5V, 3A)
2. Replace current power supply
3. Check voltage: `vcgencmd measure_volts`
4. Retry installation

### Add Cooling

1. Add heatsinks to Raspberry Pi
2. Add fan cooling (if needed)
3. Improve ventilation
4. Check temperature: `vcgencmd measure_temp`
5. Retry installation

## Summary

**Most likely causes:**
1. SD card issues (40%)
2. Power supply issues (30%)
3. Overheating (20%)
4. Network issues (10%)

**Quick checks:**
```bash
vcgencmd get_throttled  # Power supply
vcgencmd measure_temp   # Temperature
df -h                   # Disk space
ping -c 10 8.8.8.8     # Network
sudo dmesg | tail -20   # Errors
```

**Quick fixes:**
1. Use better SD card
2. Use official power supply
3. Add cooling
4. Use wired Ethernet
5. Use screen/tmux for installation

**If issues persist:**
- Run diagnostic script: `sudo bash diagnose-pipe-drops.sh`
- Check detailed guide: `TROUBLESHOOTING_PIPE_DROPS.md`
- Consider hardware replacement (SD card, power supply)

---

For detailed troubleshooting, see `TROUBLESHOOTING_PIPE_DROPS.md`.

