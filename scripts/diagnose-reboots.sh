#!/bin/bash
# Diagnose Reboots and System Crashes
# Investigates why screen sessions disappear after connection drops

echo "=========================================="
echo "Reboot/Crash Diagnostic Script"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check 1: Recent reboots
echo "1. Recent Reboot History:"
if command -v last &> /dev/null; then
    REBOOTS=$(last reboot | head -5)
    if [ -n "$REBOOTS" ]; then
        echo "$REBOOTS" | sed 's/^/   /'
        REBOOT_COUNT=$(last reboot | wc -l)
        if [ "$REBOOT_COUNT" -gt 3 ]; then
            echo -e "   ${YELLOW}⚠ Multiple reboots detected ($REBOOT_COUNT)${NC}"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    else
        echo -e "   ${GREEN}✓ No recent reboots found${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ 'last' command not available${NC}"
fi
echo ""

# Check 2: Current uptime
echo "2. System Uptime:"
UPTIME=$(uptime)
echo "   $UPTIME"
UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
UPTIME_HOURS=$((UPTIME_SECONDS / 3600))
if [ "$UPTIME_HOURS" -lt 1 ]; then
    echo -e "   ${RED}✗ System recently rebooted (< 1 hour)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
elif [ "$UPTIME_HOURS" -lt 24 ]; then
    echo -e "   ${YELLOW}⚠ System uptime is less than 24 hours${NC}"
else
    echo -e "   ${GREEN}✓ System has been up for $UPTIME_HOURS hours${NC}"
fi
echo ""

# Check 3: Boot time
echo "3. Boot Time:"
if command -v who &> /dev/null; then
    BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "unknown")
    echo "   Boot time: $BOOT_TIME"
elif command -v systemd-analyze &> /dev/null; then
    BOOT_TIME=$(systemd-analyze | grep "Startup finished" | head -1 || echo "unknown")
    echo "   $BOOT_TIME"
fi
echo ""

# Check 4: Power supply issues (common cause of reboots)
echo "4. Power Supply Check:"
if command -v vcgencmd &> /dev/null; then
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    echo "   Throttled status: $THROTTLED"
    
    # Decode throttle flags
    if [ "$THROTTLED" != "0x0" ] && [ "$THROTTLED" != "0x50000" ]; then
        echo -e "   ${RED}✗ Power supply issues detected!${NC}"
        echo "   This can cause system crashes and reboots!"
        echo ""
        echo "   Throttle flags meaning:"
        echo "   0x1 = Under-voltage detected"
        echo "   0x2 = Arm frequency capped"
        echo "   0x4 = Currently throttled"
        echo "   0x8 = Soft temperature limit active"
        echo ""
        echo "   Historical flags (since last reboot):"
        echo "   0x10000 = Under-voltage has occurred"
        echo "   0x20000 = Arm frequency capping has occurred"
        echo "   0x40000 = Throttling has occurred"
        echo "   0x80000 = Soft temperature limit has occurred"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "   ${GREEN}✓ No power supply issues detected${NC}"
    fi
    
    # Check voltage
    VOLTAGE=$(vcgencmd measure_volts | cut -d= -f2)
    echo "   Core voltage: $VOLTAGE"
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available${NC}"
fi
echo ""

# Check 5: Temperature issues
echo "5. Temperature Check:"
if command -v vcgencmd &> /dev/null; then
    TEMP=$(vcgencmd measure_temp | cut -d= -f2)
    TEMP_VALUE=$(echo "$TEMP" | cut -d. -f1 | sed 's/[^0-9]//g')
    echo "   Temperature: $TEMP"
    if [ "$TEMP_VALUE" -gt 80 ]; then
        echo -e "   ${RED}✗ High temperature (>80°C) - may cause crashes${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    elif [ "$TEMP_VALUE" -gt 70 ]; then
        echo -e "   ${YELLOW}⚠ Warm temperature (>70°C)${NC}"
    else
        echo -e "   ${GREEN}✓ Temperature is normal${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available${NC}"
fi
echo ""

# Check 6: Recent crashes/panics in logs
echo "6. Recent System Crashes:"
CRASHES=$(dmesg | tail -100 | grep -iE "crash|panic|oom|killed|segfault" | tail -5)
if [ -n "$CRASHES" ]; then
    echo -e "   ${RED}✗ Recent crash/panic messages found:${NC}"
    echo "$CRASHES" | sed 's/^/   /'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✓ No recent crash/panic messages${NC}"
fi
echo ""

# Check 7: OOM (Out of Memory) killer
echo "7. Memory Issues:"
OOM_KILLS=$(dmesg | grep -i "out of memory\|oom killer" | tail -5)
if [ -n "$OOM_KILLS" ]; then
    echo -e "   ${RED}✗ Out of memory events detected:${NC}"
    echo "$OOM_KILLS" | sed 's/^/   /'
    echo "   This can cause processes (including screen) to be killed!"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✓ No out of memory events${NC}"
fi

MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100}')
echo "   Current memory usage: ${MEM_USAGE}%"
if [ "$MEM_USAGE" -gt 90 ]; then
    echo -e "   ${RED}✗ Very high memory usage (may cause OOM kills)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check 8: Screen session persistence
echo "8. Screen Session Configuration:"
if command -v screen &> /dev/null; then
    SCREEN_VERSION=$(screen -v 2>&1 | head -1)
    echo "   $SCREEN_VERSION"
    
    # Check if screen sessions survive
    SCREEN_SOCK_DIR="${HOME}/.screen"
    if [ -d "$SCREEN_SOCK_DIR" ]; then
        echo -e "   ${GREEN}✓ Screen socket directory exists${NC}"
    else
        echo -e "   ${YELLOW}⚠ Screen socket directory not found${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ screen not installed${NC}"
fi
echo ""

# Check 9: SSH connection drops
echo "9. SSH Connection History:"
if [ -f /var/log/auth.log ]; then
    SSH_DISCONNECTS=$(grep "Disconnected from" /var/log/auth.log | tail -5)
    if [ -n "$SSH_DISCONNECTS" ]; then
        echo "   Recent SSH disconnections:"
        echo "$SSH_DISCONNECTS" | sed 's/^/   /' | tail -3
    fi
elif [ -f /var/log/messages ]; then
    SSH_DISCONNECTS=$(grep "Disconnected from" /var/log/messages | tail -5)
    if [ -n "$SSH_DISCONNECTS" ]; then
        echo "   Recent SSH disconnections:"
        echo "$SSH_DISCONNECTS" | sed 's/^/   /' | tail -3
    fi
fi
echo ""

# Check 10: SD card issues (can cause freezes/reboots)
echo "10. SD Card Health:"
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo "   Disk usage: ${DISK_USAGE}%"

# Check for filesystem errors
FS_ERRORS=$(dmesg | tail -100 | grep -iE "ext4.*error|filesystem.*error|I/O error.*mmc" | tail -3)
if [ -n "$FS_ERRORS" ]; then
    echo -e "   ${RED}✗ Filesystem errors detected:${NC}"
    echo "$FS_ERRORS" | sed 's/^/   /'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo -e "   ${GREEN}✓ No filesystem errors detected${NC}"
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
    echo "If screen sessions are disappearing:"
    echo "  1. Screen sessions don't survive reboots"
    echo "  2. Check if Pi is rebooting: last reboot"
    echo "  3. Use tmux instead (more persistent):"
    echo "     tmux new -s install"
    echo "  4. Check for manual screen cleanup"
    echo "  5. Monitor system: watch -n 5 'uptime && screen -ls'"
else
    echo -e "${RED}✗ $ISSUES_FOUND potential issue(s) found${NC}"
    echo ""
    echo "Likely causes of disappearing screen sessions:"
    echo ""
    
    if echo "$THROTTLED" | grep -q "[^0x50000]"; then
        echo "1. Power supply issues (MOST LIKELY):"
        echo "   - Under-voltage causes system crashes/reboots"
        echo "   - Fix: Use official Raspberry Pi power supply (5V, 2.5A+)"
        echo "   - Check: vcgencmd get_throttled (should be 0x0)"
        echo ""
    fi
    
    if [ "$MEM_USAGE" -gt 90 ]; then
        echo "2. Memory issues:"
        echo "   - High memory usage can cause OOM kills"
        echo "   - Fix: Close unnecessary processes"
        echo "   - Add swap: sudo dphys-swapfile swapoff && sudo dphys-swapfile swapon"
        echo ""
    fi
    
    if [ -n "$CRASHES" ] || [ -n "$OOM_KILLS" ]; then
        echo "3. System crashes:"
        echo "   - Check logs: sudo journalctl -b -1 (previous boot)"
        echo "   - Check dmesg: dmesg | tail -50"
        echo ""
    fi
    
    echo "4. Use tmux instead of screen (more reliable):"
    echo "   sudo apt install tmux"
    echo "   tmux new -s install"
    echo "   # Detach: Ctrl+B then D"
    echo "   # Reattach: tmux attach -t install"
    echo ""
fi

echo "Monitoring commands:"
echo "  # Check uptime continuously"
echo "  watch -n 5 uptime"
echo ""
echo "  # Monitor for reboots"
echo "  watch -n 10 'last reboot | head -3'"
echo ""
echo "  # Monitor power supply"
echo "  watch -n 5 'vcgencmd get_throttled'"
echo ""
echo "  # Check screen sessions"
echo "  screen -ls"
echo ""

