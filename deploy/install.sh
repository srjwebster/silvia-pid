#!/bin/bash
set -e

# Silvia PID Installation Script
# This script installs the Silvia PID controller with Docker Compose on Raspberry Pi

echo "=== Silvia PID Installation Script ==="
echo ""

# Check if running on Raspberry Pi
if [ ! -f /proc/device-tree/model ] || ! grep -q "Raspberry Pi" /proc/device-tree/model; then
    echo "WARNING: This doesn't appear to be a Raspberry Pi"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "Step 1: Updating system packages..."
apt-get update
apt-get upgrade -y

echo ""
echo "Step 2: Installing Docker..."
if ! command -v docker &> /dev/null; then
    # Install Docker using the official script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # Add current user to docker group (if not root)
    if [ -n "$SUDO_USER" ]; then
        usermod -aG docker "$SUDO_USER"
        echo "Added $SUDO_USER to docker group"
    fi
else
    echo "Docker already installed: $(docker --version)"
fi

echo ""
echo "Step 3: Installing Docker Compose..."
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    apt-get install -y docker-compose-plugin
else
    echo "Docker Compose already installed"
fi

# Detect Docker path (for use in later steps)
if command -v docker &> /dev/null; then
    DOCKER_CMD=$(command -v docker)
    echo "Docker found at: $DOCKER_CMD"
else
    # Fallback to standard location (official Docker script installs here)
    DOCKER_CMD="/usr/bin/docker"
    echo "Docker path not found in PATH, using default: $DOCKER_CMD"
fi

echo ""
echo "Step 4: Enabling I2C..."
# Enable I2C in /boot/config.txt if not already enabled
if ! grep -q "^dtparam=i2c_arm=on" /boot/firmware/config.txt 2>/dev/null && \
   ! grep -q "^dtparam=i2c_arm=on" /boot/config.txt 2>/dev/null; then
    echo "dtparam=i2c_arm=on" >> /boot/config.txt 2>/dev/null || \
    echo "dtparam=i2c_arm=on" >> /boot/firmware/config.txt 2>/dev/null
    echo "I2C enabled in config.txt"
    I2C_MODIFIED=1
else
    echo "I2C already enabled"
    I2C_MODIFIED=0
fi

# Detect Pi model to determine I2C hardware module
PI_MODEL="unknown"
if [ -f /proc/device-tree/model ]; then
    PI_MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "unknown")
fi

# Determine I2C hardware module based on Pi model
I2C_HW_MODULE=""
if echo "$PI_MODEL" | grep -qi "Raspberry Pi 5"; then
    I2C_HW_MODULE="i2c-bcm2711"
elif echo "$PI_MODEL" | grep -qi "Raspberry Pi 4"; then
    I2C_HW_MODULE="i2c-bcm2711"
elif echo "$PI_MODEL" | grep -qi "Raspberry Pi 3\|Raspberry Pi Zero"; then
    I2C_HW_MODULE="i2c-bcm2835"
else
    # Try to auto-detect by checking available modules
    if modinfo i2c-bcm2711 &>/dev/null; then
        I2C_HW_MODULE="i2c-bcm2711"
    elif modinfo i2c-bcm2835 &>/dev/null; then
        I2C_HW_MODULE="i2c-bcm2835"
    else
        echo "WARNING: Could not determine I2C hardware module for $PI_MODEL"
        echo "Will try common module names..."
    fi
fi

# Load I2C hardware module (required before i2c-dev)
if [ -n "$I2C_HW_MODULE" ]; then
    # Convert module name to use underscores for lsmod check (lsmod shows underscores)
    I2C_HW_MODULE_CHECK=$(echo "$I2C_HW_MODULE" | tr '-' '_')
    if ! lsmod | grep -q "^${I2C_HW_MODULE_CHECK} "; then
        # Also check with hyphens (some systems may show both)
        if ! lsmod | grep -q "^${I2C_HW_MODULE} "; then
            if modprobe "$I2C_HW_MODULE" 2>/dev/null; then
                echo "Loaded I2C hardware module: $I2C_HW_MODULE"
                # Add to /etc/modules if not already there
                if ! grep -q "^${I2C_HW_MODULE}" /etc/modules; then
                    echo "$I2C_HW_MODULE" >> /etc/modules
                fi
            else
                echo "WARNING: Failed to load $I2C_HW_MODULE (may require reboot)"
            fi
        else
            echo "I2C hardware module $I2C_HW_MODULE already loaded"
        fi
    else
        echo "I2C hardware module $I2C_HW_MODULE already loaded"
    fi
else
    # Try common module names if detection failed
    for module in i2c-bcm2711 i2c-bcm2835; do
        module_check=$(echo "$module" | tr '-' '_')
        if lsmod | grep -q "^${module_check} "; then
            echo "I2C hardware module $module already loaded"
            break
        elif modinfo "$module" &>/dev/null && modprobe "$module" 2>/dev/null; then
            echo "Loaded I2C hardware module: $module"
            if ! grep -q "^${module}" /etc/modules; then
                echo "$module" >> /etc/modules
            fi
            break
        fi
    done
fi

# Load I2C device module (required for /dev/i2c-*)
if ! lsmod | grep -q "^i2c_dev"; then
    if modprobe i2c-dev 2>/dev/null; then
        echo "Loaded I2C device module: i2c-dev"
        # Add to /etc/modules if not already there
        if ! grep -q "^i2c-dev" /etc/modules; then
            echo "i2c-dev" >> /etc/modules
        fi
    else
        echo "WARNING: Failed to load i2c-dev (may require reboot)"
    fi
else
    echo "I2C device module already loaded"
fi

# Wait a moment for device to appear
sleep 1

# Verify I2C device exists
if [ -e /dev/i2c-1 ]; then
    echo "✓ I2C device /dev/i2c-1 is available"
else
    echo "WARNING: I2C device /dev/i2c-1 not found"
    if [ "$I2C_MODIFIED" -eq 1 ]; then
        echo "This is expected if I2C was just enabled - reboot required"
    else
        echo "Try: sudo modprobe i2c-bcm2711 i2c-dev (or i2c-bcm2835 for Pi 3)"
        echo "Or run: sudo bash scripts/diagnose-i2c.sh"
    fi
fi

echo ""
echo "Step 5: Setting up GPIO and I2C permissions..."
# Ensure I2C and GPIO groups exist
groupadd -f i2c
groupadd -f gpio

# Add user to groups
if [ -n "$SUDO_USER" ]; then
    usermod -aG i2c,gpio "$SUDO_USER"
    echo "Added $SUDO_USER to i2c and gpio groups"
fi

# Set up udev rules for I2C and GPIO
cat > /etc/udev/rules.d/99-i2c.rules << 'EOF'
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
EOF

cat > /etc/udev/rules.d/99-gpio.rules << 'EOF'
SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c 'chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio; chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio'"
EOF

udevadm control --reload-rules
udevadm trigger

echo ""
echo "Step 6: Installing Python dependencies..."
apt-get install -y python3 python3-pip python3-smbus python3-setuptools python3-full i2c-tools
pip3 install --break-system-packages mcp9600 || pip3 install mcp9600

echo ""
echo "Step 7b: Installing pigpio from source (not available in Bookworm/Trixie repos)..."
if ! command -v pigpiod &> /dev/null; then
    cd /tmp
    wget https://github.com/joan2937/pigpio/archive/refs/tags/v79.tar.gz
    tar zxf v79.tar.gz
    cd pigpio-79
    make
    make install
    ldconfig
    
    # Verify pigpiod was installed correctly and find its path
    if [ -f /usr/local/bin/pigpiod ]; then
        PIGPIOD_PATH="/usr/local/bin/pigpiod"
        echo "✓ pigpiod installed to $PIGPIOD_PATH"
    elif command -v pigpiod &> /dev/null; then
        PIGPIOD_PATH=$(command -v pigpiod)
        echo "✓ pigpiod found at: $PIGPIOD_PATH"
    else
        echo "ERROR: pigpiod not found after installation"
        echo "Checking common locations..."
        find /usr -name pigpiod 2>/dev/null || echo "pigpiod not found in /usr"
        exit 1
    fi
    
    # Create systemd service file for pigpiod (not created automatically when compiled from source)
    # pigpio source doesn't include systemd service file, so we create it
    cat > /etc/systemd/system/pigpiod.service << EOF
[Unit]
Description=Daemon required to control GPIO pins via /dev/gpiomem
After=network.target

[Service]
Type=forking
ExecStart=$PIGPIOD_PATH
ExecStop=/bin/kill -s TERM \$MAINPID
PIDFile=/var/run/pigpiod.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    echo "Created pigpiod.service systemd unit with ExecStart=$PIGPIOD_PATH"
    
    # Reload systemd and enable/start pigpiod (following standard online guide approach)
    systemctl daemon-reload
    systemctl enable --now pigpiod
    
    # Clean up
    cd /
    rm -rf /tmp/pigpio-79 /tmp/v79.tar.gz
    
    echo "pigpio installed and pigpiod daemon started"
else
    echo "pigpio already installed"
    # Find pigpiod path
    if [ -f /usr/local/bin/pigpiod ]; then
        PIGPIOD_PATH="/usr/local/bin/pigpiod"
    elif command -v pigpiod &> /dev/null; then
        PIGPIOD_PATH=$(command -v pigpiod)
    else
        echo "WARNING: pigpiod not found in expected locations"
        PIGPIOD_PATH="/usr/local/bin/pigpiod"  # Default path
    fi
    echo "Using pigpiod path: $PIGPIOD_PATH"
    
    # Make sure service file exists (pigpio compiled from source doesn't create it)
    if [ ! -f /etc/systemd/system/pigpiod.service ]; then
        # Create service file with correct path
        cat > /etc/systemd/system/pigpiod.service << EOF
[Unit]
Description=Daemon required to control GPIO pins via /dev/gpiomem
After=network.target

[Service]
Type=forking
ExecStart=$PIGPIOD_PATH
ExecStop=/bin/kill -s TERM \$MAINPID
PIDFile=/var/run/pigpiod.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        echo "Created pigpiod.service systemd unit with ExecStart=$PIGPIOD_PATH"
        systemctl daemon-reload
    else
        # Verify service file has correct path (update if needed)
        if ! grep -q "ExecStart=$PIGPIOD_PATH" /etc/systemd/system/pigpiod.service 2>/dev/null; then
            echo "Updating pigpiod.service to use correct path: $PIGPIOD_PATH"
            sed -i "s|ExecStart=.*|ExecStart=$PIGPIOD_PATH|" /etc/systemd/system/pigpiod.service
            systemctl daemon-reload
        fi
    fi
    # Make sure daemon is enabled and running (using --now flag like online guides)
    systemctl enable --now pigpiod 2>/dev/null || true
fi

echo ""
echo "Step 8: Setting up application directory..."
INSTALL_DIR="/opt/silvia-pid"
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists"
    read -p "Remove and reinstall? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$INSTALL_DIR"
    else
        echo "Keeping existing installation"
        INSTALL_DIR="${INSTALL_DIR}_new"
        echo "Installing to $INSTALL_DIR instead"
    fi
fi

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Copy application files
mkdir -p "$INSTALL_DIR"
cp -r "$PROJECT_DIR"/* "$INSTALL_DIR/" 2>/dev/null || true

# Set ownership
if [ -n "$SUDO_USER" ]; then
    chown -R "$SUDO_USER":"$SUDO_USER" "$INSTALL_DIR"
fi

echo ""
echo "Step 9: Building Docker images and starting services..."
cd "$INSTALL_DIR"
"$DOCKER_CMD" compose build --no-cache
"$DOCKER_CMD" compose up -d

echo ""
echo "Step 10: Setting up systemd service..."
cp "$INSTALL_DIR/deploy/silvia-pid.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable silvia-pid.service

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Note: All application code runs inside Docker containers - no Node.js needed on host OS"
echo ""
echo "Next steps:"
echo "1. Review and adjust /opt/silvia-pid/config.json for your PID settings"
echo "2. If using SSL, copy your certificates and update /opt/silvia-pid/.env"
echo "3. Reboot the system: sudo reboot"
echo "4. After reboot, start the service: sudo systemctl start silvia-pid"
echo "5. Check status: sudo systemctl status silvia-pid"
echo "6. View logs: sudo docker compose -f /opt/silvia-pid/docker-compose.yml logs -f"
echo "7. Verify hardware (optional): See HARDWARE_VERIFICATION.md for testing steps"
echo ""
echo "Tip: If experiencing connection drops during installation, use screen or tmux:"
echo "  screen -S install    # Start screen session"
echo "  sudo bash deploy/install.sh"
echo "  # Press Ctrl+A then D to detach (process continues in background)"
echo "  # Reattach: screen -r install"
echo ""

if [ "$I2C_MODIFIED" -eq 1 ]; then
    echo "IMPORTANT: I2C was just enabled. You MUST reboot before starting the service."
    echo ""
    read -p "Reboot now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
fi

echo "Installation script finished successfully!"

