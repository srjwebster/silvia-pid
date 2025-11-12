# Google Assistant Integration

## Mode API Endpoints

The Silvia PID now has REST endpoints for mode control with automatic steam timeout.

### Available Endpoints

#### 1. Switch to Espresso Mode
```bash
GET /api/mode/espresso
```

**Response:**
```json
{
  "success": true,
  "mode": "espresso",
  "temperature": 100,
  "message": "Switched to espresso mode"
}
```

**Example:**
```bash
curl http://192.168.1.100/api/mode/espresso
```

---

#### 2. Switch to Steam Mode (with auto-timeout)
```bash
GET /api/mode/steam/:duration?
```

**Parameters:**
- `duration` (optional): Timeout in seconds (10-600, default: 300)

**Response:**
```json
{
  "success": true,
  "mode": "steam",
  "temperature": 140,
  "timeout_seconds": 300,
  "message": "Switched to steam mode, will auto-switch to espresso in 300s"
}
```

**Examples:**
```bash
# Default 5-minute timeout
curl http://192.168.1.100/api/mode/steam

# Custom 2-minute timeout
curl http://192.168.1.100/api/mode/steam/120

# Maximum 10-minute timeout
curl http://192.168.1.100/api/mode/steam/600
```

**Safety Feature:** Steam mode automatically switches back to espresso mode after the timeout to prevent overheating.

---

#### 3. Turn Off
```bash
GET /api/mode/off
```

**Response:**
```json
{
  "success": true,
  "mode": "off",
  "temperature": 0,
  "message": "Machine turned off"
}
```

---

#### 4. Get Current Mode
```bash
GET /api/mode
```

**Response:**
```json
{
  "mode": "steam",
  "target_temperature": 140,
  "steam_time_remaining": 245
}
```

**Fields:**
- `mode`: Current mode (`espresso`, `steam`, or `off`)
- `target_temperature`: Current target temperature (°C)
- `steam_time_remaining`: Seconds until steam timeout (null if not in steam mode)

---

## Google Assistant Integration Options

### Option 1: IFTTT (Simplest)

**Setup:**

1. **Create IFTTT Applets:**
   - **Trigger:** "Say a phrase with a text ingredient"
   - **Phrase:** "Turn on steam mode"
   - **Action:** Webhooks → `http://192.168.1.100/api/mode/steam`

2. **For local network only:**
   - IFTTT webhooks need public URL
   - Use CloudFlare Tunnel (free) or ngrok to expose locally

3. **Example applets:**
   - "Turn on steam mode" → `GET /api/mode/steam`
   - "Turn on espresso mode" → `GET /api/mode/espresso`
   - "Turn off coffee machine" → `GET /api/mode/off`

**Pros:** ✅ No coding, visual setup  
**Cons:** ❌ Requires public endpoint, ~2-3s latency

---

### Option 2: Home Assistant (Recommended)

**Setup:**

1. **Install Home Assistant** (can run on same Pi):
```bash
# Install Home Assistant Core
sudo apt-get install python3-dev python3-venv
sudo useradd -rm homeassistant
cd /srv
sudo mkdir homeassistant
sudo chown homeassistant:homeassistant homeassistant
sudo -u homeassistant -H -s
cd /srv/homeassistant
python3 -m venv .
source bin/activate
pip3 install homeassistant
```

2. **Configure Home Assistant** (`configuration.yaml`):

```yaml
# REST Commands
rest_command:
  coffee_espresso:
    url: "http://192.168.1.100/api/mode/espresso"
    method: get
  
  coffee_steam:
    url: "http://192.168.1.100/api/mode/steam/180"  # 3 minutes
    method: get
  
  coffee_off:
    url: "http://192.168.1.100/api/mode/off"
    method: get

# Template Switches (appear as devices)
switch:
  - platform: template
    switches:
      silvia_espresso:
        friendly_name: "Silvia Espresso"
        turn_on:
          service: rest_command.coffee_espresso
        turn_off:
          service: rest_command.coffee_off
        icon_template: mdi:coffee
      
      silvia_steam:
        friendly_name: "Silvia Steam"
        turn_on:
          service: rest_command.coffee_steam
        turn_off:
          service: rest_command.coffee_espresso
        icon_template: mdi:kettle-steam

# Sensors for monitoring
sensor:
  - platform: rest
    name: "Silvia Mode"
    resource: "http://192.168.1.100/api/mode"
    method: GET
    value_template: "{{ value_json.mode }}"
    scan_interval: 10
  
  - platform: rest
    name: "Silvia Temperature"
    resource: "http://192.168.1.100/api/mode"
    method: GET
    value_template: "{{ value_json.target_temperature }}"
    unit_of_measurement: "°C"
    scan_interval: 10
```

3. **Enable Google Assistant Integration:**
   - Settings → Integrations → Add Google Assistant
   - Follow OAuth setup
   - Expose switches to Google Home

4. **Voice Commands:**
   - "Hey Google, turn on Silvia Espresso"
   - "Hey Google, turn on Silvia Steam"
   - "Hey Google, turn off Silvia Steam" (switches to espresso)
   - "Hey Google, is Silvia Steam on?"

**Pros:** ✅ Local network, fast, powerful automation  
**Cons:** ❌ Requires Home Assistant setup

---

### Option 3: Node-RED (For Automation Enthusiasts)

**Setup:**

1. **Install Node-RED:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered)
sudo systemctl enable nodered
sudo systemctl start nodered
```

2. **Create Flow:**
   - HTTP In node → Function node → HTTP Request node
   - Expose webhook endpoints
   - Connect to Google Assistant via IFTTT or Home Assistant

**Pros:** ✅ Visual programming, powerful flows  
**Cons:** ❌ Another service to manage

---

## Exposing to Internet (for IFTTT)

### CloudFlare Tunnel (Recommended - Free)

```bash
# Install
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm -o cloudflared
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared

# Authenticate
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create silvia-pid

# Configure tunnel (~/.cloudflared/config.yml)
cat > ~/.cloudflared/config.yml << EOF
tunnel: <TUNNEL-ID>
credentials-file: /home/pi/.cloudflared/<TUNNEL-ID>.json

ingress:
  - hostname: coffee.yourdomain.com
    service: http://localhost:80
  - service: http_status:404
EOF

# Route DNS
cloudflared tunnel route dns silvia-pid coffee.yourdomain.com

# Run tunnel (or install as service)
cloudflared tunnel run silvia-pid
```

**Security:** Consider adding authentication or restricting to specific endpoints.

---

## WebSocket Events

When mode changes (including timeout), the server emits:

```javascript
io.emit('mode_change', {
  mode: 'espresso',
  reason: 'steam_timeout'  // or 'manual'
});
```

Your UI can listen for this to update the mode display automatically.

---

## Safety Features

### 1. Steam Auto-Timeout
- Default: 5 minutes (300 seconds)
- Configurable: 10 seconds to 10 minutes
- Automatically switches to espresso mode
- Prevents forgetting steam mode on (140°C for hours)

### 2. Timer Cancellation
- Switching modes cancels existing steam timer
- Prevents overlapping timers
- Clean state management

### 3. Validation
- Duration must be 10-600 seconds
- Invalid modes return error
- Config file validation

---

## Example Automations

### Home Assistant Automation: Morning Espresso

```yaml
automation:
  - alias: "Morning Coffee Ready"
    trigger:
      platform: time
      at: "07:00:00"
    condition:
      condition: state
      entity_id: binary_sensor.workday
      state: 'on'
    action:
      - service: switch.turn_on
        entity_id: switch.silvia_espresso
      - delay: "00:05:00"  # Wait 5 min to heat up
      - service: notify.mobile_app
        data:
          message: "☕ Your espresso machine is ready!"
```

### IFTTT: "OK Google, steam my milk"

1. **IFTTT Applet:**
   - Trigger: Google Assistant → "steam my milk"
   - Action: Webhooks → `https://coffee.yourdomain.com/api/mode/steam/120`

2. **Result:**
   - Switches to 140°C
   - Automatically returns to espresso mode after 2 minutes
   - Say: "OK Google, steam my milk"

---

## Testing

```bash
# Test espresso mode
curl http://192.168.1.100/api/mode/espresso

# Test steam mode with 1-minute timeout
curl http://192.168.1.100/api/mode/steam/60

# Wait 60 seconds, then check mode
sleep 60
curl http://192.168.1.100/api/mode
# Should show mode: "espresso"

# Test getting current mode
curl http://192.168.1.100/api/mode

# Test turning off
curl http://192.168.1.100/api/mode/off
```

---

## Monitoring

Watch mode changes in real-time:

```bash
# Server logs
sudo docker compose logs -f silvia-pid | grep -i mode

# You'll see:
# Mode changed to: Steam (140°C)
# Steam mode activated, will auto-switch to espresso in 300s
# Steam timeout reached, switching to espresso mode
# Mode changed to: Espresso (100°C)
```

---

## Summary

✅ **3 Mode Endpoints:** espresso, steam (with timer), off  
✅ **Status Endpoint:** Get current mode and time remaining  
✅ **Auto-Timeout:** Steam mode safety feature  
✅ **Google Assistant Ready:** Works with IFTTT or Home Assistant  
✅ **WebSocket Events:** Real-time mode updates to UI  

Your coffee machine is now voice-controllable! ☕🎤


