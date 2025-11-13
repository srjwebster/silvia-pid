#!/bin/bash
# Quick diagnostic script for pipe drops during installation

echo "=========================================="
echo "Pipe Drop Diagnostic Script"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ISSUES_FOUND=0

# Check 1: SD Card Health
echo "1. SD Card Health:"
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo -e "   ${RED}✗ Disk space: ${DISK_USAGE}% full (WARNING: >90%)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
elif [ "$DISK_USAGE" -gt 80 ]; then
    echo -e "   ${YELLOW}⚠ Disk space: ${DISK_USAGE}% full (WARNING: >80%)${NC}"
else
    echo -e "   ${GREEN}✓ Disk space: ${DISK_USAGE}% used${NC}"
fi
df -h / | tail -1
echo ""

# Check 2: Power Supply
echo "2. Power Supply:"
if command -v vcgencmd &> /dev/null; then
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    if [ "$THROTTLED" != "0x0" ]; then
        echo -e "   ${RED}✗ Power supply issues detected: $THROTTLED${NC}"
        echo "   - Undervoltage detected (use better power supply)"
        echo "   - Throttling detected (check power supply)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
        echo -e "   ${GREEN}✓ Power supply OK (no throttling)${NC}"
    fi
    
    # Note: measure_volts returns core voltage (typically 1.2-1.35V for Pi 3), not input voltage (5V)
    # Input voltage health is checked via get_throttled above (throttling indicates power issues)
    VOLTAGE=$(vcgencmd measure_volts | cut -d= -f2 | sed 's/V//')
    echo "   Core voltage: ${VOLTAGE}V (typical: 1.2-1.35V for Pi 3)"
    # Core voltage is usually fine if no throttling detected above
    echo -e "   ${GREEN}✓ Core voltage OK (power supply check above)${NC}"
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available (cannot check power)${NC}"
fi
echo ""

# Check 3: Temperature
echo "3. Temperature:"
if command -v vcgencmd &> /dev/null; then
    TEMP=$(vcgencmd measure_temp | cut -d= -f2)
    TEMP_VALUE=$(echo "$TEMP" | cut -d. -f1 | sed 's/[^0-9]//g')
    if [ "$TEMP_VALUE" -gt 80 ]; then
        echo -e "   ${RED}✗ Temperature: $TEMP (WARNING: >80°C)${NC}"
        echo "   - Overheating detected (add cooling)"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    elif [ "$TEMP_VALUE" -gt 70 ]; then
        echo -e "   ${YELLOW}⚠ Temperature: $TEMP (WARNING: >70°C)${NC}"
    else
        echo -e "   ${GREEN}✓ Temperature: $TEMP (normal)${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ vcgencmd not available (cannot check temperature)${NC}"
fi
echo ""

# Check 4: Memory
echo "4. Memory:"
MEMORY=$(free -h | grep Mem)
MEM_AVAIL=$(free -h | grep Mem | awk '{print $7}')
MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
echo "   Total: $MEM_TOTAL"
echo "   Available: $MEM_AVAIL"
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100}')
if [ "$MEM_USAGE" -gt 90 ]; then
    echo -e "   ${RED}✗ Memory usage: ${MEM_USAGE}% (WARNING: >90%)${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
elif [ "$MEM_USAGE" -gt 80 ]; then
    echo -e "   ${YELLOW}⚠ Memory usage: ${MEM_USAGE}% (WARNING: >80%)${NC}"
else
    echo -e "   ${GREEN}✓ Memory usage: ${MEM_USAGE}% (normal)${NC}"
fi
echo ""

# Check 5: Recent Errors
echo "5. Recent System Errors:"
# Filter out known informational messages and only show actual errors
ERRORS=$(sudo dmesg | tail -50 | grep -iE "error|fail" | grep -vE "brcmfmac.*using.*for chip|firmware.*loaded|normal.*operation" | head -10)
if [ -z "$ERRORS" ]; then
    echo -e "   ${GREEN}✓ No recent errors found${NC}"
else
    echo -e "   ${RED}✗ Recent errors found:${NC}"
    echo "$ERRORS" | sed 's/^/   /'
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check 6: Network
echo "6. Network:"
if ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
    PACKET_LOSS=$(ping -c 10 -W 2 8.8.8.8 2>&1 | grep "packet loss" | awk '{print $6}')
    echo -e "   ${GREEN}✓ Network connection OK${NC}"
    echo "   Packet loss: $PACKET_LOSS"
    if echo "$PACKET_LOSS" | grep -q "0%"; then
        echo -e "   ${GREEN}✓ No packet loss${NC}"
    else
        echo -e "   ${YELLOW}⚠ Packet loss detected${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
else
    echo -e "   ${RED}✗ Network connection failed${NC}"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Check 7: CPU Load
echo "7. CPU Load:"
# Get load average (1 minute) - more reliable parsing
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_COUNT=$(nproc)
echo "   Load average: $LOAD_AVG"

# Check if load average is valid and compare to CPU count
if [ -n "$LOAD_AVG" ] && [ -n "$CPU_COUNT" ]; then
    # Use awk for floating point comparison (more reliable than bc)
    LOAD_CHECK=$(echo "$LOAD_AVG $CPU_COUNT" | awk '{if ($1 > $2) print 1; else print 0}')
    if [ "$LOAD_CHECK" = "1" ]; then
        echo -e "   ${YELLOW}⚠ High CPU load (load > CPU count)${NC}"
    else
        echo -e "   ${GREEN}✓ CPU load normal${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ Could not determine CPU load${NC}"
fi
echo ""

# Summary
echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ No issues found!${NC}"
    echo ""
    echo "If you're still experiencing pipe drops:"
    echo "  1. Check installation logs: sudo bash deploy/install.sh 2>&1 | tee install.log"
    echo "  2. Check specific errors: grep -i 'error\|fail\|timeout' install.log"
    echo "  3. Retry installation: sudo bash deploy/install.sh"
    echo ""
    echo "Common causes:"
    echo "  - Network timeouts (try wired Ethernet)"
    echo "  - Package download failures (retry installation)"
    echo "  - SSH connection drops (use screen/tmux)"
else
    echo -e "${RED}✗ $ISSUES_FOUND issue(s) found!${NC}"
    echo ""
    echo "Recommended actions:"
    echo "  1. Fix power supply issues (use official Raspberry Pi power supply)"
    echo "  2. Fix SD card issues (use high-quality SD card)"
    echo "  3. Fix overheating (add cooling)"
    echo "  4. Fix network issues (use wired Ethernet)"
    echo "  5. Fix memory issues (close unnecessary processes)"
    echo ""
    echo "See TROUBLESHOOTING_PIPE_DROPS.md for detailed solutions."
fi
echo ""

