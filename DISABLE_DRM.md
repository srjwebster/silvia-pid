# Disabling DRM/Desktop Mode for pigpiod Compatibility

The `vc4-kms-v3d` DRM overlay (used for desktop mode) can conflict with `pigpiod`'s mailbox access, causing the "init mbox zaps failed" error.

## Quick Fix (Current System)

After firmware upgrade completes, run:

```bash
# Edit config.txt
sudo nano /boot/firmware/config.txt
# or
sudo nano /boot/config.txt

# Comment out or remove this line:
# dtoverlay=vc4-kms-v3d

# Add GPU memory allocation (if not present):
gpu_mem=64

# Save and reboot
sudo reboot
```

## Automated (Install Script)

The `install.sh` script now automatically:
1. Disables `dtoverlay=vc4-kms-v3d` if present
2. Sets `gpu_mem=64` if not configured
3. Prompts for reboot if changes were made

## Why This Fixes It

- **DRM overlay** (`vc4-kms-v3d`) takes exclusive control of GPU/mailbox
- **pigpiod** needs mailbox access for GPIO control
- **Disabling DRM** frees the mailbox for pigpiod
- **GPU memory** allocation ensures mailbox has resources

## For Fresh Install

When installing on a fresh OS:
1. Use **Raspberry Pi OS Lite** (no desktop) - recommended
2. Or use full OS and disable desktop: `sudo raspi-config` → Advanced → Desktop → Disable
3. The install script will handle the rest automatically

## Verification

After reboot, check:
```bash
# Check pigpiod is running
sudo systemctl status pigpiod

# Check it's listening
sudo netstat -tlnp | grep 8888

# Test GPIO
sudo docker exec silvia-pid-app node -e "const Gpio = require('pigpio').Gpio; const pin = new Gpio(16, {mode: Gpio.OUTPUT}); console.log('GPIO works!');"
```

