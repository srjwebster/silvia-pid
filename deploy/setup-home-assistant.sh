#!/bin/bash
# Home Assistant Setup Script for Silvia PID Google Assistant Integration
# This script installs Home Assistant in Docker and configures it for Google Assistant

set -e

COFFEE_URL="https://coffee.srjwebster.com"
HA_DIR="/opt/homeassistant"

echo "============================================"
echo "Home Assistant Setup for Silvia PID"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    echo "Please install Docker first: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

echo "Step 1: Creating Home Assistant directory..."
mkdir -p "$HA_DIR"
chmod 755 "$HA_DIR"

echo "Step 2: Creating Home Assistant configuration..."
cat > "$HA_DIR/configuration.yaml" << EOF
# Home Assistant Configuration for Silvia PID
# https://coffee.srjwebster.com

# REST Commands for Silvia PID
rest_command:
  silvia_espresso:
    url: "${COFFEE_URL}/api/mode/espresso"
    method: GET
    verify_ssl: true
  
  silvia_steam:
    url: "${COFFEE_URL}/api/mode/steam/180"  # 3 minutes default
    method: GET
    verify_ssl: true
  
  silvia_steam_short:
    url: "${COFFEE_URL}/api/mode/steam/120"  # 2 minutes
    method: GET
    verify_ssl: true
  
  silvia_off:
    url: "${COFFEE_URL}/api/mode/off"
    method: GET
    verify_ssl: true

# Template Switches (exposed to Google Assistant)
switch:
  - platform: template
    switches:
      silvia_espresso_mode:
        friendly_name: "Coffee Machine - Espresso"
        value_template: "{{ states('sensor.silvia_mode') == 'espresso' }}"
        turn_on:
          service: rest_command.silvia_espresso
        turn_off:
          service: rest_command.silvia_off
        icon_template: mdi:coffee
        
      silvia_steam_mode:
        friendly_name: "Coffee Machine - Steam"
        value_template: "{{ states('sensor.silvia_mode') == 'steam' }}"
        turn_on:
          service: rest_command.silvia_steam
        turn_off:
          service: rest_command.silvia_espresso
        icon_template: mdi:kettle-steam

# Sensors for status
sensor:
  - platform: rest
    name: "Silvia Mode"
    resource: "${COFFEE_URL}/api/mode"
    method: GET
    verify_ssl: true
    value_template: "{{ value_json.mode }}"
    scan_interval: 10
    json_attributes:
      - target_temperature
      - steam_time_remaining
  
  - platform: rest
    name: "Silvia Temperature"
    resource: "${COFFEE_URL}/api/mode"
    method: GET
    verify_ssl: true
    value_template: "{{ value_json.target_temperature }}"
    unit_of_measurement: "°C"
    scan_interval: 10
EOF

echo "✓ Configuration created"

echo ""
echo "Step 3: Starting Home Assistant container..."
# Stop existing container if running
docker stop homeassistant 2>/dev/null || true
docker rm homeassistant 2>/dev/null || true

# Start Home Assistant
docker run -d \
  --name homeassistant \
  --privileged \
  --restart unless-stopped \
  -e TZ=America/New_York \
  -v "$HA_DIR:/config" \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable

echo "✓ Home Assistant container started"
echo ""
echo "Waiting for Home Assistant to initialize (this may take 2-3 minutes)..."
sleep 30

# Check if container is running
if docker ps | grep -q homeassistant; then
    echo "✓ Home Assistant is running"
else
    echo "⚠ Home Assistant container may have issues - check logs:"
    echo "  docker logs homeassistant"
fi

echo ""
echo "============================================"
echo "Home Assistant Setup Complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Access Home Assistant UI:"
echo "   http://$(hostname -I | awk '{print $1}'):8123"
echo ""
echo "2. Complete initial setup:"
echo "   - Create admin account"
echo "   - Set location"
echo "   - Finish onboarding"
echo ""
echo "3. Enable Google Assistant Integration:"
echo "   - Settings → Integrations → Add 'Google Assistant'"
echo "   - Choose: Home Assistant Cloud ($5/month) OR Manual Setup (free)"
echo ""
echo "4. Expose devices:"
echo "   - In Google Assistant settings, enable:"
echo "     • silvia_espresso_mode"
echo "     • silvia_steam_mode"
echo ""
echo "5. Link to Google Home:"
echo "   - Open Google Home app"
echo "   - Add device → Works with Google"
echo "   - Search 'Home Assistant'"
echo ""
echo "6. Test voice commands:"
echo "   - 'Hey Google, turn on Coffee Machine Espresso'"
echo "   - 'Hey Google, turn on Coffee Machine Steam'"
echo ""
echo "Logs:"
echo "  docker logs -f homeassistant"
echo ""
echo "Configuration:"
echo "  $HA_DIR/configuration.yaml"
echo ""

