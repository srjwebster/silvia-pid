#!/bin/bash
# Check Power Supply Status During Installation
# Returns 0 if OK, 1 if power issues detected

if ! command -v vcgencmd &> /dev/null; then
    # If vcgencmd not available, assume OK
    exit 0
fi

THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)

# 0x0 = no issues
# 0x50000 = historical undervoltage (OK now)
# Anything else = current power issue
if [ "$THROTTLED" = "0x0" ] || [ "$THROTTLED" = "0x50000" ]; then
    exit 0
else
    echo "WARNING: Power supply issue detected (throttled=$THROTTLED)"
    exit 1
fi

