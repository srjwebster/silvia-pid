# Dependency Updates - Outdated Packages

This document lists all outdated packages and recommended updates.

## Node.js Dependencies (package.json)

### Critical Updates Needed

#### 1. **socket.io** - ⚠️ **VERY OUTDATED**
- **Current:** `^2.3.0` (2018)
- **Latest:** `^4.7.x` (2024)
- **Status:** Major version update required
- **Breaking Changes:** Yes - API has changed significantly
- **Impact:** WebSocket functionality needs code updates

#### 2. **mongodb** - ⚠️ **VERY OUTDATED**
- **Current:** `^3.6.2` (2021)
- **Latest:** `^6.3.x` or `^7.x` (2024)
- **Status:** Major version update required
- **Breaking Changes:** Yes - API has changed
- **Impact:** Database connection code needs updates
- **Note:** MongoDB server is v7.0 (good), but driver is v3.6.2 (incompatible)

#### 3. **express** - ⚠️ **OUTDATED**
- **Current:** `^4.17.1` (2019)
- **Latest:** `^4.19.x` (2024)
- **Status:** Minor update available
- **Breaking Changes:** No - backward compatible
- **Impact:** Security updates, bug fixes

### OK - No Updates Needed

#### 4. **cors** - ✅ **UP TO DATE**
- **Current:** `^2.8.5` (2018, but still maintained)
- **Latest:** `^2.8.5` (2024)
- **Status:** Latest version
- **Action:** No update needed

#### 5. **liquid-pid** - ⚠️ **CHECK**
- **Current:** `^1.0.0`
- **Status:** Need to check npm for latest version
- **Action:** Verify if newer version exists

#### 6. **pigpio** - ⚠️ **CHECK**
- **Current:** `^3.2.3`
- **Status:** Need to check npm for latest version
- **Action:** Verify if newer version exists
- **Note:** GPIO library - must be compatible with hardware

---

## Python Dependencies

### 1. **mcp9600** - ⚠️ **CHECK**
- **Current:** Latest (installed via pip)
- **Status:** Need to check PyPI for latest version
- **Action:** Verify if newer version exists

---

## System Packages (Dockerfile)

### 1. **pigpio** - ⚠️ **CHECK**
- **Current:** v79 (from GitHub)
- **Status:** Need to check GitHub for latest release
- **Action:** Verify if v80 or newer exists
- **Note:** Compiles from source - must be compatible

### 2. **MongoDB** - ✅ **UP TO DATE**
- **Current:** `mongo:7.0` (Docker image)
- **Latest:** `mongo:7.0` or `mongo:8.0` (if available)
- **Status:** Latest stable version
- **Action:** Verify if 8.0 is available and stable

---

## Recommended Update Strategy

### Phase 1: Safe Updates (No Code Changes)

1. **express** - Update to `^4.19.x`
   - No breaking changes
   - Security updates
   - Bug fixes

2. **cors** - Already latest
   - No update needed

3. **Check for updates:**
   - liquid-pid
   - pigpio (npm)
   - mcp9600 (Python)
   - pigpio (system - v79)

### Phase 2: Major Updates (Requires Code Changes)

1. **socket.io** - Update to `^4.7.x`
   - Breaking changes in API
   - Need to update `web-server.js`
   - Need to update `index.html` (WebSocket client)

2. **mongodb** - Update to `^6.x` or `^7.x`
   - Breaking changes in API
   - Need to update `pid-process.js`
   - Need to update `web-server.js`

---

## Update Commands

### Check Current Versions

```bash
# Check Node.js packages
cd /home/sam/Code/silvia-pid
npm outdated

# Check Python packages
pip list --outdated

# Check Docker images
docker images | grep mongo
```

### Update Safe Packages

```bash
# Update express (safe update)
npm install express@^4.19.2

# Update package.json
# Then rebuild Docker image
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

### Update Major Packages (Requires Testing)

```bash
# Update socket.io (major update - test thoroughly!)
npm install socket.io@^4.7.2

# Update mongodb (major update - test thoroughly!)
npm install mongodb@^6.3.0

# Update code to match new APIs
# Test thoroughly before deploying
```

---

## Breaking Changes to Watch For

### socket.io v4.x

**Changes:**
- WebSocket connection API changed
- Client connection method changed
- Event handling changed

**Code Updates Needed:**
- `web-server.js` - Socket.IO server initialization
- `index.html` - Socket.IO client connection
- Event handling code

**Migration Guide:**
- https://socket.io/docs/v4/migrating-from-2-x-to-3-0/
- https://socket.io/docs/v4/migrating-from-3-x-to-4-0/

### mongodb v6.x

**Changes:**
- Connection API changed
- Query API changed
- Promise handling changed

**Code Updates Needed:**
- `pid-process.js` - MongoDB connection
- `web-server.js` - MongoDB connection
- Query methods
- Collection methods

**Migration Guide:**
- https://www.mongodb.com/docs/drivers/node/current/upgrade-migration/

---

## Testing After Updates

### After Safe Updates (express)

```bash
# Rebuild and test
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d

# Test web UI
curl http://localhost/

# Test API
curl http://localhost/api/mode

# Check logs
sudo docker compose logs -f silvia-pid
```

### After Major Updates (socket.io, mongodb)

```bash
# 1. Test locally first (if possible)
cd /home/sam/Code/silvia-pid
npm install
npm test  # If tests exist

# 2. Test on Pi
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d

# 3. Test all functionality:
# - Web UI loads
# - WebSocket connection works
# - Temperature readings work
# - Database writes work
# - API endpoints work
# - Mode switching works

# 4. Monitor logs for errors
sudo docker compose logs -f silvia-pid
```

---

## Priority Recommendations

### High Priority (Security/Compatibility)

1. **mongodb** - Update to v6.x or v7.x
   - **Reason:** MongoDB server is v7.0, but driver is v3.6.2 (incompatible)
   - **Risk:** May cause compatibility issues
   - **Effort:** Medium (requires code updates)

2. **express** - Update to v4.19.x
   - **Reason:** Security updates, bug fixes
   - **Risk:** Low (backward compatible)
   - **Effort:** Low (no code changes)

### Medium Priority (Features/Bug Fixes)

3. **socket.io** - Update to v4.7.x
   - **Reason:** Better performance, new features
   - **Risk:** Medium (requires code updates)
   - **Effort:** Medium (requires code updates)

### Low Priority (Optional)

4. **Check for updates:**
   - liquid-pid
   - pigpio (npm)
   - mcp9600 (Python)
   - pigpio (system)

---

## Current Package Status

### Node.js Packages

| Package | Current | Latest | Status | Priority |
|---------|---------|--------|--------|----------|
| express | 4.17.1 | 4.19.x | ⚠️ Outdated | High |
| socket.io | 2.3.0 | 4.7.x | ⚠️ Very Outdated | High |
| mongodb | 3.6.2 | 6.x/7.x | ⚠️ Very Outdated | Critical |
| cors | 2.8.5 | 2.8.5 | ✅ Up to date | None |
| liquid-pid | 1.0.0 | ? | ⚠️ Check | Low |
| pigpio | 3.2.3 | ? | ⚠️ Check | Low |

### Python Packages

| Package | Current | Latest | Status | Priority |
|---------|---------|--------|--------|----------|
| mcp9600 | Latest | ? | ⚠️ Check | Low |

### System Packages

| Package | Current | Latest | Status | Priority |
|---------|---------|--------|--------|----------|
| pigpio | v79 | ? | ⚠️ Check | Low |
| MongoDB | 7.0 | 7.0/8.0 | ✅ Up to date | Low |

---

## Recommended Action Plan

### Step 1: Update Safe Packages (Now)

```bash
# Update express (safe)
npm install express@^4.19.2

# Update package.json
# Commit changes
git add package.json package-lock.json
git commit -m "Update express to 4.19.x"

# Rebuild and test
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

### Step 2: Update MongoDB Driver (Next)

```bash
# Update mongodb driver
npm install mongodb@^6.3.0

# Update code in pid-process.js and web-server.js
# Test thoroughly

# Rebuild and test
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

### Step 3: Update Socket.IO (Later)

```bash
# Update socket.io
npm install socket.io@^4.7.2

# Update code in web-server.js and index.html
# Test thoroughly

# Rebuild and test
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d
```

---

## Testing Checklist

After each update, verify:

- [ ] Web UI loads correctly
- [ ] WebSocket connection works
- [ ] Temperature readings work
- [ ] Database writes work
- [ ] API endpoints work
- [ ] Mode switching works
- [ ] Health endpoint works
- [ ] No errors in logs
- [ ] PID control works correctly
- [ ] Chart displays data correctly

---

## Summary

**Critical Updates:**
- ⚠️ **mongodb** - v3.6.2 → v6.x (incompatible with MongoDB 7.0 server)
- ⚠️ **socket.io** - v2.3.0 → v4.7.x (major API changes)

**Safe Updates:**
- ✅ **express** - v4.17.1 → v4.19.x (backward compatible)

**Check:**
- ⚠️ **liquid-pid** - Check for updates
- ⚠️ **pigpio** (npm) - Check for updates
- ⚠️ **mcp9600** (Python) - Check for updates
- ⚠️ **pigpio** (system) - Check for v80 or newer

**Priority:**
1. **mongodb** - Critical (incompatible with server)
2. **express** - High (security updates)
3. **socket.io** - Medium (features, but requires code changes)

