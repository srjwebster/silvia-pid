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

# Load I2C kernel modules
if ! lsmod | grep -q i2c_dev; then
    modprobe i2c-dev
    echo "i2c-dev" >> /etc/modules
    echo "I2C kernel module loaded"
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
echo "Step 6: Installing Node.js and npm (for validation scripts)..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
else
    echo "Node.js already installed: $(node --version)"
fi

echo ""
echo "Step 7: Installing Python dependencies..."
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
    
    # Enable and start pigpiod daemon
    systemctl daemon-reload
    systemctl enable pigpiod
    systemctl start pigpiod
    
    # Clean up
    cd /
    rm -rf /tmp/pigpio-79 /tmp/v79.tar.gz
    
    echo "pigpio installed and pigpiod daemon started"
else
    echo "pigpio already installed"
    # Make sure daemon is enabled and running
    systemctl enable pigpiod 2>/dev/null || true
    systemctl start pigpiod 2>/dev/null || true
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
echo "Step 9: Installing npm dependencies..."
cd "$INSTALL_DIR"
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" npm install
else
    npm install
fi

echo ""
echo "Step 10: Running hardware validation..."
echo "This will test the thermocouple and GPIO..."
cd "$INSTALL_DIR"
if [ -n "$SUDO_USER" ]; then
    sudo -u "$SUDO_USER" node scripts/validate-hardware.js || true
else
    node scripts/validate-hardware.js || true
fi

echo ""
echo "Step 11: Setting up systemd service..."
cp "$INSTALL_DIR/deploy/silvia-pid.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable silvia-pid.service

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Next steps:"
echo "1. Review and adjust /opt/silvia-pid/config.json for your PID settings"
echo "2. If using SSL, copy your certificates and update /opt/silvia-pid/.env"
echo "3. Reboot the system: sudo reboot"
echo "4. After reboot, start the service: sudo systemctl start silvia-pid"
echo "5. Check status: sudo systemctl status silvia-pid"
echo "6. View logs: sudo journalctl -u silvia-pid -f"
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

