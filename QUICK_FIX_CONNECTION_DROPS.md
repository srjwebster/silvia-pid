# Quick Fix: Connection Drops

## Immediate Solution: Use Screen

**For your current installation:**
```bash
# Install screen (if not already installed)
sudo apt install screen

# Start screen session
screen -S install

# Run installation
sudo bash deploy/install.sh

# Detach: Press Ctrl+A, then D
# Your process continues even if SSH disconnects!

# Reattach later:
screen -r install
```

## Root Cause: WiFi Power Management

Your Pi is using WiFi (wlan0), and WiFi power management is the **#1 cause** of connection drops on Raspberry Pi.

### Fix WiFi Drops

```bash
# Run automated fix script
sudo bash scripts/fix-wifi-drops.sh

# Reboot to apply
sudo reboot
```

### Or Fix Manually

```bash
# Disable WiFi power management via NetworkManager
sudo nmcli connection modify "$(nmcli -t -f NAME,TYPE connection show --active | grep wifi | cut -d: -f1)" wifi.powersave 0

# Create persistent configuration
sudo bash -c 'cat > /etc/NetworkManager/conf.d/99-wifi-powersave.conf << EOF
[connection]
wifi.powersave = 0
EOF'

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Verify
nmcli connection show --active | grep wifi.powersave
# Should show: wifi.powersave:0
```

## Other Common Causes

### 1. Weak WiFi Signal
- Your signal: 78% (fair, but could be better)
- **Fix:** Move Pi closer to router, or use Ethernet

### 2. Power Supply Issues
- **Check:** `vcgencmd get_throttled`
- Should show: `0x0` (no issues)
- **Fix:** Use official Pi power supply (5V, 2.5A+)

### 3. Long SSH Timeouts
- **Fix:** Configure SSH keepalive (see below)

### 4. Router/AP Issues
- **Fix:** Restart router, update firmware

## Configure SSH Keepalive

Edit `/etc/ssh/sshd_config`:
```
ClientAliveInterval 60
ClientAliveCountMax 3
```

Then restart SSH:
```bash
sudo systemctl restart ssh
```

## Best Practice: Use Ethernet

Ethernet is **much more stable** than WiFi:
- No power management issues
- Lower latency
- More reliable
- Better for long-running processes

If possible, connect Ethernet cable and disable WiFi.

## Diagnostic Tools

```bash
# Run comprehensive diagnostics
sudo bash scripts/diagnose-connection-drops.sh

# Check WiFi power management
nmcli connection show --active | grep wifi.powersave

# Check power supply
vcgencmd get_throttled

# Check signal strength
nmcli device wifi list

# Monitor connection
watch -n 5 'ping -c 1 -W 2 8.8.8.8 && echo "OK" || echo "FAILED"'
```

## Summary

**Quick Fix (Right Now):**
1. Use screen: `screen -S install`
2. Run your command
3. Detach: Ctrl+A, then D

**Permanent Fix:**
1. Disable WiFi power management: `sudo bash scripts/fix-wifi-drops.sh`
2. Reboot: `sudo reboot`
3. Consider using Ethernet if possible

**For Long Operations:**
- Always use screen or tmux
- Prevents connection drops from killing your process
- Can reconnect and continue later

