#!/bin/bash
# Kill Stuck Docker Build/Pull Processes

set -e

echo "=========================================="
echo "Killing Stuck Docker Processes"
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

# Kill stuck Docker build/pull processes
echo "1. Finding stuck Docker processes..."
STUCK_PROCS=$(ps aux | grep -E "docker.*build|docker.*pull|docker.*compose" | grep -v grep || true)

if [ -n "$STUCK_PROCS" ]; then
    echo "   Found stuck processes:"
    echo "$STUCK_PROCS" | sed 's/^/   /'
    echo ""
    
    # Kill docker compose processes
    pkill -f "docker.*compose.*build" 2>/dev/null || true
    pkill -f "docker.*compose.*pull" 2>/dev/null || true
    pkill -f "docker.*build" 2>/dev/null || true
    pkill -f "docker.*pull" 2>/dev/null || true
    
    sleep 2
    echo -e "   ${GREEN}✓ Killed stuck Docker processes${NC}"
else
    echo -e "   ${GREEN}✓ No stuck Docker processes found${NC}"
fi
echo ""

# Restart Docker daemon to clear stuck connections
echo "2. Restarting Docker daemon..."
systemctl restart docker
sleep 3
echo -e "   ${GREEN}✓ Docker daemon restarted${NC}"
echo ""

# Clean up
echo "3. Cleaning up Docker..."
docker system prune -f 2>/dev/null || true
echo -e "   ${GREEN}✓ Docker cleanup complete${NC}"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Check network connectivity:"
echo "   ping -c 3 registry-1.docker.io"
echo ""
echo "2. Fix WiFi connection drops:"
echo "   sudo bash scripts/fix-wifi-drops.sh"
echo ""
echo "3. Retry build in screen (recommended):"
echo "   screen -S docker-build"
echo "   cd /opt/silvia-pid"
echo "   docker compose build --no-cache"
echo "   # Detach: Ctrl+A then D"
echo ""
echo "4. Or retry with increased timeout:"
echo "   DOCKER_CLIENT_TIMEOUT=600 docker compose build --no-cache"
echo ""

