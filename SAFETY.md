# Safety Documentation

## ⚠️ CRITICAL: This system controls a heating element. Bugs can cause property damage or fire.

## Safety Constants

The system uses multiple temperature limits to protect against dangerous conditions:

### 1. `MAX_TEMP_READING = 200.0°C`
**Purpose:** Sensor validation - rejects physically impossible readings  
**Location:** `pid-process.js` line 10, `temperature.py` line 7  
**Action:** Rejects reading, increments failure counter  
**Rationale:** MCP9600 K-type thermocouple max is ~400°C, but coffee machines should never exceed 200°C

### 2. `MAX_SAFE_TEMP = 160.0°C`
**Purpose:** Emergency shutdown - hardware safety limit  
**Location:** `pid-process.js` line 11  
**Action:** Immediately shuts down heater (PWM = 0), triggers failure counter  
**Rationale:** 
- Silvia boiler rated for ~150°C max
- Steam mode target is 140°C
- 160°C provides 20°C safety margin
- Prevents boiler damage and fire risk

### 3. Target Temperature Limits
**Range:** 80-150°C (enforced in UI and API)  
**Typical values:**
- Espresso: 100°C
- Steam: 140°C
- Max reasonable: 150°C

## Safety Mechanisms

### Layer 1: Sensor Validation (Python)
```python
# temperature.py
if temperature < 0 or temperature > MAX_TEMP_READING:
    print("ERROR: Temperature out of range")
    sys.exit(2)  # Non-zero exit code
```

**Catches:** 
- Thermocouple disconnection (usually reads very high)
- Wiring issues
- Sensor failures

---

### Layer 2: Reading Timeout (Node.js)
```javascript
// pid-process.js
setTimeout(() => {
    temperatureProcess.kill();
    reject(new Error('Temperature read timeout'));
}, 5000);
```

**Catches:**
- Hung I2C bus
- Python script crashes
- Sensor communication failures

---

### Layer 3: Consecutive Failure Tracking
```javascript
if (consecutiveFailures >= 5) {
    console.error('Too many failures, shutting down');
    boiler.pwmWrite(0);
    return;
}
```

**Catches:**
- Intermittent sensor issues
- Gradual hardware degradation
- Prevents operating blind

---

### Layer 4: Temperature Range Validation (Node.js)
```javascript
if (temperature < MIN_TEMP || temperature > MAX_TEMP_READING) {
    console.error('Temperature out of valid range');
    consecutiveFailures++;
    reject();
    return;
}
```

**Catches:**
- Invalid readings that passed Python validation
- Calculation errors
- Memory corruption

---

### Layer 5: Emergency Shutdown
```javascript
if (temperature > MAX_SAFE_TEMP) {
    console.error('EMERGENCY: Temperature too high!');
    boiler.pwmWrite(0);  // Immediate shutdown
    consecutiveFailures = MAX_CONSECUTIVE_FAILURES;
    return;
}
```

**Catches:**
- PID malfunction
- Runaway heating
- Sensor reading correctly but temperature dangerously high

---

### Layer 6: Output Clamping
```javascript
SSROutput = Math.max(0, Math.min(MAX_OUTPUT, SSROutput));
```

**Catches:**
- PID calculation errors
- Negative output values
- Output > 255 (PWM overflow)

---

### Layer 7: Steam Mode Auto-Timeout
```javascript
if (mode === 'steam') {
    setTimeout(() => {
        setMode('espresso');  // Auto-switch to 100°C
    }, STEAM_TIMEOUT_MS);
}
```

**Catches:**
- User forgetting to switch off steam mode
- Prevents 140°C operation for hours
- UI crash/browser close doesn't leave at high temp

---

### Layer 8: Graceful Shutdown
```javascript
process.on('SIGINT', () => {
    boiler.pwmWrite(0);  // Turn off heater
    flushBuffer();       // Save pending data
    client.close();      // Close DB
    process.exit();
});
```

**Catches:**
- Container restart
- System reboot
- Manual service stop

---

## Testing Safety Mechanisms

### Test 1: Sensor Disconnection
```bash
# Disconnect thermocouple physically
# Expected: "Temperature read timeout" after 5 seconds
# Expected: Heater shutdown after 5 consecutive failures
```

### Test 2: Simulated High Temperature
```bash
# Edit temperature.py temporarily to return 180
# Expected: "EMERGENCY: Temperature 180°C exceeds maximum safe limit"
# Expected: Immediate heater shutdown
```

### Test 3: Steam Timeout
```bash
# Switch to steam mode
curl http://192.168.1.100/api/mode/steam/60

# Wait 60 seconds
# Expected: Auto-switch to espresso mode
# Expected: WebSocket event to UI
```

### Test 4: Graceful Shutdown
```bash
sudo docker compose stop silvia-pid

# Expected: Log shows "Flushing buffer"
# Expected: Heater PWM = 0
# Expected: Clean exit
```

## What Could Still Go Wrong?

### Hardware Failures
1. **SSR fails closed (stuck ON):**
   - Software can't turn off heater
   - **Mitigation:** Use quality SSR, add thermal fuse to boiler
   - **Detection:** Temperature will keep rising despite PWM = 0

2. **Thermocouple fails open (disconnected):**
   - Reads very high or very low
   - **Mitigation:** System will shut down after 5 failures ✅

3. **Thermocouple fails incorrectly (reads low):**
   - PID thinks temp is low, applies more heat
   - **Mitigation:** `MAX_SAFE_TEMP` catches runaway ✅
   - **Additional:** Use boiler thermal cutoff switch

4. **Raspberry Pi crashes/freezes:**
   - Last PWM state persists (could be ON)
   - **Mitigation:** Add hardware watchdog timer
   - **Additional:** Silvia has built-in thermal fuse

### Software Bugs
1. **Race condition in control loop:**
   - **Mitigation:** `controlLoopRunning` flag prevents overlapping ✅

2. **PID windup:**
   - **Mitigation:** liquid-pid library handles windup
   - **Additional:** Output clamping to 0-255 ✅

3. **Memory leak:**
   - **Mitigation:** Array size limits (600 points max) ✅
   - **Additional:** Docker container restart on OOM

## Recommendations

### Essential (Already Implemented)
- ✅ Multiple temperature validation layers
- ✅ Emergency shutdown at 160°C
- ✅ Consecutive failure tracking
- ✅ Steam mode auto-timeout
- ✅ Output clamping
- ✅ Graceful shutdown handling

### Highly Recommended (Hardware)
- ⚠️ **Thermal fuse on boiler** (usually built into Silvia)
- ⚠️ **Quality SSR** (Fotek, Crydom, Omron)
- ⚠️ **Proper wiring** (gauge appropriate for load)
- ⚠️ **UPS/surge protector** for Raspberry Pi

### Nice to Have (Software)
- [ ] Watchdog timer (reboot if process hangs)
- [ ] Redundant temperature sensor
- [ ] Rate-of-change monitoring (catch sensor drift)
- [ ] Email/push notifications on errors
- [ ] Historical temperature logging analysis

### Nice to Have (Hardware)
- [ ] External hardware watchdog (cuts power if Pi freezes)
- [ ] Mechanical thermal cutoff switch (backup)
- [ ] Status LED (visible indicator of operation)

## Constants Summary

```javascript
// Sensor validation
MIN_TEMP = 0.0°C              // Below this = sensor error
MAX_TEMP_READING = 200.0°C    // Above this = sensor error

// Safety shutdown
MAX_SAFE_TEMP = 160.0°C       // Emergency shutdown limit

// Normal operation
ESPRESSO_TEMP = 100.0°C       // Normal brewing
STEAM_TEMP = 140.0°C          // Milk steaming
STEAM_TIMEOUT = 300s          // Auto-return to espresso

// Failure handling
MAX_CONSECUTIVE_FAILURES = 5  // Failures before shutdown
TEMP_READ_TIMEOUT = 5000ms    // Sensor timeout

// PWM limits
MAX_OUTPUT = 255              // Maximum PWM value
MIN_OUTPUT = 0                // Minimum PWM value
```

## Important Notes

1. **Never increase `MAX_SAFE_TEMP` above 160°C** without understanding risks
2. **Never disable safety checks** "temporarily" - always permanent
3. **Test thoroughly** after any code changes affecting PID or safety
4. **Monitor logs** regularly for warnings or errors
5. **Inspect hardware** periodically (wiring, connections, SSR condition)

## Emergency Procedures

### If machine overheats:
1. **Immediately unplug** from wall
2. Let cool completely before inspection
3. Check logs: `sudo docker compose logs silvia-pid | grep -i emergency`
4. Inspect thermocouple connection
5. Verify SSR is switching properly (use multimeter)
6. Don't restart until root cause identified

### If strange behavior:
1. Check logs: `sudo docker compose logs -f silvia-pid`
2. Verify temperature readings are reasonable
3. Check for warning messages
4. Restart service: `sudo docker compose restart`
5. If persists, shut down and investigate

### If in doubt:
**UNPLUG THE MACHINE** - coffee is not worth a house fire.

---

**Remember:** This system controls a heating element capable of causing fires. When in doubt, add more safety checks, not fewer.

Stay safe and enjoy your coffee! ☕


