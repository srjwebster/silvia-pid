#!/bin/bash
# Helper functions for installation script with retry logic

# Retry a command with exponential backoff
# Usage: retry_command <command> <max_attempts> <delay>
retry_command() {
    local command="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: $command"
        
        if eval "$command"; then
            echo "✓ Command succeeded"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                echo "✗ Command failed, retrying in ${delay} seconds..."
                sleep $delay
                delay=$((delay * 2))  # Exponential backoff
            else
                echo "✗ Command failed after $max_attempts attempts"
                return 1
            fi
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Retry apt-get update
apt_get_update_with_retry() {
    retry_command "apt-get update" 3 5
}

# Retry apt-get install
apt_get_install_with_retry() {
    local package="$1"
    retry_command "apt-get install -y $package" 3 5
}

# Retry curl download
curl_with_retry() {
    local url="$1"
    local output="$2"
    local max_attempts="${3:-3}"
    local delay="${4:-5}"
    
    retry_command "curl -fsSL $url -o $output" $max_attempts $delay
}

# Retry wget download
wget_with_retry() {
    local url="$1"
    local max_attempts="${3:-3}"
    local delay="${4:-5}"
    
    retry_command "wget -q $url" $max_attempts $delay
}

# Check network connectivity
check_network() {
    if ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo "✓ Network connectivity OK"
        return 0
    else
        echo "✗ Network connectivity failed"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    local required_gb="${1:-2}"
    local available_gb=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [ "$available_gb" -lt "$required_gb" ]; then
        echo "✗ Insufficient disk space: ${available_gb}GB available, ${required_gb}GB required"
        return 1
    else
        echo "✓ Disk space OK: ${available_gb}GB available"
        return 0
    fi
}

# Check power supply
check_power_supply() {
    if command -v vcgencmd &> /dev/null; then
        local throttled=$(vcgencmd get_throttled | cut -d= -f2)
        if [ "$throttled" != "0x0" ]; then
            echo "✗ Power supply issues detected: $throttled"
            echo "  - Use official Raspberry Pi power supply (5V, 3A)"
            echo "  - Check USB cable quality"
            return 1
        else
            echo "✓ Power supply OK"
            return 0
        fi
    else
        echo "⚠ vcgencmd not available (cannot check power supply)"
        return 0
    fi
}

# Check temperature
check_temperature() {
    if command -v vcgencmd &> /dev/null; then
        local temp=$(vcgencmd measure_temp | cut -d= -f2)
        local temp_value=$(echo "$temp" | cut -d. -f1 | sed 's/[^0-9]//g')
        
        if [ "$temp_value" -gt 80 ]; then
            echo "✗ Temperature too high: $temp (>80°C)"
            echo "  - Add cooling (heatsinks, fan)"
            echo "  - Improve ventilation"
            return 1
        elif [ "$temp_value" -gt 70 ]; then
            echo "⚠ Temperature high: $temp (>70°C)"
            return 0
        else
            echo "✓ Temperature OK: $temp"
            return 0
        fi
    else
        echo "⚠ vcgencmd not available (cannot check temperature)"
        return 0
    fi
}

# Pre-flight checks
preflight_checks() {
    echo "=========================================="
    echo "Pre-flight Checks"
    echo "=========================================="
    echo ""
    
    local checks_passed=0
    local checks_failed=0
    
    # Check network
    echo "1. Checking network connectivity..."
    if check_network; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
        echo "   WARNING: Network connectivity failed - installation may fail"
    fi
    echo ""
    
    # Check disk space
    echo "2. Checking disk space..."
    if check_disk_space 2; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
        echo "   ERROR: Insufficient disk space - installation will fail"
    fi
    echo ""
    
    # Check power supply
    echo "3. Checking power supply..."
    if check_power_supply; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
        echo "   WARNING: Power supply issues detected - installation may fail"
    fi
    echo ""
    
    # Check temperature
    echo "4. Checking temperature..."
    if check_temperature; then
        checks_passed=$((checks_passed + 1))
    else
        checks_failed=$((checks_failed + 1))
        echo "   WARNING: Temperature too high - installation may fail"
    fi
    echo ""
    
    # Summary
    echo "=========================================="
    echo "Pre-flight Check Summary"
    echo "=========================================="
    echo "Passed: $checks_passed"
    echo "Failed: $checks_failed"
    echo ""
    
    if [ $checks_failed -gt 0 ]; then
        echo "WARNING: $checks_failed check(s) failed!"
        echo "Installation may fail or be unstable."
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 1
        fi
    else
        echo "✓ All pre-flight checks passed!"
    fi
    echo ""
}

