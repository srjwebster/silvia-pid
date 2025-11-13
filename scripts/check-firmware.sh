#!/bin/bash
# Raspberry Pi Firmware Status Check Script

echo "=========================================="
echo "Raspberry Pi Firmware Status Check"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check 1: Firmware version
echo "1. Firmware Version:"
if command -v vcgencmd &> /dev/null; then
    FIRMWARE_VERSION=$(vcgencmd version)
    echo "   $FIRMWARE_VERSION"
    # Extract date from version string
    FIRMWARE_DATE=$(echo "$FIRMWARE_VERSION" | grep -oE "[A-Z][a-z]{2} [0-9]{1,2} [0-9]{4}" | head -1)
    if [ -n "$FIRMWARE_DATE" ]; then
        echo -e "   ${GREEN}✓ Firmware date: $FIRMWARE_DATE${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available${NC}"
fi
echo ""

# Check 2: Kernel version
echo "2. Kernel Version:"
KERNEL_VERSION=$(uname -r)
KERNEL_DATE=$(uname -v | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1)
echo "   Kernel: $KERNEL_VERSION"
if [ -n "$KERNEL_DATE" ]; then
    echo "   Build date: $KERNEL_DATE"
    echo -e "   ${GREEN}✓ Kernel is recent${NC}"
fi
echo ""

# Check 3: OS version
echo "3. Operating System:"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "   OS: $PRETTY_NAME"
    echo "   Version: $VERSION_ID"
    echo "   Codename: $VERSION_CODENAME"
fi
echo ""

# Check 4: Available updates
echo "4. Available Updates:"
if command -v apt &> /dev/null; then
    echo "   Checking for updates..."
    apt update -qq 2>/dev/null
    UPDATABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    UPDATABLE=$((UPDATABLE - 1))  # Subtract header line
    
    if [ "$UPDATABLE" -eq 0 ]; then
        echo -e "   ${GREEN}✓ No updates available (system is up to date)${NC}"
    else
        echo -e "   ${YELLOW}⚠ $UPDATABLE package(s) can be upgraded${NC}"
        echo "   Upgradable packages:"
        apt list --upgradable 2>/dev/null | grep -v "Listing..." | sed 's/^/     /'
        echo ""
        echo "   To upgrade: sudo apt full-upgrade"
    fi
else
    echo -e "   ${YELLOW}⚠ apt not available${NC}"
fi
echo ""

# Check 5: Firmware packages
echo "5. Firmware Package Versions:"
if command -v dpkg &> /dev/null; then
    FIRMWARE_PKGS=$(dpkg -l | grep -iE "firmware|rpi" | grep -v "^rc" | head -5)
    if [ -n "$FIRMWARE_PKGS" ]; then
        echo "$FIRMWARE_PKGS" | awk '{printf "   %s: %s\n", $2, $3}'
    else
        echo "   No firmware packages found"
    fi
fi
echo ""

# Check 6: I2C hardware status
echo "6. I2C Hardware Status:"
if lsmod | grep -q "i2c_bcm\|i2c-bcm"; then
    echo -e "   ${GREEN}✓ I2C hardware module loaded${NC}"
    lsmod | grep "i2c_bcm\|i2c-bcm" | awk '{print "     " $0}'
else
    echo -e "   ${YELLOW}⚠ I2C hardware module not loaded${NC}"
fi

if [ -e /dev/i2c-1 ]; then
    echo -e "   ${GREEN}✓ I2C device /dev/i2c-1 exists${NC}"
else
    echo -e "   ${RED}✗ I2C device /dev/i2c-1 NOT found${NC}"
fi
echo ""

# Check 7: GPIO access
echo "7. GPIO Access:"
if [ -e /dev/gpiomem ]; then
    echo -e "   ${GREEN}✓ GPIO device /dev/gpiomem exists${NC}"
else
    echo -e "   ${YELLOW}⚠ GPIO device /dev/gpiomem NOT found${NC}"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary and Recommendations"
echo "=========================================="
echo ""

# Check if firmware is reasonably recent (within last 6 months)
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)

if [ -n "$FIRMWARE_DATE" ]; then
    FIRMWARE_YEAR=$(echo "$FIRMWARE_DATE" | awk '{print $3}')
    FIRMWARE_MONTH=$(date -d "$FIRMWARE_DATE" +%m 2>/dev/null || echo "01")
    
    if [ "$FIRMWARE_YEAR" = "$CURRENT_YEAR" ]; then
        MONTH_DIFF=$((CURRENT_MONTH - FIRMWARE_MONTH))
        if [ "$MONTH_DIFF" -le 6 ] && [ "$MONTH_DIFF" -ge 0 ]; then
            echo -e "${GREEN}✓ Firmware is recent (within last 6 months)${NC}"
            echo ""
            echo "Your firmware appears to be up to date."
            echo "If you're experiencing hardware issues, they're likely not firmware-related."
        else
            echo -e "${YELLOW}⚠ Firmware may be outdated (older than 6 months)${NC}"
            echo ""
            echo "Consider updating firmware:"
            echo "  sudo apt update"
            echo "  sudo apt full-upgrade"
            echo "  sudo reboot"
        fi
    else
        echo -e "${YELLOW}⚠ Firmware is from a different year${NC}"
        echo ""
        echo "Consider updating firmware:"
        echo "  sudo apt update"
        echo "  sudo apt full-upgrade"
        echo "  sudo reboot"
    fi
else
    echo -e "${YELLOW}⚠ Could not determine firmware age${NC}"
fi

echo ""
echo "For Debian Trixie:"
echo "  - Firmware updates come through apt (not rpi-update)"
echo "  - Run: sudo apt update && sudo apt full-upgrade"
echo "  - Reboot after upgrading: sudo reboot"
echo ""
echo "Note: rpi-update is for advanced users and may cause issues"
echo "      on Debian. Use apt instead."

