#!/bin/bash
# Fix Docker Build Timeout Issues
# Addresses stuck Docker builds and download timeouts

set -e

echo "=========================================="
echo "Docker Build Timeout Fix"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check 1: Docker daemon status
echo "1. Checking Docker daemon..."
if systemctl is-active --quiet docker; then
    echo -e "   ${GREEN}✓ Docker daemon is running${NC}"
else
    echo -e "   ${RED}✗ Docker daemon is NOT running${NC}"
    echo "   Starting Docker daemon..."
    systemctl start docker
    sleep 2
fi
echo ""

# Check 2: Restart Docker daemon (fixes stuck builds)
echo "2. Restarting Docker daemon (fixes stuck builds)..."
echo "   This will kill any stuck Docker processes"
read -p "   Restart Docker daemon? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl restart docker
    sleep 3
    echo -e "   ${GREEN}✓ Docker daemon restarted${NC}"
else
    echo -e "   ${YELLOW}⚠ Skipped Docker restart${NC}"
fi
echo ""

# Check 3: Clean up stuck builds
echo "3. Cleaning up Docker..."
echo "   Removing stopped containers..."
docker container prune -f 2>/dev/null || true
echo "   Removing dangling images..."
docker image prune -f 2>/dev/null || true
echo "   Removing build cache..."
docker builder prune -f 2>/dev/null || true
echo -e "   ${GREEN}✓ Docker cleanup complete${NC}"
echo ""

# Check 4: Configure Docker daemon for better timeout handling
echo "4. Configuring Docker daemon for better network handling..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
if [ ! -f "$DOCKER_DAEMON_JSON" ]; then
    cat > "$DOCKER_DAEMON_JSON" << 'EOF'
{
  "max-concurrent-downloads": 3,
  "max-concurrent-uploads": 5,
  "default-ulimits": {},
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    echo -e "   ${GREEN}✓ Docker daemon.json created${NC}"
    echo "   Restarting Docker to apply changes..."
    systemctl restart docker
    sleep 3
else
    echo -e "   ${YELLOW}⚠ Docker daemon.json already exists${NC}"
    echo "   Current configuration:"
    cat "$DOCKER_DAEMON_JSON" | sed 's/^/     /'
fi
echo ""

# Check 5: Test Docker registry connectivity
echo "5. Testing Docker registry connectivity..."
if ping -c 3 -W 2 registry-1.docker.io > /dev/null 2>&1; then
    echo -e "   ${GREEN}✓ Docker registry is reachable${NC}"
else
    echo -e "   ${RED}✗ Docker registry is NOT reachable${NC}"
    echo "   Check network connection"
fi
echo ""

# Check 6: Check for stuck Docker processes
echo "6. Checking for stuck Docker processes..."
STUCK_PROCS=$(ps aux | grep -E "docker.*build|docker.*pull" | grep -v grep || true)
if [ -n "$STUCK_PROCS" ]; then
    echo -e "   ${YELLOW}⚠ Stuck Docker processes found:${NC}"
    echo "$STUCK_PROCS" | sed 's/^/     /'
    echo ""
    read -p "   Kill stuck processes? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pkill -f "docker.*build" || true
        pkill -f "docker.*pull" || true
        echo -e "   ${GREEN}✓ Stuck processes killed${NC}"
    fi
else
    echo -e "   ${GREEN}✓ No stuck Docker processes${NC}"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary and Recommendations"
echo "=========================================="
echo ""

echo "If Docker builds are still timing out:"
echo ""
echo "1. Use screen/tmux to prevent connection drops:"
echo "   screen -S docker-build"
echo "   docker compose build --no-cache"
echo "   # Detach: Ctrl+A then D"
echo ""
echo "2. Retry with increased timeout:"
echo "   DOCKER_CLIENT_TIMEOUT=600 docker compose build --no-cache"
echo ""
echo "3. Build without cache (if layer is corrupted):"
echo "   docker compose build --no-cache --pull"
echo ""
echo "4. Pull images manually first:"
echo "   docker compose pull"
echo "   docker compose build"
echo ""
echo "5. Use Docker registry mirror (if Docker Hub is slow):"
echo "   # Add to /etc/docker/daemon.json:"
echo "   {"
echo "     \"registry-mirrors\": [\"https://mirror.gcr.io\"]"
echo "   }"
echo ""
echo "6. Check network stability:"
echo "   sudo bash scripts/diagnose-connection-drops.sh"
echo ""
echo "7. Fix WiFi drops (if using WiFi):"
echo "   sudo bash scripts/fix-wifi-drops.sh"
echo ""

