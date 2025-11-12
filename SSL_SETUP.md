# SSL/HTTPS Setup for coffee.srjwebster.com

Now that you have a public domain pointing to your coffee machine, let's secure it with HTTPS!

## Current Setup

✅ Domain: `coffee.srjwebster.com`  
✅ DNS: Points to your home IP  
✅ Port forward: 80 → Raspberry Pi  
✅ Port forward: 443 → Raspberry Pi  

---

## Option 1: Let's Encrypt with Certbot (Recommended)

Free, automated SSL certificates that auto-renew.

### Step 1: Install Certbot on Raspberry Pi

```bash
ssh pi@192.168.1.100

# Install certbot
sudo apt-get update
sudo apt-get install -y certbot

# Stop the silvia-pid service temporarily (needs port 80)
cd /opt/silvia-pid
sudo docker compose stop silvia-pid
```

### Step 2: Obtain Certificate

```bash
# Request certificate using standalone mode
sudo certbot certonly --standalone \
  -d coffee.srjwebster.com \
  --non-interactive \
  --agree-tos \
  -m your-email@example.com

# Certbot will:
# 1. Temporarily start a web server on port 80
# 2. Let's Encrypt will verify you control the domain
# 3. Issue certificate valid for 90 days
```

**Certificates will be stored at:**
```
Certificate: /etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem
Private Key: /etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem
```

### Step 3: Update Environment Variables

Edit `/opt/silvia-pid/.env` (or create it):

```bash
cd /opt/silvia-pid
nano .env
```

Add:
```env
USE_SSL=true
SSL_CERT_PATH=/etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem
HTTP_PORT=80
HTTPS_PORT=443
```

### Step 4: Update docker-compose.yml to Mount Certificates

The certificates are already configured to be mounted:

```yaml
volumes:
  - /etc/letsencrypt:/etc/letsencrypt:ro  # Already in your docker-compose.yml
```

### Step 5: Restart Service

```bash
sudo docker compose up -d
```

### Step 6: Test HTTPS

Open in browser:
```
https://coffee.srjwebster.com
```

You should see:
- 🔒 Secure connection
- Valid SSL certificate
- HTTP automatically redirects to HTTPS

### Step 7: Set Up Auto-Renewal

Certbot certificates expire after 90 days. Set up auto-renewal:

```bash
# Test renewal (dry run)
sudo certbot renew --dry-run

# If successful, add to crontab
sudo crontab -e

# Add this line (renews twice daily, restarts service after renewal):
0 */12 * * * certbot renew --quiet --deploy-hook "docker compose -f /opt/silvia-pid/docker-compose.yml restart silvia-pid"
```

**Done!** Your coffee machine now has HTTPS with auto-renewal! 🔒

---

## Option 2: CloudFlare SSL (Alternative - Easier but Proxied)

Use CloudFlare's SSL without installing anything on your Pi.

### Pros:
- ✅ No certificate management on Pi
- ✅ DDoS protection
- ✅ Hides your home IP
- ✅ Caching (faster page loads)

### Cons:
- ❌ Traffic goes through CloudFlare (not direct)
- ❌ Some latency added

### Setup:

1. **Transfer domain to CloudFlare DNS** (if not already):
   - Add site to CloudFlare
   - Update nameservers at your registrar

2. **Enable SSL:**
   - CloudFlare Dashboard → SSL/TLS → Overview
   - Set to "Flexible" or "Full (strict)"

3. **Create A Record:**
   ```
   Type: A
   Name: coffee
   Content: [Your home IP]
   Proxy status: Proxied (orange cloud)
   ```

4. **Done!** Access via `https://coffee.srjwebster.com`

**Note:** With CloudFlare proxy, you don't need to configure SSL on your Pi - CloudFlare handles it.

---

## Security Considerations

### 1. Authentication (Highly Recommended!)

Your coffee machine is now publicly accessible. Add authentication!

**Option A: Basic Auth (Simple)**

Add to `web-server.js`:

```javascript
// Install: npm install express-basic-auth
const basicAuth = require('express-basic-auth');

// Add before routes
app.use(basicAuth({
  users: { 'coffee': 'your-secure-password' },
  challenge: true,
  realm: 'Silvia PID'
}));
```

**Option B: IP Whitelist**

Only allow access from specific IPs (your phone, work, etc.):

```javascript
const allowedIPs = ['1.2.3.4', '5.6.7.8']; // Your IPs

app.use((req, res, next) => {
  const clientIP = req.ip || req.connection.remoteAddress;
  if (allowedIPs.includes(clientIP)) {
    next();
  } else {
    res.status(403).send('Access denied');
  }
});
```

**Option C: CloudFlare Access (Zero Trust)**

Use CloudFlare's free Zero Trust:
- Dashboard → Zero Trust → Access
- Create application for `coffee.srjwebster.com`
- Require email authentication or Google OAuth
- Free for up to 50 users

### 2. Firewall Rules

```bash
# On Raspberry Pi, restrict access to essential ports
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

### 3. Rate Limiting

Protect against brute force:

```javascript
// Install: npm install express-rate-limit
const rateLimit = require('express-rate-limit');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});

app.use(limiter);
```

### 4. Fail2Ban (Optional)

Automatically ban IPs after failed attempts:

```bash
sudo apt-get install fail2ban
sudo systemctl enable fail2ban
```

---

## Update Uptime Kuma

Now that you have a public URL, update your Uptime Kuma monitors:

### External Monitor

Add a new monitor in Uptime Kuma:

```
Monitor Type: HTTP(s)
Friendly Name: Coffee Machine (Public)
URL: https://coffee.srjwebster.com/health
Heartbeat Interval: 60
Accepted Status Codes: 200
```

This monitors:
- Your home internet connection
- Port forwarding
- SSL certificate validity
- Overall public accessibility

---

## Google Assistant Integration (Now Easy!)

With a public domain, Google Assistant integration is much simpler!

### IFTTT Setup

1. **Create IFTTT account** (free)

2. **Create Applets:**

**Applet 1: Espresso Mode**
- **If:** Google Assistant → "Turn on espresso mode"
- **Then:** Webhooks → `https://coffee.srjwebster.com/api/mode/espresso`

**Applet 2: Steam Mode**
- **If:** Google Assistant → "Steam my milk"
- **Then:** Webhooks → `https://coffee.srjwebster.com/api/mode/steam/120`

**Applet 3: Check Status**
- **If:** Google Assistant → "Is my coffee machine ready?"
- **Then:** Webhooks → `https://coffee.srjwebster.com/api/mode`
- **Then:** Google Assistant → Say response

3. **Test:**
```
"Hey Google, turn on espresso mode"
"Hey Google, steam my milk"
```

**No Home Assistant needed!** IFTTT can reach your public URL directly.

---

## Monitoring External Access

### Check SSL Certificate Expiry

Add to Uptime Kuma:

```
Monitor Type: HTTP(s) - Keyword
Friendly Name: SSL Certificate
URL: https://coffee.srjwebster.com
Keyword: "" (empty - just checking SSL)
Ignore TLS/SSL errors: OFF
Certificate Expiry: Notify if < 14 days
```

You'll get an email 14 days before certificate expires.

---

## Status Page (Public)

You can now share your Uptime Kuma status page:

1. In Uptime Kuma, go to Status Pages
2. Edit your status page
3. Make it public (optional password protect)
4. Access via: `http://192.168.1.100:3001/status/coffee`

**Or expose Uptime Kuma publicly:**

Add port forward: `3001 → 192.168.1.100:3001`

Then access: `https://coffee.srjwebster.com:3001/status/coffee`

---

## Updating Configuration

Your `web-server.js` already supports SSL! Just set environment variables:

```bash
cd /opt/silvia-pid
nano .env
```

```env
# Enable SSL
USE_SSL=true

# Certificate paths (inside container)
SSL_CERT_PATH=/etc/letsencrypt/live/coffee.srjwebster.com/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/coffee.srjwebster.com/privkey.pem

# Ports
HTTP_PORT=80
HTTPS_PORT=443
```

Restart:
```bash
sudo docker compose restart silvia-pid
```

---

## Testing Checklist

After setup, verify:

```bash
# ✅ HTTP redirects to HTTPS
curl -I http://coffee.srjwebster.com
# Should see: Location: https://coffee.srjwebster.com

# ✅ HTTPS works
curl https://coffee.srjwebster.com
# Should see: HTML content

# ✅ Health endpoint works
curl https://coffee.srjwebster.com/health
# Should see: {"status":"healthy",...}

# ✅ API endpoints work
curl https://coffee.srjwebster.com/api/mode
# Should see: {"mode":"espresso",...}

# ✅ SSL certificate valid
openssl s_client -connect coffee.srjwebster.com:443 -servername coffee.srjwebster.com < /dev/null 2>&1 | grep 'Verify return code'
# Should see: Verify return code: 0 (ok)
```

---

## Troubleshooting

### Certificate not working

```bash
# Check certificate files exist
sudo ls -la /etc/letsencrypt/live/coffee.srjwebster.com/

# Check Docker can read them
sudo docker compose exec silvia-pid ls -la /etc/letsencrypt/live/coffee.srjwebster.com/

# Check logs
sudo docker compose logs silvia-pid | grep -i ssl
```

### Port 443 not working

```bash
# Verify port forward
sudo netstat -tlnp | grep :443

# Check if service is listening
curl -k https://localhost:443
```

### Let's Encrypt rate limits

If you hit rate limits (5 certs per domain per week):
- Use `--staging` flag for testing: `certbot certonly --standalone --staging -d coffee.srjwebster.com`
- Or use CloudFlare SSL instead

---

## Summary

✅ **Public domain:** `coffee.srjwebster.com`  
✅ **SSL/HTTPS:** Free with Let's Encrypt (auto-renew)  
✅ **Security:** Authentication recommended  
✅ **Google Assistant:** Easy IFTTT setup  
✅ **Monitoring:** External checks via Uptime Kuma  
✅ **Status page:** Shareable public status  

Your coffee machine is now professionally accessible from anywhere in the world! ☕🌍🔒

**Next steps:**
1. Set up SSL with certbot (10 min)
2. Add authentication (5 min)
3. Update Uptime Kuma monitors (5 min)
4. Set up IFTTT for Google Assistant (5 min)

Total: ~25 minutes to full public deployment!

