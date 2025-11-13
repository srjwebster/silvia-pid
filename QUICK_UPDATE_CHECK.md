# Quick Dependency Update Check

Quick reference for updating outdated packages.

## Critical Issue: MongoDB Driver Incompatibility

**Problem:**
- MongoDB server: `mongo:7.0` (Docker image)
- MongoDB driver: `mongodb@^3.6.2` (Node.js package)
- **Status:** Incompatible! Driver v3.6.2 doesn't support MongoDB 7.0

**Impact:**
- May cause connection errors
- May cause query failures
- May cause performance issues

**Solution:**
- Update `mongodb` driver to `^6.3.0` or `^7.0.0`
- Update code to match new API

## Outdated Packages Summary

### Very Outdated (Need Updates)

1. **socket.io**: `^2.3.0` → `^4.7.2` (2018 → 2024)
   - Major API changes
   - Requires code updates

2. **mongodb**: `^3.6.2` → `^6.3.0` or `^7.0.0` (2021 → 2024)
   - Major API changes
   - Required for MongoDB 7.0 compatibility
   - Requires code updates

3. **express**: `^4.17.1` → `^4.19.2` (2019 → 2024)
   - Minor update
   - No code changes needed
   - Security updates

### Up to Date

- **cors**: `^2.8.5` (latest)

### Need to Check

- **liquid-pid**: `^1.0.0` (check npm for updates)
- **pigpio**: `^3.2.3` (check npm for updates)
- **mcp9600**: Python package (check PyPI)
- **pigpio**: v79 from GitHub (check for v80+)

---

## Quick Update Commands

### Check Current Versions

```bash
# Node.js packages
npm outdated

# Python packages
pip list --outdated
```

### Update Safe Packages (No Code Changes)

```bash
# Update express
npm install express@^4.19.2

# Rebuild Docker
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

### Update Critical Packages (Requires Code Changes)

```bash
# Update mongodb (REQUIRED for MongoDB 7.0 compatibility)
npm install mongodb@^6.3.0

# Update socket.io (optional but recommended)
npm install socket.io@^4.7.2

# Update code to match new APIs
# See DEPENDENCY_UPDATES.md for migration guides

# Rebuild Docker
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

---

## Recommended Update Order

1. **express** (safe, no code changes)
2. **mongodb** (critical, requires code updates)
3. **socket.io** (optional, requires code updates)

---

## Testing After Updates

```bash
# Test web UI
curl http://localhost/

# Test API
curl http://localhost/api/mode

# Test WebSocket (check browser console)
# Open: http://localhost

# Test database
curl http://localhost/api/temp/set/100

# Check logs
sudo docker compose logs -f silvia-pid
```

---

## Migration Guides

- **MongoDB Driver:** https://www.mongodb.com/docs/drivers/node/current/upgrade-migration/
- **Socket.IO:** https://socket.io/docs/v4/migrating-from-2-x-to-3-0/
- **Express:** No migration needed (backward compatible)

---

For detailed information, see `DEPENDENCY_UPDATES.md`.

