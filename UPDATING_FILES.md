# How to Update Files

## File Update Strategy (Hybrid Approach)

The Docker setup uses a hybrid approach for easy updates:

### 📄 Mounted Files (Instant Updates)

These files are **mounted** from the host - changes appear after container restart:

- ✅ `config.json` - PID parameters (auto-reloaded every 10s, no restart needed!)
- ✅ `index.html` - Web UI

**To update:**
```bash
# 1. Edit file on host
nano /opt/silvia-pid/index.html

# 2. Restart container
sudo docker compose restart silvia-pid

# 3. Hard refresh browser (Ctrl+Shift+R)
```

### 🔧 Built-in Files (Requires Rebuild)

These files are **copied** into the Docker image - changes require rebuild:

- ⚙️ `pid-process.js` - PID control loop
- ⚙️ `web-server.js` - API server
- ⚙️ `temperature.py` - Thermocouple reader

**To update:**
```bash
# 1. Transfer updated files to Pi
rsync -avz pid-process.js web-server.js temperature.py pi@192.168.1.100:/opt/silvia-pid/

# 2. SSH to Pi
ssh pi@192.168.1.100

# 3. Rebuild and restart
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

## Quick Update Workflows

### Update UI Only (index.html)

```bash
# From your dev machine
cd /home/sam/Code/silvia-pid
rsync -avz index.html pi@192.168.1.100:/opt/silvia-pid/

# On Pi (or via SSH)
ssh pi@192.168.1.100 "cd /opt/silvia-pid && sudo docker compose restart silvia-pid"

# Hard refresh browser
# Chrome/Firefox: Ctrl+Shift+R
# Safari: Cmd+Option+R
```

**Time to see changes: ~10 seconds**

### Update PID Parameters (config.json)

```bash
# Option 1: Edit directly on Pi
ssh pi@192.168.1.100
nano /opt/silvia-pid/config.json
# Changes apply automatically in <10 seconds, no restart needed!

# Option 2: Edit locally and sync
nano config.json
rsync -avz config.json pi@192.168.1.100:/opt/silvia-pid/
# Changes apply automatically in <10 seconds
```

**Time to see changes: <10 seconds (automatic)**

### Update Application Code (*.js, *.py)

```bash
# 1. Transfer all changed files
cd /home/sam/Code/silvia-pid
rsync -avz pid-process.js web-server.js temperature.py pi@192.168.1.100:/opt/silvia-pid/

# 2. Rebuild image
ssh pi@192.168.1.100 "cd /opt/silvia-pid && sudo docker compose build --no-cache && sudo docker compose up -d"
```

**Time to see changes: ~2-3 minutes (rebuild time)**

### Update Everything

```bash
# Sync entire project (excluding node_modules and Go code)
cd /home/sam/Code/silvia-pid
rsync -avz --exclude 'node_modules' --exclude 'silvia-pid/' --exclude '.git' . pi@192.168.1.100:/opt/silvia-pid/

# Rebuild and restart
ssh pi@192.168.1.100 "cd /opt/silvia-pid && sudo docker compose build --no-cache && sudo docker compose up -d"
```

## Why This Approach?

### Benefits of Mounting config.json and index.html:

✅ **Instant UI updates** - Tweak design without waiting for rebuild  
✅ **Live PID tuning** - Adjust parameters and see results immediately  
✅ **Easy customization** - Non-technical users can edit config  
✅ **Quick fixes** - Fix typos or styling without rebuild  

### Benefits of Building-in Application Code:

✅ **Production safety** - Code changes require deliberate rebuild  
✅ **Prevent accidents** - Can't accidentally break control loop  
✅ **Portability** - Image contains all dependencies  
✅ **Consistency** - Same code runs everywhere  

## Troubleshooting

### "Changes don't appear after restart"

**For mounted files (index.html, config.json):**
```bash
# 1. Verify file exists on host
ls -la /opt/silvia-pid/index.html

# 2. Check file is mounted in container
sudo docker compose exec silvia-pid ls -la /app/index.html

# 3. Check the content matches
sudo docker compose exec silvia-pid head -20 /app/index.html

# 4. Hard refresh browser (clear cache)
# Chrome/Firefox: Ctrl+Shift+R
```

**For built-in files (*.js, *.py):**
```bash
# 1. Verify you rebuilt the image
sudo docker compose build --no-cache

# 2. Verify container is using new image
sudo docker compose down
sudo docker compose up -d

# 3. Check logs for errors
sudo docker compose logs -f silvia-pid
```

### "Config changes don't apply"

Config is reloaded every 10 seconds automatically. Wait 10 seconds and check logs:

```bash
sudo docker compose logs -f silvia-pid | grep "Config changed"
# Should see: "Config changed, reinitializing PID controller"
```

If not appearing:
- Check JSON syntax: `cat /opt/silvia-pid/config.json | jq .`
- Restart container: `sudo docker compose restart silvia-pid`

### "Browser shows old UI"

1. **Hard refresh:** Ctrl+Shift+R (or Cmd+Shift+R on Mac)
2. **Clear cache:** Browser settings → Clear cache
3. **Incognito mode:** Test in private/incognito window
4. **Check file:** `curl http://192.168.1.100/ | head -50`

### "Container won't start after rebuild"

```bash
# Check logs for errors
sudo docker compose logs silvia-pid

# Common issues:
# - Syntax error in JS/Python code
# - Missing dependencies in package.json
# - File permissions issues

# Rollback to previous version:
sudo docker compose down
# Restore old files from backup
sudo docker compose up -d
```

## File Permissions

Ensure files are readable:

```bash
# On Pi
cd /opt/silvia-pid
sudo chmod 644 index.html config.json
sudo chmod 755 temperature.py
```

## Development Workflow

### Testing Changes Locally First

```bash
# On your dev machine (won't have GPIO/I2C, but can test UI/logic)
cd /home/sam/Code/silvia-pid

# Test web server only
USE_SSL=false HTTP_PORT=3000 node web-server.js

# Open browser to http://localhost:3000
# Test UI changes without deploying to Pi
```

### Iterating on UI

1. Edit `index.html` locally
2. Test in browser (reload file:// URL)
3. When satisfied, sync to Pi:
```bash
rsync -avz index.html pi@192.168.1.100:/opt/silvia-pid/
ssh pi@192.168.1.100 "cd /opt/silvia-pid && sudo docker compose restart silvia-pid"
```

## Quick Commands Reference

```bash
# Restart container (for mounted file changes)
sudo docker compose restart silvia-pid

# Rebuild image (for code changes)
sudo docker compose build --no-cache

# Stop and restart everything
sudo docker compose down && sudo docker compose up -d

# View logs
sudo docker compose logs -f silvia-pid

# Execute command in container
sudo docker compose exec silvia-pid cat /app/index.html

# Check which files are mounted
sudo docker compose config | grep volumes -A 10
```

## Summary

| File Type | Update Method | Time | Restart Needed? |
|-----------|---------------|------|-----------------|
| `config.json` | Edit & wait | <10s | No (auto-reload) |
| `index.html` | Edit & restart | ~10s | Yes (container only) |
| `*.js`, `*.py` | Edit & rebuild | ~2-3min | Yes (rebuild) |

Choose the right approach based on what you're updating! 🚀

