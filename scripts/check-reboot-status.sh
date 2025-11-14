#!/bin/bash
# Quick Check: Has Pi Rebooted Recently?

echo "=========================================="
echo "Reboot Status Check"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check uptime
UPTIME=$(uptime)
UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo "0")
UPTIME_MINUTES=$((UPTIME_SECONDS / 60))
UPTIME_HOURS=$((UPTIME_SECONDS / 3600))

echo "Current Uptime:"
echo "  $UPTIME"
echo ""

if [ "$UPTIME_MINUTES" -lt 10 ]; then
    echo -e "${RED}✗ SYSTEM RECENTLY REBOOTED (< 10 minutes ago)${NC}"
    echo ""
    echo "This explains why your screen session disappeared!"
    echo "Screen sessions don't survive reboots."
    echo ""
    echo "Likely causes:"
    echo "  1. Power supply issues (undervoltage)"
    echo "  2. System crash"
    echo "  3. Manual reboot"
    echo ""
elif [ "$UPTIME_HOURS" -lt 1 ]; then
    echo -e "${YELLOW}⚠ System recently rebooted (< 1 hour ago)${NC}"
    echo ""
else
    echo -e "${GREEN}✓ System has been up for $UPTIME_HOURS hours${NC}"
    echo ""
    echo "If screen session disappeared but Pi didn't reboot:"
    echo "  - Screen session may have been manually killed"
    echo "  - Check: screen -ls"
    echo "  - Use tmux instead (more persistent)"
    echo ""
fi

# Check boot time
if command -v who &> /dev/null; then
    BOOT_TIME=$(who -b 2>/dev/null | awk '{print $3, $4}' || echo "unknown")
    echo "Boot time: $BOOT_TIME"
fi

# Check power supply
if command -v vcgencmd &> /dev/null; then
    echo ""
    echo "Power Supply Status:"
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    echo "  Throttled: $THROTTLED"
    
    if [ "$THROTTLED" != "0x0" ] && [ "$THROTTLED" != "0x50000" ]; then
        echo -e "  ${RED}✗ Power supply issues detected!${NC}"
        echo "  This likely caused the reboot!"
        echo ""
        echo "  Fix: Use official Raspberry Pi power supply (5V, 2.5A+)"
    elif echo "$THROTTLED" | grep -q "0x50000"; then
        echo -e "  ${YELLOW}⚠ Undervoltage has occurred (historical)${NC}"
        echo "  Check power supply quality"
    else
        echo -e "  ${GREEN}✓ Power supply OK${NC}"
    fi
fi

echo ""
echo "=========================================="
echo "Recommendations"
echo "=========================================="
echo ""

if [ "$UPTIME_MINUTES" -lt 10 ]; then
    echo "1. Fix power supply (MOST IMPORTANT):"
    echo "   - Use official Raspberry Pi power supply"
    echo "   - Check power cable quality"
    echo "   - Avoid USB hubs for power"
    echo ""
    echo "2. Run full diagnostics:"
    echo "   sudo bash scripts/diagnose-reboots.sh"
    echo ""
fi

echo "3. Use tmux for long-running processes (survives connection drops):"
echo "   tmux new -s install"
echo "   # Your commands here"
echo "   # Detach: Ctrl+B then D"
echo "   # Reattach: tmux attach -t install"
echo ""
echo "4. Monitor for reboots:"
echo "   watch -n 10 uptime"
echo ""

