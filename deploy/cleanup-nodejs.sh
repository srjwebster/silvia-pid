#!/bin/bash
# Cleanup script to remove Node.js 18 and related packages from Raspberry Pi
# Run this if you have Node.js 18 installed and want to remove it

set -e

echo "=========================================="
echo "Node.js 18 Cleanup Script"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

echo "This script will:"
echo "  1. Remove Node.js and npm packages"
echo "  2. Remove NodeSource repository (if added for Node.js 18)"
echo "  3. Clean up apt cache"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

echo ""
echo "Step 1: Checking current Node.js installation..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo "  Current Node.js version: $NODE_VERSION"
else
    echo "  Node.js not found in PATH"
fi

echo ""
echo "Step 2: Removing Node.js and npm packages..."
# Remove Node.js packages (multiple methods to catch all)
apt-get remove -y nodejs npm 2>/dev/null || true
apt-get purge -y nodejs npm 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

echo ""
echo "Step 3: Removing NodeSource repository (if present)..."
# Check for NodeSource repository
if [ -f /etc/apt/sources.list.d/nodesource.list ]; then
    echo "  Found NodeSource repository - removing..."
    rm -f /etc/apt/sources.list.d/nodesource.list
    echo "  NodeSource repository removed"
else
    echo "  No NodeSource repository found"
fi

# Also check for nodesource in sources.list.d with different names
find /etc/apt/sources.list.d/ -name "*nodesource*" -type f -delete 2>/dev/null || true

echo ""
echo "Step 4: Removing NodeSource GPG key (if present)..."
# Remove NodeSource GPG key
if [ -f /etc/apt/trusted.gpg.d/nodesource.gpg ]; then
    echo "  Found NodeSource GPG key - removing..."
    rm -f /etc/apt/trusted.gpg.d/nodesource.gpg
    echo "  NodeSource GPG key removed"
fi

# Also check in trusted.gpg.d for any nodesource keys
find /etc/apt/trusted.gpg.d/ -name "*nodesource*" -type f -delete 2>/dev/null || true

echo ""
echo "Step 5: Cleaning up apt cache..."
apt-get update

echo ""
echo "Step 6: Verifying Node.js removal..."
if command -v node &> /dev/null; then
    echo "  ⚠️  WARNING: Node.js still found: $(node --version)"
    echo "  This might be installed via a different method (snap, nvm, etc.)"
    echo "  Check: which node"
    echo "  Location: $(which node)"
else
    echo "  ✓ Node.js successfully removed"
fi

if command -v npm &> /dev/null; then
    echo "  ⚠️  WARNING: npm still found: $(npm --version)"
    echo "  This might be installed separately"
    echo "  Check: which npm"
    echo "  Location: $(which npm)"
else
    echo "  ✓ npm successfully removed"
fi

echo ""
echo "Step 7: Checking for remaining Node.js files..."
# Check for common Node.js installation locations
NODE_FILES_FOUND=0

if [ -d /usr/lib/node_modules ]; then
    echo "  ⚠️  Found: /usr/lib/node_modules"
    NODE_FILES_FOUND=1
fi

if [ -d /usr/local/lib/node_modules ]; then
    echo "  ⚠️  Found: /usr/local/lib/node_modules"
    NODE_FILES_FOUND=1
fi

if [ -d ~/.npm ]; then
    echo "  ⚠️  Found: ~/.npm (user npm cache)"
    NODE_FILES_FOUND=1
fi

if [ $NODE_FILES_FOUND -eq 0 ]; then
    echo "  ✓ No Node.js files found in common locations"
else
    echo "  Note: Some Node.js files may remain in these directories"
    echo "  You can manually remove them if needed"
fi

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "Node.js 18 has been removed from your system."
echo ""
echo "Note: Your application runs in Docker containers,"
echo "      so Node.js is not needed on the host OS."
echo ""
echo "If you see warnings above, Node.js might be installed via:"
echo "  - snap: sudo snap remove node"
echo "  - nvm: nvm uninstall 18"
echo "  - Manual installation: check installation location"
echo ""

