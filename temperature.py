#!/usr/bin/env python3
import sys
import mcp9600

# Temperature validation constants
MIN_TEMP = 0.0
MAX_TEMP_READING = 200.0  # Maximum valid thermocouple reading

try:
    # Initialize MCP9600 thermocouple at I2C address 0x60
    adapter = mcp9600.TemperatureAdapter()
    sensor = mcp9600.MCP9600(0x60)
    
    # Read hot junction temperature
    temperature = sensor.get_hot_junction_temperature()
    
    # Validate temperature is within reasonable range for coffee machine
    if temperature < MIN_TEMP or temperature > MAX_TEMP_READING:
        print(f"ERROR: Temperature {temperature}°C out of valid range ({MIN_TEMP}-{MAX_TEMP_READING}°C)", file=sys.stderr)
        sys.exit(2)  # Exit code 2 = invalid temperature reading
    
    # Output temperature to stdout
    print(temperature)
    sys.exit(0)  # Success
    
except ImportError as e:
    print(f"ERROR: Failed to import mcp9600 library: {e}", file=sys.stderr)
    sys.exit(3)  # Exit code 3 = library import error
    
except Exception as e:
    print(f"ERROR: Failed to read temperature from MCP9600: {e}", file=sys.stderr)
    sys.exit(1)  # Exit code 1 = general I2C/sensor error