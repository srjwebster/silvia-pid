# Remove Node.js 18 from Raspberry Pi

Since your application runs entirely in Docker containers, Node.js is not needed on the host OS. Here's how to remove it.

## Quick Method: Automated Script

```bash
# Transfer cleanup script to Pi
cd /home/sam/Code/silvia-pid
rsync -avz deploy/cleanup-nodejs.sh pi@192.168.1.100:~/cleanup-nodejs.sh

# SSH to Pi
ssh pi@192.168.1.100

# Run cleanup script
chmod +x cleanup-nodejs.sh
sudo bash cleanup-nodejs.sh
```

The script will:
- ✅ Remove Node.js and npm packages
- ✅ Remove NodeSource repository
- ✅ Remove NodeSource GPG keys
- ✅ Clean up apt cache
- ✅ Verify removal

---

## Manual Method: Step-by-Step

If you prefer to do it manually or the script doesn't catch everything:

### Step 1: Check Current Installation

```bash
# Check Node.js version
node --version

# Check npm version
npm --version

# Check where Node.js is installed
which node
which npm

# Check if installed via apt
dpkg -l | grep nodejs
dpkg -l | grep npm
```

### Step 2: Remove Node.js Packages

```bash
# Remove Node.js and npm
sudo apt-get remove -y nodejs npm
sudo apt-get purge -y nodejs npm
sudo apt-get autoremove -y
```

### Step 3: Remove NodeSource Repository

```bash
# Remove NodeSource repository file
sudo rm -f /etc/apt/sources.list.d/nodesource.list

# Also check for other NodeSource files
sudo find /etc/apt/sources.list.d/ -name "*nodesource*" -type f -delete

# Update apt cache
sudo apt-get update
```

### Step 4: Remove NodeSource GPG Key

```bash
# Remove NodeSource GPG key
sudo rm -f /etc/apt/trusted.gpg.d/nodesource.gpg

# Also check for other NodeSource keys
sudo find /etc/apt/trusted.gpg.d/ -name "*nodesource*" -type f -delete
```

### Step 5: Verify Removal

```bash
# Check if Node.js is still installed
node --version
# Should show: command not found

npm --version
# Should show: command not found

# Check apt packages
dpkg -l | grep nodejs
# Should show: nothing

dpkg -l | grep npm
# Should show: nothing
```

---

## Additional Cleanup (If Needed)

### Remove Node.js Files

```bash
# Remove Node.js modules (if still present)
sudo rm -rf /usr/lib/node_modules
sudo rm -rf /usr/local/lib/node_modules

# Remove npm cache (if present)
rm -rf ~/.npm

# Remove global npm packages
sudo rm -rf /usr/local/lib/node_modules
sudo rm -rf /usr/lib/node_modules
```

### Remove if Installed via Snap

```bash
# Check if installed via snap
snap list | grep node

# Remove if found
sudo snap remove node
```

### Remove if Installed via NVM

```bash
# Check if nvm is installed
nvm list

# Remove Node.js 18 if using nvm
nvm uninstall 18

# Remove nvm entirely (if desired)
rm -rf ~/.nvm
```

### Remove if Installed via Binary

```bash
# Check common binary locations
ls -la /usr/local/bin/node
ls -la /usr/bin/node

# Remove if found
sudo rm -f /usr/local/bin/node
sudo rm -f /usr/local/bin/npm
sudo rm -f /usr/bin/node
sudo rm -f /usr/bin/npm
```

---

## After Cleanup

### Verify Docker is Working

Since your application runs in Docker, verify Docker is working:

```bash
# Check Docker version
docker --version

# Check Docker Compose
docker compose version

# Test Docker
sudo docker run hello-world
```

### Verify Application Runs in Docker

```bash
# Check Docker containers
cd /opt/silvia-pid
sudo docker compose ps

# Check logs
sudo docker compose logs silvia-pid

# All application code runs inside containers!
```

---

## Why Remove Node.js from Host?

✅ **Your application runs in Docker** - All Node.js code runs inside containers  
✅ **No need for host Node.js** - Docker image contains Node.js 24  
✅ **Cleaner system** - Less packages, less maintenance  
✅ **No conflicts** - Avoid version conflicts between host and container  

---

## Troubleshooting

### Node.js Still Found After Removal

**Check installation method:**
```bash
# Check all possible locations
which node
type node
command -v node

# Check for snap
snap list | grep node

# Check for nvm
nvm list

# Check PATH
echo $PATH
```

**Remove based on installation method:**
- **apt:** Already removed above
- **snap:** `sudo snap remove node`
- **nvm:** `nvm uninstall 18`
- **binary:** Remove from `/usr/local/bin/` or `/usr/bin/`
- **manual:** Check installation location and remove

### npm Still Found

```bash
# Check npm location
which npm
type npm

# Remove based on location
sudo rm -f $(which npm)

# Or if in PATH
sudo rm -f /usr/local/bin/npm
sudo rm -f /usr/bin/npm
```

### NodeSource Repository Still Present

```bash
# Check all sources
cat /etc/apt/sources.list.d/*.list | grep nodesource

# Remove all NodeSource files
sudo find /etc/apt/sources.list.d/ -name "*nodesource*" -type f -exec rm {} \;

# Update apt
sudo apt-get update
```

---

## Summary

**Quick cleanup:**
```bash
sudo bash cleanup-nodejs.sh
```

**Manual cleanup:**
```bash
sudo apt-get remove -y nodejs npm
sudo apt-get purge -y nodejs npm
sudo rm -f /etc/apt/sources.list.d/nodesource.list
sudo rm -f /etc/apt/trusted.gpg.d/nodesource.gpg
sudo apt-get update
```

**Verify:**
```bash
node --version  # Should show: command not found
npm --version   # Should show: command not found
```

**Your application still works** because it runs in Docker containers with Node.js 24! ✅

---

## After Cleanup

Once Node.js is removed from the host:

1. ✅ **Docker containers still run** - Application code is in containers
2. ✅ **No impact on application** - All Node.js code runs inside Docker
3. ✅ **Cleaner system** - Less packages to maintain
4. ✅ **No version conflicts** - Host and container versions don't conflict

**Your coffee machine controller will continue working normally!** ☕

