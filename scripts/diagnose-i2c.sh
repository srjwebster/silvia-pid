#!/bin/bash
# I2C Diagnostic Script
# Diagnoses and attempts to fix I2C issues on Raspberry Pi

set -e

echo "=========================================="
echo "I2C Diagnostic Script"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track issues
ISSUES=0
FIXES_APPLIED=0

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        ISSUES=$((ISSUES + 1))
    fi
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check 1: I2C enabled in config.txt
echo "1. Checking I2C configuration..."
I2C_CONFIG_FILE=""
if [ -f /boot/firmware/config.txt ]; then
    I2C_CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    I2C_CONFIG_FILE="/boot/config.txt"
fi

if [ -n "$I2C_CONFIG_FILE" ]; then
    if grep -q "^dtparam=i2c_arm=on" "$I2C_CONFIG_FILE" 2>/dev/null; then
        print_status 0 "I2C enabled in $I2C_CONFIG_FILE"
    else
        print_status 1 "I2C NOT enabled in $I2C_CONFIG_FILE"
        echo "   Fix: Add 'dtparam=i2c_arm=on' to $I2C_CONFIG_FILE"
        if [ "$EUID" -eq 0 ]; then
            read -p "   Enable I2C now? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "dtparam=i2c_arm=on" >> "$I2C_CONFIG_FILE"
                print_info "I2C enabled in $I2C_CONFIG_FILE (reboot required)"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
            fi
        else
            echo "   Run as root to enable I2C automatically"
        fi
    fi
else
    print_status 1 "Config file not found (neither /boot/firmware/config.txt nor /boot/config.txt)"
fi

# Check 2: Detect Pi model
echo ""
echo "2. Detecting Raspberry Pi model..."
PI_MODEL="unknown"
if [ -f /proc/device-tree/model ]; then
    PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "unknown")
    print_info "Detected: $PI_MODEL"
else
    print_warn "Could not detect Pi model from /proc/device-tree/model"
fi

# Check 3: Determine I2C hardware module
echo ""
echo "3. Determining I2C hardware module..."
I2C_HW_MODULE=""
if echo "$PI_MODEL" | grep -qi "Raspberry Pi 5"; then
    I2C_HW_MODULE="i2c-bcm2711"
    print_info "Pi 5 detected - using i2c-bcm2711"
elif echo "$PI_MODEL" | grep -qi "Raspberry Pi 4"; then
    I2C_HW_MODULE="i2c-bcm2711"
    print_info "Pi 4 detected - using i2c-bcm2711"
elif echo "$PI_MODEL" | grep -qi "Raspberry Pi 3\|Raspberry Pi Zero"; then
    I2C_HW_MODULE="i2c-bcm2835"
    print_info "Pi 3/Zero detected - using i2c-bcm2835"
else
    # Try to auto-detect
    if modinfo i2c-bcm2711 &>/dev/null; then
        I2C_HW_MODULE="i2c-bcm2711"
        print_info "Auto-detected: i2c-bcm2711"
    elif modinfo i2c-bcm2835 &>/dev/null; then
        I2C_HW_MODULE="i2c-bcm2835"
        print_info "Auto-detected: i2c-bcm2835"
    else
        print_warn "Could not determine I2C hardware module"
    fi
fi

# Check 4: I2C hardware module loaded
echo ""
echo "4. Checking I2C hardware module..."
if [ -n "$I2C_HW_MODULE" ]; then
    # Convert module name to use underscores for lsmod check (lsmod shows underscores)
    I2C_HW_MODULE_CHECK=$(echo "$I2C_HW_MODULE" | tr '-' '_')
    if lsmod | grep -q "^${I2C_HW_MODULE_CHECK} "; then
        print_status 0 "I2C hardware module $I2C_HW_MODULE is loaded"
    else
        # Also check with hyphens (some systems may show both)
        if lsmod | grep -q "^${I2C_HW_MODULE} "; then
            print_status 0 "I2C hardware module $I2C_HW_MODULE is loaded"
        else
            print_status 1 "I2C hardware module $I2C_HW_MODULE is NOT loaded"
            if [ "$EUID" -eq 0 ]; then
                if modprobe "$I2C_HW_MODULE" 2>/dev/null; then
                    print_info "Loaded $I2C_HW_MODULE"
                    FIXES_APPLIED=$((FIXES_APPLIED + 1))
                    # Add to /etc/modules if not already there
                    if ! grep -q "^${I2C_HW_MODULE}" /etc/modules 2>/dev/null; then
                        echo "$I2C_HW_MODULE" >> /etc/modules
                        print_info "Added $I2C_HW_MODULE to /etc/modules"
                    fi
                else
                    print_warn "Failed to load $I2C_HW_MODULE (may require reboot)"
                fi
            else
                echo "   Run as root to load module: sudo modprobe $I2C_HW_MODULE"
            fi
        fi
    fi
else
    # Try to auto-detect any I2C BCM module
    if lsmod | grep -q "i2c_bcm\|i2c-bcm"; then
        print_status 0 "I2C hardware module loaded"
    else
        print_status 1 "Cannot check - I2C hardware module unknown"
        echo "   Check manually: lsmod | grep i2c"
    fi
fi

# Check 5: I2C device module loaded
echo ""
echo "5. Checking I2C device module..."
if lsmod | grep -q "^i2c_dev"; then
    print_status 0 "I2C device module i2c-dev is loaded"
else
    print_status 1 "I2C device module i2c-dev is NOT loaded"
    if [ "$EUID" -eq 0 ]; then
        if modprobe i2c-dev 2>/dev/null; then
            print_info "Loaded i2c-dev"
            FIXES_APPLIED=$((FIXES_APPLIED + 1))
            # Add to /etc/modules if not already there
            if ! grep -q "^i2c-dev" /etc/modules 2>/dev/null; then
                echo "i2c-dev" >> /etc/modules
                print_info "Added i2c-dev to /etc/modules"
            fi
        else
            print_warn "Failed to load i2c-dev (may require reboot)"
        fi
    else
        echo "   Run as root to load module: sudo modprobe i2c-dev"
    fi
fi

# Check 6: I2C device file exists
echo ""
echo "6. Checking I2C device file..."
sleep 1  # Wait a moment for device to appear
if [ -e /dev/i2c-1 ]; then
    print_status 0 "I2C device /dev/i2c-1 exists"
    ls -l /dev/i2c-1 | awk '{print "   " $0}'
else
    print_status 1 "I2C device /dev/i2c-1 NOT found"
    if [ -n "$I2C_HW_MODULE" ] && [ "$EUID" -eq 0 ]; then
        print_info "Trying to load modules again..."
        modprobe "$I2C_HW_MODULE" 2>/dev/null || true
        modprobe i2c-dev 2>/dev/null || true
        sleep 1
        if [ -e /dev/i2c-1 ]; then
            print_info "I2C device appeared after loading modules"
            FIXES_APPLIED=$((FIXES_APPLIED + 1))
        else
            print_warn "I2C device still not found - reboot may be required"
        fi
    fi
fi

# Check 7: I2C device permissions
echo ""
echo "7. Checking I2C device permissions..."
if [ -e /dev/i2c-1 ]; then
    PERMS=$(stat -c "%a" /dev/i2c-1 2>/dev/null || echo "unknown")
    GROUP=$(stat -c "%G" /dev/i2c-1 2>/dev/null || echo "unknown")
    if [ "$GROUP" = "i2c" ] && [ "$PERMS" = "660" ]; then
        print_status 0 "I2C device permissions correct (660, group i2c)"
    else
        print_status 1 "I2C device permissions: $PERMS, group: $GROUP"
        echo "   Expected: 660, group i2c"
        if [ "$EUID" -eq 0 ]; then
            chmod 660 /dev/i2c-1 2>/dev/null || true
            chgrp i2c /dev/i2c-1 2>/dev/null || true
            print_info "Updated permissions (may require udev rules reload)"
        fi
    fi
else
    print_status 1 "Cannot check - /dev/i2c-1 not found"
fi

# Check 8: User in i2c group
echo ""
echo "8. Checking user groups..."
CURRENT_USER=${SUDO_USER:-$USER}
if [ "$CURRENT_USER" != "root" ]; then
    if groups "$CURRENT_USER" 2>/dev/null | grep -q "\bi2c\b"; then
        print_status 0 "User $CURRENT_USER is in i2c group"
    else
        print_status 1 "User $CURRENT_USER is NOT in i2c group"
        if [ "$EUID" -eq 0 ]; then
            usermod -aG i2c "$CURRENT_USER"
            print_info "Added $CURRENT_USER to i2c group (logout/login required)"
            FIXES_APPLIED=$((FIXES_APPLIED + 1))
        else
            echo "   Run as root to add user: sudo usermod -aG i2c $CURRENT_USER"
        fi
    fi
else
    print_info "Running as root - group check skipped"
fi

# Check 9: Scan for I2C devices
echo ""
echo "9. Scanning for I2C devices..."
if [ -e /dev/i2c-1 ] && command -v i2cdetect &> /dev/null; then
    if [ "$EUID" -eq 0 ] || groups | grep -q "\bi2c\b"; then
        print_info "Running i2cdetect -y 1..."
        I2C_OUTPUT=$(i2cdetect -y 1 2>&1)
        echo "$I2C_OUTPUT"
        if echo "$I2C_OUTPUT" | grep -q "60"; then
            print_status 0 "MCP9600 detected at address 0x60"
        else
            print_status 1 "MCP9600 NOT detected at address 0x60"
            echo "   Check wiring: VCC→3.3V, GND→Ground, SDA→GPIO2, SCL→GPIO3"
        fi
    else
        print_warn "Cannot scan - run as root or user in i2c group"
        echo "   Run: sudo i2cdetect -y 1"
    fi
else
    if [ ! -e /dev/i2c-1 ]; then
        print_status 1 "Cannot scan - /dev/i2c-1 not found"
    else
        print_status 1 "Cannot scan - i2c-tools not installed"
        echo "   Install: sudo apt-get install i2c-tools"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}All checks passed! I2C is working correctly.${NC}"
    exit 0
else
    echo -e "${RED}$ISSUES issue(s) found.${NC}"
    if [ $FIXES_APPLIED -gt 0 ]; then
        echo -e "${YELLOW}$FIXES_APPLIED fix(es) applied.${NC}"
    fi
    echo ""
    echo "Next steps:"
    if grep -q "I2C enabled" <<< "$(grep dtparam=i2c_arm=on ${I2C_CONFIG_FILE:-/boot/config.txt} 2>/dev/null || echo '')"; then
        echo "1. Reboot the system: sudo reboot"
        echo "2. After reboot, run this script again to verify"
    else
        echo "1. If I2C was just enabled in config.txt, reboot: sudo reboot"
        echo "2. If modules were loaded, try: sudo modprobe $I2C_HW_MODULE i2c-dev"
        echo "3. Run this script again to verify: sudo bash scripts/diagnose-i2c.sh"
    fi
    echo "4. Check HARDWARE_VERIFICATION.md for detailed troubleshooting"
    exit 1
fi

