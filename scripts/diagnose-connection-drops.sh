#!/bin/bash
# Connection Drop Diagnostic Script
# Investigates why Raspberry Pi connections drop periodically

echo "=========================================="
echo "Connection Drop Diagnostic Script"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check 1: Network interface type
echo "1. Network Interface Status:"
INTERFACE=""
if ip link show eth0 | grep -q "state UP" && ip link show eth0 | grep -q "LOWER_UP"; then
    INTERFACE="eth0"
    echo -e "   ${GREEN}✓ Using Ethernet (eth0) - more stable than WiFi${NC}"
elif ip link show wlan0 | grep -q "state UP" && ip link show wlan0 | grep -q "LOWER_UP"; then
    INTERFACE="wlan0"
    echo -e "   ${YELLOW}⚠ Using WiFi (wlan0) - more prone to drops${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${RED}✗ No active network interface found${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if [ -n "$INTERFACE" ]; then
    ip link show "$INTERFACE" | grep -E "state|mtu" | sed 's/^/   /'
fi
echo ""

# Check 2: WiFi power management (major cause of drops)
if [ "$INTERFACE" = "wlan0" ]; then
    echo "2. WiFi Power Management:"
    if command -v iwconfig &> /dev/null; then
        POWER_MGMT=$(iwconfig wlan0 2>/dev/null | grep -o "Power Management:.*" | awk '{print $3}')
        if [ "$POWER_MGMT" = "on" ]; then
            echo -e "   ${RED}✗ WiFi power management is ON (causes connection drops)${NC}"
            echo "   This is a common cause of periodic disconnections!"
            echo "   Fix: sudo iwconfig wlan0 power off"
            echo "   Or disable in /etc/network/interfaces.d/wlan0"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        else
            echo -e "   ${GREEN}✓ WiFi power management is OFF${NC}"
        fi
        iwconfig wlan0 2>/dev/null | grep -i "power" | sed 's/^/   /'
    else
        echo -e "   ${YELLOW}⚠ iwconfig not available${NC}"
    fi
    echo ""
fi

# Check 3: Power supply (undervoltage causes drops)
echo "3. Power Supply Check:"
if command -v vcgencmd &> /dev/null; then
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    if [ "$THROTTLED" != "0x0" ]; then
        echo -e "   ${RED}✗ Power supply issues detected: $THROTTLED${NC}"
        echo "   Undervoltage causes system instability and connection drops!"
        echo "   Fix: Use official Raspberry Pi power supply (5V, 2.5A+)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "   ${GREEN}✓ Power supply OK (no throttling)${NC}"
    fi
    
    # Check throttling history
    THROTTLE_HISTORY=$(vcgencmd get_throttled | cut -d= -f2)
    if [ "$THROTTLE_HISTORY" != "0x0" ] && [ "$THROTTLE_HISTORY" != "0x50000" ]; then
        echo "   Throttling history: $THROTTLE_HISTORY"
        echo "   (Check bit flags: https://www.raspberrypi.org/documentation/raspbian/applications/vcgencmd.md)"
    fi
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available${NC}"
fi
echo ""

# Check 4: WiFi signal strength
if [ "$INTERFACE" = "wlan0" ]; then
    echo "4. WiFi Signal Strength:"
    if command -v iwconfig &> /dev/null; then
        SIGNAL=$(iwconfig wlan0 2>/dev/null | grep -o "Signal level=.*" | awk '{print $2}' | cut -d= -f2)
        if [ -n "$SIGNAL" ]; then
            SIGNAL_DB=$(echo "$SIGNAL" | sed 's/dBm//')
            echo "   Signal: $SIGNAL"
            # Convert dBm to approximate percentage (rough estimate)
            if [ "$SIGNAL_DB" -gt -50 ]; then
                echo -e "   ${GREEN}✓ Excellent signal strength${NC}"
            elif [ "$SIGNAL_DB" -gt -70 ]; then
                echo -e "   ${GREEN}✓ Good signal strength${NC}"
            elif [ "$SIGNAL_DB" -gt -80 ]; then
                echo -e "   ${YELLOW}⚠ Fair signal strength (may cause drops)${NC}"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            else
                echo -e "   ${RED}✗ Poor signal strength (likely causing drops)${NC}"
                echo "   Fix: Move Pi closer to router or use WiFi extender"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi
        iwconfig wlan0 2>/dev/null | grep -i "signal\|link" | sed 's/^/   /'
    else
        echo -e "   ${YELLOW}⚠ iwconfig not available${NC}"
    fi
    echo ""
fi

# Check 5: Recent disconnections in system logs
echo "5. Recent Disconnection Events:"
RECENT_DROPS=$(dmesg | tail -100 | grep -iE "disconnect|link down|carrier.*lost|wlan.*down|network.*down" | tail -5)
if [ -n "$RECENT_DROPS" ]; then
    echo -e "   ${RED}✗ Recent disconnection events found:${NC}"
    echo "$RECENT_DROPS" | sed 's/^/   /'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✓ No recent disconnection events in kernel log${NC}"
fi
echo ""

# Check 6: WiFi driver/firmware version
if [ "$INTERFACE" = "wlan0" ]; then
    echo "6. WiFi Driver/Firmware:"
    DRIVER_INFO=$(dmesg | grep -i "brcmfmac.*Firmware:" | tail -1)
    if [ -n "$DRIVER_INFO" ]; then
        echo "   $DRIVER_INFO" | sed 's/^/   /'
        # Check if firmware is old (before 2024)
        if echo "$DRIVER_INFO" | grep -qE "202[0-3]"; then
            echo -e "   ${YELLOW}⚠ WiFi firmware may be outdated (consider updating)${NC}"
            echo "   Update: sudo apt update && sudo apt full-upgrade"
        else
            echo -e "   ${GREEN}✓ WiFi firmware appears recent${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠ Could not determine WiFi firmware version${NC}"
    fi
    echo ""
fi

# Check 7: System load and memory
echo "7. System Resource Usage:"
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_COUNT=$(nproc)
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100}')
echo "   Load average: $LOAD_AVG (CPUs: $CPU_COUNT)"
echo "   Memory usage: ${MEM_USAGE}%"

if [ -n "$LOAD_AVG" ] && [ -n "$CPU_COUNT" ]; then
    LOAD_CHECK=$(echo "$LOAD_AVG $CPU_COUNT" | awk '{if ($1 > $2 * 2) print 1; else print 0}')
    if [ "$LOAD_CHECK" = "1" ]; then
        echo -e "   ${YELLOW}⚠ High system load (may cause timeouts)${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
fi

if [ "$MEM_USAGE" -gt 90 ]; then
    echo -e "   ${RED}✗ High memory usage: ${MEM_USAGE}% (may cause freezes)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check 8: SD card health (slow I/O causes timeouts)
echo "8. SD Card Health:"
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
IO_WAIT=$(iostat -x 1 2 2>/dev/null | tail -1 | awk '{print $10}' || echo "N/A")
echo "   Disk usage: ${DISK_USAGE}%"

# Check for slow I/O in dmesg
SLOW_IO=$(dmesg | tail -50 | grep -iE "slow.*io|mmc.*timeout|sd.*timeout" | tail -3)
if [ -n "$SLOW_IO" ]; then
    echo -e "   ${RED}✗ Slow I/O detected (may cause timeouts):${NC}"
    echo "$SLOW_IO" | sed 's/^/     /'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✓ No slow I/O issues detected${NC}"
fi
echo ""

# Check 9: SSH keepalive settings
echo "9. SSH Connection Settings:"
if [ -f /etc/ssh/sshd_config ]; then
    CLIENT_ALIVE=$(grep -E "^ClientAliveInterval|^#ClientAliveInterval" /etc/ssh/sshd_config | tail -1)
    if echo "$CLIENT_ALIVE" | grep -q "^ClientAliveInterval" && ! echo "$CLIENT_ALIVE" | grep -q "^#"; then
        INTERVAL=$(echo "$CLIENT_ALIVE" | awk '{print $2}')
        echo "   ClientAliveInterval: $INTERVAL seconds"
        if [ "$INTERVAL" -lt 60 ]; then
            echo -e "   ${GREEN}✓ SSH keepalive configured (prevents timeouts)${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠ SSH keepalive not configured (may timeout on idle)${NC}"
        echo "   Fix: Add to /etc/ssh/sshd_config:"
        echo "        ClientAliveInterval 60"
        echo "        ClientAliveCountMax 3"
    fi
else
    echo -e "   ${YELLOW}⚠ Could not check SSH config${NC}"
fi
echo ""

# Check 10: Network interface errors
echo "10. Network Interface Errors:"
if [ -n "$INTERFACE" ]; then
    RX_ERRORS=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_errors 2>/dev/null || echo "0")
    TX_ERRORS=$(cat /sys/class/net/"$INTERFACE"/statistics/tx_errors 2>/dev/null || echo "0")
    RX_DROPPED=$(cat /sys/class/net/"$INTERFACE"/statistics/rx_dropped 2>/dev/null || echo "0")
    TX_DROPPED=$(cat /sys/class/net/"$INTERFACE"/statistics/tx_dropped 2>/dev/null || echo "0")
    
    echo "   RX errors: $RX_ERRORS"
    echo "   TX errors: $TX_ERRORS"
    echo "   RX dropped: $RX_DROPPED"
    echo "   TX dropped: $TX_DROPPED"
    
    TOTAL_ERRORS=$((RX_ERRORS + TX_ERRORS + RX_DROPPED + TX_DROPPED))
    if [ "$TOTAL_ERRORS" -gt 100 ]; then
        echo -e "   ${RED}✗ High error count (may indicate connection issues)${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    elif [ "$TOTAL_ERRORS" -gt 10 ]; then
        echo -e "   ${YELLOW}⚠ Some errors detected${NC}"
    else
        echo -e "   ${GREEN}✓ Low error count (normal)${NC}"
    fi
fi
echo ""

# Summary
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious issues found${NC}"
    echo ""
    echo "If connections are still dropping:"
    echo "  1. Check router/AP logs"
    echo "  2. Try using Ethernet instead of WiFi"
    echo "  3. Check for interference (microwaves, other WiFi networks)"
    echo "  4. Monitor connections: watch -n 1 'ping -c 1 8.8.8.8'"
else
    echo -e "${RED}✗ $ISSUES_FOUND potential issue(s) found${NC}"
    echo ""
    echo "Recommended fixes:"
    echo ""
    
    if [ "$INTERFACE" = "wlan0" ]; then
        echo "1. Disable WiFi power management:"
        echo "   sudo iwconfig wlan0 power off"
        echo "   (Add to /etc/rc.local or systemd service to persist)"
        echo ""
        echo "2. Use Ethernet if possible (more stable)"
        echo ""
    fi
    
    if [ -n "$THROTTLED" ] && [ "$THROTTLED" != "0x0" ]; then
        echo "3. Fix power supply:"
        echo "   - Use official Raspberry Pi power supply (5V, 2.5A+)"
        echo "   - Check power cable quality"
        echo "   - Avoid USB hubs for power"
        echo ""
    fi
    
    echo "4. For long-running processes, use screen or tmux:"
    echo "   sudo apt install screen"
    echo "   screen -S install"
    echo "   sudo bash deploy/install.sh"
    echo "   # Press Ctrl+A then D to detach"
    echo "   # Reattach: screen -r install"
    echo ""
    echo "   OR use tmux:"
    echo "   sudo apt install tmux"
    echo "   tmux new -s install"
    echo "   sudo bash deploy/install.sh"
    echo "   # Press Ctrl+B then D to detach"
    echo "   # Reattach: tmux attach -t install"
    echo ""
fi

echo "For persistent connection monitoring:"
echo "  # Monitor connection stability"
echo "  while true; do ping -c 1 -W 2 8.8.8.8 && echo \"$(date): OK\" || echo \"$(date): FAILED\"; sleep 5; done"
echo ""
echo "See TROUBLESHOOTING_PIPE_DROPS.md for more details."

