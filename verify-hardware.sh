#!/bin/bash
# Quick Hardware Verification Script
# Run this after connecting hardware to verify everything works

set -e

echo "=========================================="
echo "Silvia PID Hardware Verification"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# Check 1: I2C enabled in config.txt
echo "1. Checking I2C configuration..."
I2C_CONFIG_FILE=""
if [ -f /boot/firmware/config.txt ]; then
    I2C_CONFIG_FILE="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    I2C_CONFIG_FILE="/boot/config.txt"
fi

if [ -n "$I2C_CONFIG_FILE" ] && grep -q "^dtparam=i2c_arm=on" "$I2C_CONFIG_FILE" 2>/dev/null; then
    print_status 0 "I2C enabled in $I2C_CONFIG_FILE"
else
    print_status 1 "I2C NOT enabled in config.txt"
    echo "   Fix: Add 'dtparam=i2c_arm=on' to $I2C_CONFIG_FILE and reboot"
    echo "   Or run: sudo raspi-config → Interface Options → I2C → Enable"
fi

# Check 2: I2C hardware module loaded
echo ""
echo "2. Checking I2C hardware module..."
PI_MODEL="unknown"
if [ -f /proc/device-tree/model ]; then
    PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "unknown")
fi

I2C_HW_MODULE=""
if echo "$PI_MODEL" | grep -qi "Raspberry Pi 5\|Raspberry Pi 4"; then
    I2C_HW_MODULE="i2c-bcm2711"
elif echo "$PI_MODEL" | grep -qi "Raspberry Pi 3\|Raspberry Pi Zero"; then
    I2C_HW_MODULE="i2c-bcm2835"
else
    # Try to auto-detect
    if lsmod | grep -q "i2c-bcm2711"; then
        I2C_HW_MODULE="i2c-bcm2711"
    elif lsmod | grep -q "i2c-bcm2835"; then
        I2C_HW_MODULE="i2c-bcm2835"
    fi
fi

if [ -n "$I2C_HW_MODULE" ]; then
    # Convert module name to use underscores for lsmod check (lsmod shows underscores)
    I2C_HW_MODULE_CHECK=$(echo "$I2C_HW_MODULE" | tr '-' '_')
    if lsmod | grep -q "^${I2C_HW_MODULE_CHECK} "; then
        print_status 0 "I2C hardware module $I2C_HW_MODULE loaded"
    else
        # Also check with hyphens (some systems may show both)
        if lsmod | grep -q "^${I2C_HW_MODULE} "; then
            print_status 0 "I2C hardware module $I2C_HW_MODULE loaded"
        else
            print_status 1 "I2C hardware module $I2C_HW_MODULE NOT loaded"
            echo "   Fix: sudo modprobe $I2C_HW_MODULE"
            echo "   Or run: sudo bash scripts/diagnose-i2c.sh"
        fi
    fi
else
    # Check for any I2C BCM module (with underscores or hyphens)
    if lsmod | grep -q "i2c_bcm\|i2c-bcm"; then
        print_status 0 "I2C hardware module loaded"
    else
        print_status 1 "I2C hardware module NOT loaded"
        echo "   Fix: sudo modprobe i2c-bcm2711 (Pi 4/5) or i2c-bcm2835 (Pi 3)"
        echo "   Or run: sudo bash scripts/diagnose-i2c.sh"
    fi
fi

# Check 3: I2C device module loaded
echo ""
echo "3. Checking I2C device module..."
if lsmod | grep -q "^i2c_dev"; then
    print_status 0 "I2C device module i2c-dev loaded"
else
    print_status 1 "I2C device module i2c-dev NOT loaded"
    echo "   Fix: sudo modprobe i2c-dev"
    echo "   Or run: sudo bash scripts/diagnose-i2c.sh"
fi

# Check 4: I2C device exists
echo ""
echo "4. Checking I2C device..."
if [ -e /dev/i2c-1 ]; then
    print_status 0 "I2C device /dev/i2c-1 exists"
    ls -l /dev/i2c-1 | awk '{print "   " $0}'
else
    print_status 1 "I2C device /dev/i2c-1 NOT found"
    echo "   Possible fixes:"
    echo "   1. Load I2C modules: sudo modprobe $I2C_HW_MODULE i2c-dev"
    echo "   2. Run diagnostic: sudo bash scripts/diagnose-i2c.sh"
    echo "   3. Reboot if I2C was just enabled in config.txt"
    echo "   4. Check I2C is enabled: sudo raspi-config → Interface Options → I2C"
fi

# Check 5: MCP9600 detected
echo ""
echo "5. Scanning I2C bus for MCP9600..."
if command -v i2cdetect &> /dev/null; then
    if [ -e /dev/i2c-1 ]; then
        I2C_OUTPUT=$(sudo i2cdetect -y 1 2>&1)
        if echo "$I2C_OUTPUT" | grep -q "60"; then
            print_status 0 "MCP9600 detected at address 0x60"
        else
            print_status 1 "MCP9600 NOT detected at address 0x60"
            echo "   Run: sudo i2cdetect -y 1"
            echo "   Check wiring: VCC→3.3V, GND→Ground, SDA→GPIO2, SCL→GPIO3"
            echo "   If device not found, check I2C modules are loaded (checks 2-3 above)"
        fi
    else
        print_status 1 "Cannot scan - /dev/i2c-1 not found"
        echo "   Fix I2C device issue first (see checks 2-4 above)"
    fi
else
    print_status 1 "i2c-tools not installed (run: sudo apt-get install i2c-tools)"
fi

# Check 6: Python script works
echo ""
echo "6. Testing temperature reading..."
if [ -f "temperature.py" ]; then
    TEMP=$(python3 temperature.py 2>&1)
    if [ $? -eq 0 ] && [[ "$TEMP" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        print_status 0 "Temperature reading: ${TEMP}°C"
        TEMP_VALUE=$(echo "$TEMP" | awk '{print int($1)}')
        if [ "$TEMP_VALUE" -ge 0 ] && [ "$TEMP_VALUE" -le 200 ]; then
            print_status 0 "Temperature in valid range (0-200°C)"
        else
            print_status 1 "Temperature out of valid range: ${TEMP}°C"
        fi
    else
        print_status 1 "Temperature reading failed: $TEMP"
        echo "   Check: pip3 install mcp9600 --break-system-packages"
    fi
else
    print_status 1 "temperature.py not found in current directory"
fi

# Check 7: pigpiod running
echo ""
echo "7. Checking pigpiod daemon..."
if systemctl is-active --quiet pigpiod; then
    print_status 0 "pigpiod daemon is running"
else
    print_status 1 "pigpiod daemon is NOT running (run: sudo systemctl start pigpiod)"
fi

# Check 8: GPIO accessible
echo ""
echo "8. Checking GPIO access..."
if [ -e /dev/gpiomem ]; then
    print_status 0 "GPIO device /dev/gpiomem exists"
    ls -l /dev/gpiomem | awk '{print "   " $0}'
else
    print_status 1 "GPIO device /dev/gpiomem NOT found"
fi

# Check 9: Docker containers running
echo ""
echo "9. Checking Docker containers..."
if command -v docker &> /dev/null; then
    if docker ps | grep -q silvia-pid; then
        print_status 0 "Silvia PID container is running"
    else
        print_status 1 "Silvia PID container is NOT running (run: sudo docker compose up -d)"
    fi
    
    if docker ps | grep -q mongodb; then
        print_status 0 "MongoDB container is running"
    else
        print_status 1 "MongoDB container is NOT running"
    fi
else
    print_status 1 "Docker not installed or not accessible"
fi

# Check 10: Temperature reading from Docker
echo ""
echo "10. Testing temperature reading from Docker container..."
if docker ps | grep -q silvia-pid; then
    DOCKER_TEMP=$(sudo docker compose exec -T silvia-pid python3 temperature.py 2>&1)
    if [ $? -eq 0 ] && [[ "$DOCKER_TEMP" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        print_status 0 "Docker temperature reading: ${DOCKER_TEMP}°C"
    else
        print_status 1 "Docker temperature reading failed: $DOCKER_TEMP"
        echo "   Check: I2C device mounted in docker-compose.yml"
        echo "   Check: Container has I2C permissions"
    fi
else
    print_status 1 "Cannot test - container not running"
fi

# Check 11: PID process logs
echo ""
echo "11. Checking PID process logs (last 5 lines)..."
if docker ps | grep -q silvia-pid; then
    LOGS=$(sudo docker compose logs --tail 5 silvia-pid 2>&1)
    if echo "$LOGS" | grep -q "Temp:"; then
        print_status 0 "PID process is reading temperatures"
        echo "$LOGS" | grep "Temp:" | tail -1 | sed 's/^/   /'
    else
        print_status 1 "PID process NOT reading temperatures"
        echo "   Check logs: sudo docker compose logs -f silvia-pid"
    fi
else
    print_status 1 "Cannot check - container not running"
fi

# Check 12: Web interface accessible
echo ""
echo "12. Testing web interface..."
if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health 2>&1 || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "503" ]; then
        print_status 0 "Web interface accessible (HTTP $HTTP_CODE)"
    else
        print_status 1 "Web interface NOT accessible (HTTP $HTTP_CODE)"
        echo "   Check: sudo docker compose logs silvia-pid"
    fi
else
    print_status 1 "curl not installed (cannot test web interface)"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo ""

if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All checks passed! Hardware is working correctly.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Check web UI: http://192.168.1.100"
    echo "  2. Test PID control: curl http://192.168.1.100/api/temp/set/100"
    echo "  3. Monitor logs: sudo docker compose logs -f silvia-pid"
    exit 0
else
    echo -e "${RED}$FAILURES check(s) failed.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Review failed checks above"
    echo "  2. See HARDWARE_VERIFICATION.md for detailed steps"
    echo "  3. Check logs: sudo docker compose logs -f silvia-pid"
    exit 1
fi

