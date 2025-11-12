# Uptime Kuma Setup Guide

Uptime Kuma is a self-hosted monitoring tool that provides:
- ✅ Beautiful status page
- ✅ Email, Discord, Slack, Telegram, and 90+ notification services
- ✅ Uptime statistics and graphs
- ✅ Response time tracking
- ✅ Multiple monitors (can monitor other services too!)

## Quick Setup

### 1. Add Uptime Kuma to docker-compose.yml

```yaml
# Add to your docker-compose.yml services section:

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - uptime_kuma_data:/app/data
    networks:
      - silvia-network

# Add to volumes section:
volumes:
  mongodb_data:
  silvia_logs:
  uptime_kuma_data:  # Add this line
```

### 2. Start Uptime Kuma

```bash
cd /opt/silvia-pid
sudo docker compose up -d uptime-kuma
```

### 3. Access Web Interface

Open in your browser:
```
http://192.168.1.100:3001
```

On first visit, you'll be prompted to create an admin account.

---

## Initial Configuration

### Step 1: Create Admin Account

1. Open `http://192.168.1.100:3001`
2. Create username and password
3. Click "Create"

### Step 2: Set Up Notification Channels

Before creating monitors, set up how you want to be notified:

#### Email Notifications

1. Click **Settings** (gear icon, bottom left)
2. Click **Notifications**
3. Click **Setup Notification**
4. Select **Email (SMTP)**
5. Fill in your email settings:

**Gmail Example:**
```
Notification Type: Email (SMTP)
Friendly Name: My Email
SMTP Host: smtp.gmail.com
SMTP Port: 587
Security: TLS
Username: your-email@gmail.com
Password: [App Password - not your Gmail password!]
From Email: your-email@gmail.com
To Email: your-email@gmail.com
```

**Gmail App Password:**
- Go to https://myaccount.google.com/apppasswords
- Generate an app password for "Mail"
- Use that password (not your regular password)

**Other Email Providers:**

- **Outlook/Hotmail:**
  - Host: `smtp-mail.outlook.com`
  - Port: `587`
  - Security: `TLS`

- **Yahoo:**
  - Host: `smtp.mail.yahoo.com`
  - Port: `587`
  - Security: `TLS`

- **Custom SMTP:**
  - Use your ISP or hosting provider's SMTP settings

6. Click **Test** to verify it works
7. Click **Save**

#### Discord Notifications (Optional)

1. In Discord, go to Server Settings → Integrations → Webhooks
2. Click **New Webhook**
3. Name it "Silvia PID Monitor"
4. Copy the Webhook URL
5. In Uptime Kuma:
   - Setup Notification → **Discord**
   - Paste Webhook URL
   - Test → Save

#### Slack Notifications (Optional)

1. Go to https://api.slack.com/apps
2. Create New App → From Scratch
3. Enable Incoming Webhooks
4. Add Webhook to Workspace
5. Copy Webhook URL
6. In Uptime Kuma:
   - Setup Notification → **Slack**
   - Paste Webhook URL
   - Test → Save

#### Telegram Notifications (Optional)

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow instructions
3. Copy the Bot Token
4. Start a chat with your bot and send any message
5. Get your Chat ID: `https://api.telegram.org/bot<TOKEN>/getUpdates`
6. In Uptime Kuma:
   - Setup Notification → **Telegram**
   - Bot Token: [your token]
   - Chat ID: [your chat ID]
   - Test → Save

---

## Setting Up Monitors

### Monitor 1: Silvia PID Health Check

This monitors the overall health of your coffee machine.

1. Click **Add New Monitor**
2. Fill in:

```
Monitor Type: HTTP(s)
Friendly Name: Silvia PID Health
URL: http://silvia-pid/health
Heartbeat Interval: 60 seconds
Retries: 1
Heartbeat Retry Interval: 20 seconds
Advanced:
  - Accepted Status Codes: 200
  - Request Timeout: 10 seconds
Notifications: [Select your notification method]
```

3. Click **Save**

**What this monitors:**
- Overall system health
- MongoDB connection
- Temperature sensor readings
- Detects if service is down

---

### Monitor 2: Web Interface

Monitors the web UI accessibility.

```
Monitor Type: HTTP(s)
Friendly Name: Silvia PID Web UI
URL: http://silvia-pid/
Heartbeat Interval: 120 seconds
Retries: 1
Accepted Status Codes: 200
Notifications: [Select your notification method]
```

**What this monitors:**
- Web server is responding
- UI is accessible

---

### Monitor 3: MongoDB

Monitors the database directly.

```
Monitor Type: TCP Port
Friendly Name: MongoDB Database
Hostname: mongodb
Port: 27017
Heartbeat Interval: 120 seconds
Notifications: [Select your notification method]
```

**What this monitors:**
- MongoDB container is running
- Database is accepting connections

---

### Optional: Temperature Threshold Monitor

Create a custom endpoint for temperature alerts.

**Add to `web-server.js`:**

```javascript
// Temperature threshold endpoint
app.get('/health/temperature', async (req, res) => {
  try {
    const database = client.db('pid');
    const collection = database.collection('temperatures');
    
    // Get latest reading
    const latest = await collection.findOne(
      {},
      { sort: { timestamp: -1 } }
    );
    
    if (!latest) {
      return res.status(503).json({ error: 'No temperature data' });
    }
    
    const age = Date.now() - latest.timestamp;
    const temp = latest.temperature;
    
    // Alert if temperature reading is stale (>60s) or dangerously high (>155°C)
    if (age > 60000 || temp > 155) {
      return res.status(503).json({
        status: 'critical',
        temperature: temp,
        age_seconds: Math.floor(age / 1000)
      });
    }
    
    res.json({
      status: 'ok',
      temperature: temp,
      age_seconds: Math.floor(age / 1000)
    });
    
  } catch (err) {
    res.status(503).json({ error: err.message });
  }
});
```

**Then add monitor:**
```
Monitor Type: HTTP(s)
Friendly Name: Temperature Critical
URL: http://silvia-pid/health/temperature
Heartbeat Interval: 30 seconds
Accepted Status Codes: 200
Notifications: [High priority notification]
```

---

## Status Page (Public Dashboard)

Create a public status page to view from any device:

1. Click **Status Pages** (bottom left)
2. Click **New Status Page**
3. Fill in:

```
Title: Coffee Machine Status
Slug: coffee (accessible at /status/coffee)
Theme: Auto (or Light/Dark)
```

4. Add monitors to the page by dragging them
5. Click **Save**

**Access your status page:**
```
http://192.168.1.100:3001/status/coffee
```

You can bookmark this on your phone for quick status checks!

---

## Notification Examples

### What You'll Receive

**When service goes down:**
```
🔴 [DOWN] Silvia PID Health is DOWN

Details:
- Monitor: Silvia PID Health
- URL: http://silvia-pid/health
- Error: Connection refused
- Time: 2025-11-12 10:30:45
```

**When service recovers:**
```
✅ [UP] Silvia PID Health is back UP

Details:
- Monitor: Silvia PID Health
- Downtime: 2 minutes 34 seconds
- Time: 2025-11-12 10:33:19
```

**When temperature sensor fails:**
```
🔴 [DOWN] Silvia PID Health is DOWN

Details:
- Monitor: Silvia PID Health
- URL: http://silvia-pid/health
- Status Code: 503 (Service Unavailable)
- Response: {"status":"unhealthy","checks":{"temperature_readings":{"status":"unhealthy"}}}
- Time: 2025-11-12 11:15:22
```

---

## Advanced Configuration

### Notification Rules

You can set different notification channels for different monitors:

1. **Critical monitors** (Health, Temperature) → Email + SMS
2. **Less critical** (Web UI) → Email only
3. **Info only** (MongoDB) → Discord only

### Maintenance Windows

Prevent alerts during known maintenance:

1. Click on a monitor
2. Click **Maintenance**
3. Set start/end time
4. Notifications paused during this window

### Tags

Organize monitors with tags:

1. Settings → Tags
2. Create tags: "Production", "Critical", "Info"
3. Assign to monitors
4. Filter by tag in dashboard

---

## Mobile Access

### Option 1: Bookmark Status Page

Bookmark `http://192.168.1.100:3001/status/coffee` on your phone.

### Option 2: Home Screen Shortcut

**iOS:**
1. Open status page in Safari
2. Tap Share → Add to Home Screen

**Android:**
1. Open status page in Chrome
2. Menu → Add to Home Screen

### Option 3: Use Notifications

Enable mobile notifications through:
- Email (push notifications via Gmail app)
- Telegram (native mobile app)
- Discord (native mobile app)
- Pushover (dedicated notification app)

---

## Docker Compose Integration

Here's the complete `docker-compose.yml` addition:

```yaml
version: '3.8'

services:
  mongodb:
    # ... existing config ...

  silvia-pid:
    # ... existing config ...

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - uptime_kuma_data:/app/data
    networks:
      - silvia-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3001"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 20s

networks:
  silvia-network:
    driver: bridge

volumes:
  mongodb_data:
  silvia_logs:
  uptime_kuma_data:
```

---

## Backup Configuration

Uptime Kuma data is stored in a Docker volume. To back it up:

```bash
# Export backup
sudo docker run --rm \
  -v silvia-pid_uptime_kuma_data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/uptime-kuma-backup.tar.gz -C /data .

# Restore backup
sudo docker run --rm \
  -v silvia-pid_uptime_kuma_data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/uptime-kuma-backup.tar.gz"
```

---

## Troubleshooting

### Can't access Uptime Kuma web interface

```bash
# Check if container is running
sudo docker ps | grep uptime-kuma

# Check logs
sudo docker logs uptime-kuma

# Restart
sudo docker compose restart uptime-kuma
```

### Monitors showing DOWN but service is working

1. Check network connectivity: `sudo docker compose exec uptime-kuma ping silvia-pid`
2. Verify URL is correct (use service name, not localhost)
3. Check accepted status codes (should be 200)

### Email notifications not working

1. Verify SMTP settings
2. Use "Test" button in notification setup
3. Check spam folder
4. For Gmail, use App Password (not regular password)
5. Enable "Less secure app access" or use OAuth2

### Notifications are too frequent

1. Increase **Heartbeat Interval** (e.g., 120 seconds)
2. Increase **Retries** (e.g., 3 retries before alert)
3. Increase **Heartbeat Retry Interval**

---

## Example Notification Scenarios

### Scenario 1: Sensor Disconnects
```
1. Temperature readings stop
2. After 30 seconds, /health returns 503
3. Uptime Kuma detects failure
4. You receive email: "Silvia PID Health is DOWN"
5. You reconnect sensor
6. /health returns 200
7. You receive email: "Silvia PID Health is UP"
```

### Scenario 2: MongoDB Crashes
```
1. MongoDB container stops
2. /health returns 503 (MongoDB unhealthy)
3. Email alert: "Silvia PID Health is DOWN"
4. Docker auto-restarts MongoDB
5. Email: "Silvia PID Health is UP"
```

### Scenario 3: Raspberry Pi Loses Power
```
1. All services stop
2. Uptime Kuma can't reach services
3. Email alerts for all monitors
4. Power restored
5. Services restart automatically
6. Email: All services back UP
```

---

## Recommended Monitor Setup

For a coffee machine, I recommend:

1. **Critical Monitor: Silvia PID Health** (60s interval)
   - Notifications: Email (immediate)
   - Monitors: Overall system health

2. **Monitor: Web UI** (120s interval)
   - Notifications: Email (info only)
   - Monitors: UI accessibility

3. **Optional: MongoDB** (120s interval)
   - Notifications: Discord (info)
   - Monitors: Database health

**Total monitors:** 2-3  
**Total alerts per day (if healthy):** 0  
**Alert latency:** 60-90 seconds from failure

---

## Summary

✅ **Beautiful dashboard** - Visual status at a glance  
✅ **Email alerts** - Notified immediately on issues  
✅ **90+ notification channels** - Discord, Slack, Telegram, SMS, etc.  
✅ **Public status page** - Check from any device  
✅ **Response time graphs** - Historical performance  
✅ **Easy setup** - 10 minutes to full monitoring  

**Setup time:** 10-15 minutes  
**Maintenance:** None (automatic)  
**Cost:** Free  

Your coffee machine now has enterprise-grade monitoring! ☕📊

