# Monitoring & Health Checks

## Health Check Endpoint

The system now includes a `/health` endpoint that reports the status of all critical components.

### Usage

```bash
curl http://192.168.1.100/health
```

### Response (Healthy)

```json
{
  "status": "healthy",
  "timestamp": "2025-11-12T10:30:45.123Z",
  "uptime": 3600,
  "checks": {
    "mongodb": {
      "status": "healthy",
      "connected": true
    },
    "temperature_readings": {
      "status": "healthy",
      "last_update_seconds_ago": 2,
      "threshold_seconds": 30
    },
    "web_server": {
      "status": "healthy",
      "port": 80,
      "ssl": false
    }
  },
  "details": {
    "mode": "espresso",
    "steam_timer_active": false,
    "connected_clients": 1
  }
}
```

**HTTP Status Code:** `200 OK`

---

### Response (Unhealthy)

```json
{
  "status": "unhealthy",
  "timestamp": "2025-11-12T10:35:20.456Z",
  "uptime": 3900,
  "checks": {
    "mongodb": {
      "status": "unhealthy",
      "connected": false
    },
    "temperature_readings": {
      "status": "unhealthy",
      "last_update_seconds_ago": 45,
      "threshold_seconds": 30
    },
    "web_server": {
      "status": "healthy",
      "port": 80,
      "ssl": false
    }
  },
  "details": {
    "mode": "espresso",
    "steam_timer_active": false,
    "connected_clients": 0
  }
}
```

**HTTP Status Code:** `503 Service Unavailable`

---

## What Gets Checked?

### 1. MongoDB Connection
- **Healthy:** MongoDB is connected and responding
- **Unhealthy:** MongoDB is disconnected or unreachable

**Common causes of failure:**
- MongoDB container not running
- Network issues
- Database crashed

### 2. Temperature Readings
- **Healthy:** Temperature data received within last 30 seconds
- **Unhealthy:** No temperature data for >30 seconds

**Common causes of failure:**
- Thermocouple disconnected
- I2C bus issues
- PID process crashed
- GPIO/sensor issues

### 3. Web Server
- **Healthy:** Server is responding (you got this response!)
- **Unhealthy:** (You wouldn't get a response)

---

## Monitoring Options

### Option 1: Manual Checks (Basic)

Check health occasionally:

```bash
# Simple status check
curl -s http://192.168.1.100/health | jq '.status'

# Full health report
curl -s http://192.168.1.100/health | jq .

# Check if healthy (exit code 0 = healthy, 1 = unhealthy)
curl -sf http://192.168.1.100/health > /dev/null && echo "Healthy" || echo "Unhealthy"
```

---

### Option 2: Simple Monitoring Script (Cron)

Create a monitoring script that runs periodically:

```bash
#!/bin/bash
# /opt/silvia-pid/monitor.sh

HEALTH_URL="http://localhost/health"
LOG_FILE="/var/log/silvia-pid-monitor.log"

# Check health
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL")

if [ "$HTTP_CODE" -eq 200 ]; then
    echo "$(date): Healthy" >> "$LOG_FILE"
else
    echo "$(date): UNHEALTHY (HTTP $HTTP_CODE)" >> "$LOG_FILE"
    
    # Optional: Send notification
    # curl -X POST "https://api.pushover.net/1/messages.json" \
    #   -d "token=YOUR_TOKEN" \
    #   -d "user=YOUR_USER" \
    #   -d "message=Silvia PID is unhealthy!"
    
    # Optional: Restart service
    # sudo docker compose restart silvia-pid
fi
```

**Setup:**
```bash
# Make executable
chmod +x /opt/silvia-pid/monitor.sh

# Add to crontab (check every 5 minutes)
crontab -e

# Add this line:
*/5 * * * * /opt/silvia-pid/monitor.sh
```

---

### Option 3: Docker Healthcheck (Built-in)

The Docker Compose file already has a healthcheck configured:

```yaml
healthcheck:
  test: ["CMD", "node", "-e", "require('http').get('http://localhost:80/', ...)"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

**Check container health:**
```bash
sudo docker ps

# Look for "healthy" or "unhealthy" in STATUS column
# Example:
# CONTAINER ID   IMAGE              STATUS
# abc123         silvia-pid-app     Up 2 hours (healthy)
```

**Update to use /health endpoint:**

Edit `docker-compose.yml`:

```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:80/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

Or with curl:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:80/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

**Auto-restart unhealthy containers:**

Docker will automatically restart unhealthy containers if you have `restart: unless-stopped` (already configured).

---

### Option 4: Uptime Kuma (Recommended - Self-hosted)

Uptime Kuma is a beautiful, self-hosted monitoring tool.

**Install:**
```bash
sudo docker run -d --restart=always \
  -p 3001:3001 \
  -v uptime-kuma:/app/data \
  --name uptime-kuma \
  louislam/uptime-kuma:1
```

**Access:** http://192.168.1.100:3001

**Setup Monitor:**
1. Add new monitor
2. Monitor Type: HTTP(s)
3. URL: `http://192.168.1.100/health`
4. Heartbeat Interval: 60 seconds
5. Expected Status Code: 200
6. Enable notifications (email, Discord, Slack, etc.)

**Features:**
- ✅ Beautiful web dashboard
- ✅ Status page
- ✅ Multiple notification channels
- ✅ Uptime statistics
- ✅ Response time graphs

---

### Option 5: External Monitoring (Cloud)

#### UptimeRobot (Free tier available)
1. Sign up at https://uptimerobot.com
2. Add monitor for `http://your-public-domain/health`
3. Get email/SMS alerts on downtime
4. Requires public endpoint (CloudFlare tunnel)

#### Healthchecks.io (Free for 20 checks)
1. Sign up at https://healthchecks.io
2. Create a check with URL: `http://your-public-domain/health`
3. Get alerts via email, Slack, PagerDuty, etc.

---

### Option 6: Prometheus + Grafana (Advanced)

For full observability with metrics and dashboards.

**1. Add Prometheus endpoint to `web-server.js`:**

```javascript
// Install: npm install prom-client
const promClient = require('prom-client');

// Create metrics
const register = new promClient.Registry();
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// Expose metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});
```

**2. Add Prometheus to docker-compose.yml:**

```yaml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
    - prometheus_data:/prometheus
  ports:
    - "9090:9090"

grafana:
  image: grafana/grafana:latest
  volumes:
    - grafana_data:/var/lib/grafana
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=admin
```

**3. Configure Prometheus (`prometheus.yml`):**

```yaml
scrape_configs:
  - job_name: 'silvia-pid'
    static_configs:
      - targets: ['silvia-pid:80']
    scrape_interval: 10s
    metrics_path: /metrics
```

**Access:**
- Prometheus: http://192.168.1.100:9090
- Grafana: http://192.168.1.100:3000

---

## Alerting Options

### 1. Email Alerts (Simple)

Use `mailx` or `sendemail`:

```bash
# Install
sudo apt-get install mailutils

# In monitor.sh:
if [ "$HTTP_CODE" -ne 200 ]; then
    echo "Silvia PID is unhealthy!" | mail -s "Coffee Machine Alert" you@example.com
fi
```

### 2. Push Notifications

**Pushover (Mobile app):**
```bash
curl -s \
  --form-string "token=YOUR_APP_TOKEN" \
  --form-string "user=YOUR_USER_KEY" \
  --form-string "message=Silvia PID is unhealthy!" \
  https://api.pushover.net/1/messages.json
```

**Ntfy (Free, self-hosted or public):**
```bash
curl -d "Silvia PID is unhealthy!" ntfy.sh/yourUniqueTopic
```

### 3. Discord Webhook

```bash
curl -H "Content-Type: application/json" \
  -d '{"content": "🚨 Silvia PID is unhealthy!"}' \
  https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
```

### 4. Slack Webhook

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🚨 Silvia PID is unhealthy!"}' \
  https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

---

## Automated Recovery

### Auto-restart on Failure

Add to your monitoring script:

```bash
#!/bin/bash
# /opt/silvia-pid/monitor-and-heal.sh

HEALTH_URL="http://localhost/health"
MAX_FAILURES=3
FAILURE_COUNT_FILE="/tmp/silvia-failures"

# Initialize failure counter
if [ ! -f "$FAILURE_COUNT_FILE" ]; then
    echo "0" > "$FAILURE_COUNT_FILE"
fi

# Check health
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL")

if [ "$HTTP_CODE" -eq 200 ]; then
    # Reset failure count on success
    echo "0" > "$FAILURE_COUNT_FILE"
    echo "$(date): Healthy"
else
    # Increment failure count
    FAILURES=$(<"$FAILURE_COUNT_FILE")
    FAILURES=$((FAILURES + 1))
    echo "$FAILURES" > "$FAILURE_COUNT_FILE"
    
    echo "$(date): UNHEALTHY - Failure $FAILURES/$MAX_FAILURES"
    
    # Restart after multiple consecutive failures
    if [ "$FAILURES" -ge "$MAX_FAILURES" ]; then
        echo "$(date): Restarting service..."
        cd /opt/silvia-pid
        sudo docker compose restart silvia-pid
        
        # Reset counter
        echo "0" > "$FAILURE_COUNT_FILE"
        
        # Send notification
        curl -d "Silvia PID restarted after $MAX_FAILURES failures" ntfy.sh/yourTopic
    fi
fi
```

---

## Dashboard (Manual Check)

Quick visual check of system status:

```bash
#!/bin/bash
# dashboard.sh

clear
echo "=== Silvia PID Dashboard ==="
echo ""

# Docker status
echo "Docker Container:"
sudo docker ps --filter name=silvia-pid --format "  Status: {{.Status}}"
echo ""

# Health check
echo "Health Status:"
HEALTH=$(curl -s http://localhost/health)
echo "$HEALTH" | jq -r '"  Overall: \(.status)"'
echo "$HEALTH" | jq -r '"  MongoDB: \(.checks.mongodb.status)"'
echo "$HEALTH" | jq -r '"  Temperature: \(.checks.temperature_readings.status) (last update \(.checks.temperature_readings.last_update_seconds_ago)s ago)"'
echo "$HEALTH" | jq -r '"  Mode: \(.details.mode)"'
echo "$HEALTH" | jq -r '"  Clients: \(.details.connected_clients)"'
echo ""

# Logs (last 10 lines)
echo "Recent Logs:"
sudo docker compose logs --tail 10 silvia-pid | tail -10
```

**Run:**
```bash
bash /opt/silvia-pid/dashboard.sh
```

---

## Summary

| Method | Complexity | Cost | Features |
|--------|-----------|------|----------|
| **Manual curl** | 🟢 Simple | Free | Basic |
| **Cron script** | 🟢 Simple | Free | Automated checks |
| **Docker healthcheck** | 🟢 Simple | Free | Built-in, auto-restart |
| **Uptime Kuma** | 🟡 Medium | Free | Dashboard, alerts, beautiful |
| **UptimeRobot** | 🟢 Simple | Free tier | Cloud-based, SMS alerts |
| **Prometheus/Grafana** | 🔴 Complex | Free | Full observability, metrics |

### My Recommendation

**For most users:**
1. Use **Docker healthcheck** (already configured) for auto-restart
2. Add **Uptime Kuma** for visual dashboard and notifications
3. Optionally add **cron script** for custom alerts

**Setup time:** ~15 minutes  
**Result:** Visual dashboard + email/Discord/Slack alerts + auto-recovery

---

## Testing

Test the health endpoint:

```bash
# Should return 200 when healthy
curl -v http://192.168.1.100/health

# Test unhealthy state (stop MongoDB)
sudo docker compose stop mongodb
sleep 5
curl -v http://192.168.1.100/health  # Should return 503

# Restart MongoDB
sudo docker compose start mongodb
```

---

## Quick Start: Simple Monitoring

```bash
# 1. Create monitor script
cat > /opt/silvia-pid/monitor.sh << 'EOF'
#!/bin/bash
if ! curl -sf http://localhost/health > /dev/null; then
    echo "$(date): UNHEALTHY - Restarting" | tee -a /var/log/silvia-monitor.log
    cd /opt/silvia-pid && sudo docker compose restart silvia-pid
fi
EOF

# 2. Make executable
chmod +x /opt/silvia-pid/monitor.sh

# 3. Add to crontab (check every 5 min)
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/silvia-pid/monitor.sh") | crontab -

# Done! Service will auto-recover if unhealthy.
```

---

Your coffee machine now monitors itself! ☕📊

