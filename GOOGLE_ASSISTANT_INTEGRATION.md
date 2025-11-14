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

### Option 2: Home Assistant with Google Assistant (Full Integration - Recommended)

**Why Home Assistant:**
- Native Google Assistant integration (no IFTTT needed)
- Exposes your coffee machine as a smart device in Google Home
- Works with your existing HTTPS endpoint
- Supports status queries ("Is my coffee machine ready?")
- Can run on the same Pi or separate device

**Setup:**

#### Step 1: Install Home Assistant

**Option A: Docker (Easiest - Recommended)**
```bash
# On your Raspberry Pi (or another device)
cd /opt
sudo docker run -d \
  --name homeassistant \
  --privileged \
  --restart unless-stopped \
  -e TZ=America/New_York \
  -v /opt/homeassistant:/config \
  --network=host \
  ghcr.io/home-assistant/home-assistant:stable
```

**Option B: Home Assistant OS (Full featured)**
- Install on separate device or VM
- Download from: https://www.home-assistant.io/installation/

#### Step 2: Configure Home Assistant

Edit `/opt/homeassistant/configuration.yaml`:

```yaml
# REST Commands for Silvia PID
rest_command:
  silvia_espresso:
    url: "https://coffee.srjwebster.com/api/mode/espresso"
    method: GET
    verify_ssl: true
  
  silvia_steam:
    url: "https://coffee.srjwebster.com/api/mode/steam/180"  # 3 minutes default
    method: GET
    verify_ssl: true
  
  silvia_steam_short:
    url: "https://coffee.srjwebster.com/api/mode/steam/120"  # 2 minutes
    method: GET
    verify_ssl: true
  
  silvia_off:
    url: "https://coffee.srjwebster.com/api/mode/off"
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
    resource: "https://coffee.srjwebster.com/api/mode"
    method: GET
    verify_ssl: true
    value_template: "{{ value_json.mode }}"
    scan_interval: 10
    json_attributes:
      - target_temperature
      - steam_time_remaining
  
  - platform: rest
    name: "Silvia Temperature"
    resource: "https://coffee.srjwebster.com/api/mode"
    method: GET
    verify_ssl: true
    value_template: "{{ value_json.target_temperature }}"
    unit_of_measurement: "°C"
    scan_interval: 10
```

#### Step 3: Enable Google Assistant Integration

1. **In Home Assistant UI:**
   - Go to Settings → Integrations
   - Click "+" → Search "Google Assistant"
   - Click "Google Assistant"

2. **Choose Integration Method:**
   - **Option A: Home Assistant Cloud (Easiest - $5/month)**
     - Subscribe to Nabu Casa (supports Home Assistant development)
     - Automatic Google Assistant integration
     - No port forwarding needed
   
   - **Option B: Manual Setup (Free)**
     - Follow: https://www.home-assistant.io/integrations/google_assistant/
     - Requires OAuth setup with Google
     - More complex but free

3. **Expose Devices:**
   - In Google Assistant settings, select which switches to expose
   - Enable: `silvia_espresso_mode` and `silvia_steam_mode`
   - Give them friendly names: "Coffee Machine Espresso" and "Coffee Machine Steam"

#### Step 4: Link to Google Home

1. Open Google Home app on your phone
2. Add device → Works with Google
3. Search for "Home Assistant"
4. Sign in and authorize
5. Your coffee machine switches will appear!

#### Step 5: Voice Commands

Once linked, you can say:
- **"Hey Google, turn on Coffee Machine Espresso"**
- **"Hey Google, turn on Coffee Machine Steam"**
- **"Hey Google, turn off Coffee Machine Steam"** (switches to espresso)
- **"Hey Google, is Coffee Machine Steam on?"**
- **"Hey Google, what's the temperature of the coffee machine?"**

**Pros:** ✅ Native Google integration, status queries, fast, powerful automation  
**Cons:** ❌ Requires Home Assistant setup (but worth it!)

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


