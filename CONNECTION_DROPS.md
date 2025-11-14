# Connection Drops Troubleshooting Guide

## ⚠️ CRITICAL: Check if Pi is Rebooting

**If screen sessions disappear after connection drops, the Pi may be rebooting due to power supply issues!**

### Quick Check

```bash
# Check if Pi recently rebooted
uptime

# Check boot time
who -b

# Check power supply (CRITICAL!)
vcgencmd get_throttled
# Should be: 0x0 (no issues)
# If not 0x0: Power supply problem causing reboots!

# Quick diagnostic
bash scripts/check-reboot-status.sh
```

**Note:** Screen sessions don't survive reboots. If your Pi is rebooting, fix the power supply first (most common cause: undervoltage).

## Quick Fixes

### 1. Use Screen or Tmux (Immediate Workaround)

**Screen:**
```bash
# Install screen
sudo apt install screen

# Start screen session
screen -S install

# Run your command
sudo bash deploy/install.sh

# Detach: Press Ctrl+A, then D
# Reattach: screen -r install
# List sessions: screen -ls
```

**Tmux:**
```bash
# Install tmux
sudo apt install tmux

# Start tmux session
tmux new -s install

# Run your command
sudo bash deploy/install.sh

# Detach: Press Ctrl+B, then D
# Reattach: tmux attach -t install
# List sessions: tmux ls
```

### 2. Fix WiFi Power Management (Common Cause)

```bash
# Run automated fix script
sudo bash scripts/fix-wifi-drops.sh

# Or manually:
sudo iwconfig wlan0 power off
```

### 3. Use Ethernet Instead of WiFi

Ethernet is much more stable than WiFi. If possible:
- Connect Ethernet cable
- Disable WiFi or let it be secondary
- More reliable for long-running processes

## Diagnosis

### Run Diagnostic Script

```bash
# Comprehensive connection drop diagnosis
sudo bash scripts/diagnose-connection-drops.sh
```

This will check:
- WiFi power management status
- Power supply issues (undervoltage)
- WiFi signal strength
- Network interface errors
- System resource usage
- Recent disconnection events

## Common Causes

### 1. WiFi Power Management (Most Common)

**Symptoms:**
- Connections drop periodically (every few minutes)
- More common when idle
- Reconnects automatically

**Fix:**
```bash
sudo bash scripts/fix-wifi-drops.sh
sudo reboot
```

### 2. Weak WiFi Signal

**Symptoms:**
- Connections drop when signal is weak
- More drops at distance from router
- Packet loss in ping tests

**Check:**
```bash
iwconfig wlan0
# Look for Signal level (should be > -70 dBm)
```

**Fix:**
- Move Pi closer to router
- Use WiFi extender
- Switch to Ethernet
- Change WiFi channel on router (avoid interference)

### 3. Power Supply Issues

**Symptoms:**
- Connections drop under load
- System freezes or reboots
- Throttling detected

**Check:**
```bash
vcgencmd get_throttled
# Should show: 0x0 (no issues)
# If not 0x0, power supply is insufficient
```

**Fix:**
- Use official Raspberry Pi power supply (5V, 2.5A+)
- Check power cable quality
- Avoid USB hubs for power
- Use shorter, thicker USB cable

### 4. SD Card Issues

**Symptoms:**
- System freezes during I/O operations
- Connections drop during disk writes
- Slow performance

**Check:**
```bash
sudo bash scripts/diagnose-pipe-drops.sh
```

**Fix:**
- Use high-quality SD card (Class 10, A2)
- Check SD card health
- Consider using USB SSD instead

### 5. System Overload

**Symptoms:**
- Connections drop during heavy operations
- High CPU/memory usage
- Timeouts

**Check:**
```bash
top
free -h
```

**Fix:**
- Close unnecessary processes
- Reduce system load
- Add swap space if needed

### 6. Router/AP Issues

**Symptoms:**
- Connections drop for all devices
- Router logs show disconnections
- Network-wide issues

**Fix:**
- Restart router
- Update router firmware
- Check router logs
- Try different WiFi network

## Prevention

### 1. Disable WiFi Power Management

```bash
sudo bash scripts/fix-wifi-drops.sh
```

This creates persistent settings that survive reboots.

### 2. Configure SSH Keepalive

Edit `/etc/ssh/sshd_config`:
```
ClientAliveInterval 60
ClientAliveCountMax 3
```

Then restart SSH:
```bash
sudo systemctl restart ssh
```

### 3. Use Ethernet When Possible

Ethernet is more stable than WiFi:
- No power management issues
- Lower latency
- More reliable
- Better for long-running processes

### 4. Monitor Connection Stability

```bash
# Monitor connection continuously
while true; do
    ping -c 1 -W 2 8.8.8.8 && echo "$(date): OK" || echo "$(date): FAILED"
    sleep 5
done
```

### 5. Use Screen/Tmux for Long Operations

Always use screen or tmux for:
- Installation scripts
- Long-running builds
- Updates
- Any critical operations

## Testing

### Test Connection Stability

```bash
# Ping test (5 minutes)
ping -c 60 -i 5 8.8.8.8

# Should show 0% packet loss
# If > 0%, connections are dropping
```

### Test WiFi Signal

```bash
# Check signal strength
iwconfig wlan0 | grep Signal

# Good: > -70 dBm
# Fair: -70 to -80 dBm
# Poor: < -80 dBm (causes drops)
```

### Test Power Supply

```bash
# Check for throttling
vcgencmd get_throttled

# Should show: 0x0
# If not, power supply is insufficient
```

## Quick Reference

### Check Current Status

```bash
# WiFi power management
iwconfig wlan0 | grep Power

# Power supply
vcgencmd get_throttled

# Signal strength
iwconfig wlan0 | grep Signal

# Network errors
cat /sys/class/net/wlan0/statistics/rx_errors
cat /sys/class/net/wlan0/statistics/tx_errors
```

### Fix Common Issues

```bash
# Disable WiFi power management
sudo iwconfig wlan0 power off

# Check power supply
vcgencmd get_throttled

# Run diagnostics
sudo bash scripts/diagnose-connection-drops.sh

# Apply fixes
sudo bash scripts/fix-wifi-drops.sh
```

### Use Screen for Long Operations

```bash
# Start screen
screen -S install

# Run command
sudo bash deploy/install.sh

# Detach: Ctrl+A, then D
# Reattach: screen -r install
```

## Summary

**Most Common Cause:** WiFi power management

**Quick Fix:**
```bash
sudo bash scripts/fix-wifi-drops.sh
sudo reboot
```

**Best Practice:** Use screen/tmux for long-running processes

**Best Solution:** Use Ethernet instead of WiFi (if possible)

