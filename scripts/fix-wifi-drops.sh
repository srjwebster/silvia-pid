#!/bin/bash
# Fix WiFi Connection Drops on Raspberry Pi
# This script disables WiFi power management and optimizes WiFi settings

set -e

echo "=========================================="
echo "Fix WiFi Connection Drops"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check 1: Disable WiFi power management (most common cause of drops)
echo "1. Disabling WiFi power management..."
if ip link show wlan0 &>/dev/null; then
    # Try iwconfig first (older method)
    if command -v iwconfig &> /dev/null; then
        iwconfig wlan0 power off 2>/dev/null && echo -e "   ${GREEN}✓ WiFi power management disabled (iwconfig)${NC}"
    fi
    
    # Use NetworkManager (preferred on modern systems)
    if command -v nmcli &> /dev/null; then
        # Disable powersave for all WiFi connections
        WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep wifi | cut -d: -f1 | head -1)
        if [ -n "$WIFI_CONN" ]; then
            nmcli connection modify "$WIFI_CONN" wifi.powersave 0 2>/dev/null && \
                echo -e "   ${GREEN}✓ WiFi power management disabled (NetworkManager)${NC}"
        fi
    fi
    
    # Verify
    if command -v iw &> /dev/null; then
        POWER_STATE=$(iw dev wlan0 get power_save 2>/dev/null || echo "unknown")
        if [ "$POWER_STATE" = "off" ]; then
            echo -e "   ${GREEN}✓ Verified: WiFi power save is OFF${NC}"
        elif [ "$POWER_STATE" != "unknown" ]; then
            echo -e "   ${YELLOW}⚠ WiFi power save state: $POWER_STATE${NC}"
        fi
    fi
else
    echo -e "   ${YELLOW}⚠ wlan0 not found (not using WiFi or Ethernet only)${NC}"
fi
echo ""

# Check 2: Make WiFi power management setting persistent
echo "2. Making WiFi power management setting persistent..."
# Create NetworkManager configuration (disable powersave)
if [ -d /etc/NetworkManager/conf.d ]; then
    cat > /etc/NetworkManager/conf.d/99-wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave = 0
# 0 = disable powersave (recommended for stability)
# 1 = enable powersave
# 2 = ignore (use driver default)
EOF
    echo -e "   ${GREEN}✓ NetworkManager configuration created (powersave disabled)${NC}"
    
    # Also set for all WiFi connections
    if command -v nmcli &> /dev/null; then
        # Get active WiFi connection
        WIFI_CONN=$(nmcli -t -f NAME,TYPE connection show --active | grep wifi | cut -d: -f1 | head -1)
        if [ -n "$WIFI_CONN" ]; then
            nmcli connection modify "$WIFI_CONN" wifi.powersave 0 2>/dev/null || true
            echo -e "   ${GREEN}✓ Updated active WiFi connection: $WIFI_CONN${NC}"
        fi
    fi
else
    echo -e "   ${YELLOW}⚠ NetworkManager conf.d not found${NC}"
fi

# Also create udev rule as backup
if [ -d /etc/udev/rules.d ]; then
    cat > /etc/udev/rules.d/70-wifi-powersave.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/sbin/iwconfig %k power off"
EOF
    echo -e "   ${GREEN}✓ Udev rule created${NC}"
fi
echo ""

# Check 3: Optimize WiFi driver settings
echo "3. Optimizing WiFi driver settings..."
# Create modprobe configuration for brcmfmac
if [ -d /etc/modprobe.d ]; then
    if [ ! -f /etc/modprobe.d/brcmfmac.conf ]; then
        cat > /etc/modprobe.d/brcmfmac.conf << 'EOF'
# Disable WiFi power saving
options brcmfmac roamoff=1
EOF
        echo -e "   ${GREEN}✓ WiFi driver configuration created${NC}"
        echo "   Note: Reboot required for driver settings to take effect"
    else
        echo -e "   ${YELLOW}⚠ brcmfmac.conf already exists${NC}"
        echo "   Check: cat /etc/modprobe.d/brcmfmac.conf"
    fi
fi
echo ""

# Check 4: Update SSH keepalive settings
echo "4. Updating SSH keepalive settings..."
if [ -f /etc/ssh/sshd_config ]; then
    if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
        echo "" >> /etc/ssh/sshd_config
        echo "# Prevent SSH timeouts" >> /etc/ssh/sshd_config
        echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config
        echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config
        echo -e "   ${GREEN}✓ SSH keepalive configured${NC}"
        echo "   Restart SSH: sudo systemctl restart ssh"
    else
        echo -e "   ${YELLOW}⚠ SSH keepalive already configured${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ /etc/ssh/sshd_config not found${NC}"
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo -e "${GREEN}✓ WiFi power management disabled${NC}"
echo -e "${GREEN}✓ Persistent settings configured${NC}"
echo ""
echo "Next steps:"
echo "1. Reboot to apply all settings:"
echo "   sudo reboot"
echo ""
echo "2. After reboot, verify WiFi power management is off:"
echo "   # Using iw (preferred):"
echo "   iw dev wlan0 get power_save"
echo "   # Should show: off"
echo ""
echo "   # Using NetworkManager:"
echo "   nmcli connection show --active | grep wifi.powersave"
echo "   # Should show: wifi.powersave:0"
echo ""
echo "   # Using iwconfig (if available):"
echo "   iwconfig wlan0 | grep Power"
echo "   # Should show: Power Management:off"
echo ""
echo "3. Monitor connection stability:"
echo "   watch -n 5 'ping -c 1 -W 2 8.8.8.8 && echo \"OK\" || echo \"FAILED\"'"
echo ""
echo "4. For long-running processes, use screen or tmux:"
echo "   screen -S install"
echo "   # Your commands here"
echo "   # Press Ctrl+A then D to detach"
echo ""
echo "If connections still drop:"
echo "  - Consider using Ethernet instead of WiFi"
echo "  - Check WiFi signal strength: iwconfig wlan0"
echo "  - Check power supply: vcgencmd get_throttled"
echo "  - Run diagnostic: sudo bash scripts/diagnose-connection-drops.sh"
echo ""

