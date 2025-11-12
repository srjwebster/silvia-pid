# Quick Start: Monitoring Setup

Get email alerts for your coffee machine in 10 minutes!

## Step 1: Deploy Uptime Kuma (2 minutes)

```bash
# Transfer updated docker-compose.yml to Pi
cd /home/sam/Code/silvia-pid
rsync -avz docker-compose.yml pi@192.168.1.100:/opt/silvia-pid/

# SSH to Pi and start Uptime Kuma
ssh pi@192.168.1.100
cd /opt/silvia-pid
sudo docker compose up -d uptime-kuma

# Wait for it to start (check logs)
sudo docker compose logs -f uptime-kuma
# Press Ctrl+C when you see "server running"
```

## Step 2: Access Web Interface (1 minute)

Open in your browser:
```
http://192.168.1.100:3001
```

Create admin account:
- Username: `admin` (or your choice)
- Password: `[choose a secure password]`
- Click **Create**

## Step 3: Set Up Email Notifications (3 minutes)

1. Click **Settings** (gear icon, bottom left)
2. Click **Notifications**
3. Click **Setup Notification**
4. Select **Email (SMTP)**

**For Gmail:**
```
Friendly Name: My Email
SMTP Host: smtp.gmail.com
SMTP Port: 587
Security: TLS
Username: your-email@gmail.com
Password: [Gmail App Password - see below]
From Email: your-email@gmail.com
To Email: your-email@gmail.com
```

**Get Gmail App Password:**
1. Go to https://myaccount.google.com/apppasswords
2. Select app: Mail
3. Copy the 16-character password
4. Paste into Uptime Kuma

5. Click **Test** (you should get a test email)
6. Click **Save**

## Step 4: Create Health Monitor (2 minutes)

1. Click **Add New Monitor** (top left)
2. Fill in:

```
Monitor Type: HTTP(s)
Friendly Name: Coffee Machine Health
URL: http://silvia-pid/health
Heartbeat Interval: 60
Retries: 1
Heartbeat Retry Interval: 20
Accepted Status Codes: 200
```

3. Under **Notifications**, enable your email notification
4. Click **Save**

## Step 5: Create Status Page (2 minutes)

1. Click **Status Pages** (bottom left)
2. Click **New Status Page**
3. Fill in:

```
Title: Coffee Machine
Slug: coffee
Theme: Auto
```

4. Drag "Coffee Machine Health" monitor to the page
5. Click **Save**

6. Access your status page:
```
http://192.168.1.100:3001/status/coffee
```

7. Bookmark this on your phone!

---

## You're Done! ✅

**What you'll get:**

📧 **Email when machine is unhealthy:**
```
🔴 [DOWN] Coffee Machine Health is DOWN
Monitor: Coffee Machine Health
URL: http://silvia-pid/health
Status: 503 Service Unavailable
Time: 2025-11-12 10:30:45
```

📧 **Email when machine recovers:**
```
✅ [UP] Coffee Machine Health is UP
Monitor: Coffee Machine Health
Downtime: 2 minutes 34 seconds
Time: 2025-11-12 10:33:19
```

📊 **Status page you can check anytime:**
- Open `http://192.168.1.100:3001/status/coffee` on any device
- See if machine is healthy
- View uptime percentage
- Check response time graphs

---

## Test It

Test the notifications:

```bash
# Stop the PID service
sudo docker compose stop silvia-pid

# Wait 60-90 seconds - you should get an email alert!

# Restart service
sudo docker compose start silvia-pid

# Wait 60-90 seconds - you should get "service is UP" email
```

---

## Optional: Add More Monitors

**Web UI Monitor:**
```
Friendly Name: Coffee Machine Web UI
URL: http://silvia-pid/
Heartbeat Interval: 120
```

**MongoDB Monitor:**
```
Monitor Type: TCP Port
Friendly Name: MongoDB Database
Hostname: mongodb
Port: 27017
Heartbeat Interval: 120
```

---

## Mobile Access

**Bookmark on phone:**
1. Open `http://192.168.1.100:3001/status/coffee`
2. iOS: Safari → Share → Add to Home Screen
3. Android: Chrome → Menu → Add to Home Screen

Now you have a coffee machine status icon on your phone! 📱☕

---

## Troubleshooting

**Can't access Uptime Kuma:**
```bash
sudo docker compose logs uptime-kuma
sudo docker compose restart uptime-kuma
```

**Email not working:**
- Use Gmail App Password (not regular password)
- Check spam folder
- Click "Test" in notification setup

**Monitor shows DOWN but machine works:**
- Check URL is `http://silvia-pid/health` (not `localhost`)
- Verify accepted status code is `200`

---

## Summary

✅ Uptime Kuma running on port 3001  
✅ Email notifications configured  
✅ Health monitor checking every 60 seconds  
✅ Status page accessible from any device  
✅ Alerts when machine is unhealthy  

**Total time:** 10 minutes  
**Emails per day (when healthy):** 0  
**Emails when problem:** 2 (down alert + recovery alert)  

Your coffee machine now texts you when it needs help! ☕📧✅

