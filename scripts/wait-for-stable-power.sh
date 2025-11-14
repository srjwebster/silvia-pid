#!/bin/bash
# Wait for stable power supply before proceeding with installation
# Checks power status and waits if issues detected

if ! command -v vcgencmd &> /dev/null; then
    echo "⚠ vcgencmd not available, skipping power check"
    exit 0
fi

MAX_WAIT=300  # Maximum wait time in seconds (5 minutes)
CHECK_INTERVAL=5  # Check every 5 seconds
WAITED=0

echo "Checking power supply status..."

while [ $WAITED -lt $MAX_WAIT ]; do
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    
    # 0x0 = no issues
    # 0x50000 = historical undervoltage (OK now)
    if [ "$THROTTLED" = "0x0" ] || [ "$THROTTLED" = "0x50000" ]; then
        echo "✓ Power supply OK (throttled=$THROTTLED)"
        exit 0
    fi
    
    # Current power issue detected
    echo "⚠ Power supply issue detected (throttled=$THROTTLED), waiting..."
    echo "   Fix: Use official Raspberry Pi power supply (5V, 2.5A+)"
    echo "   Waiting ${CHECK_INTERVAL}s before retry... (${WAITED}/${MAX_WAIT}s elapsed)"
    
    sleep $CHECK_INTERVAL
    WAITED=$((WAITED + CHECK_INTERVAL))
done

echo "✗ Power supply still unstable after ${MAX_WAIT}s"
echo "   Please fix power supply before continuing installation"
exit 1

