# Deployment Checklist

Quick reference for deploying Silvia PID from scratch.

## Pre-Deployment

- [ ] Raspberry Pi with Debian Trixie installed
- [ ] Pi connected to network
- [ ] Know Pi's IP address: `________________`
- [ ] SSH access working: `ssh pi@192.168.1.100`
- [ ] Domain configured: `coffee.srjwebster.com` → your public IP
- [ ] Router port forwarding: 80, 443 → Pi

## Stage 1: Transfer Code (5 min)

```bash
# From /home/sam/Code/silvia-pid on your computer:
rsync -avz --exclude 'node_modules' --exclude '.git' --exclude 'silvia-pid/' . pi@192.168.1.100:~/silvia-pid/
```

- [ ] Code transferred
- [ ] SSH to Pi: `ssh pi@192.168.1.100`
- [ ] Verify files: `ls ~/silvia-pid`

## Stage 2: Run Installer (15 min)

```bash
cd ~/silvia-pid/deploy
chmod +x install.sh
sudo bash install.sh
```

- [ ] Installer completed successfully
- [ ] Reboot: `sudo reboot`
- [ ] Wait 2-3 minutes
- [ ] SSH back in
- [ ] Check containers: `sudo docker ps` (should see 2 running)

## Stage 3: Test Without Hardware (5 min)

```bash
# Check logs
cd /opt/silvia-pid
sudo docker compose logs -f
# Should see temperature errors (expected without hardware)
```

- [ ] Web UI loads: `http://192.168.1.100`
- [ ] Health check responds: `curl http://192.168.1.100/health`
- [ ] API works: `curl http://192.168.1.100/api/mode`

## Stage 4: Connect Hardware (10 min)

### Wiring

**MCP9600 (I2C):**
- [ ] VCC → Pin 1 (3.3V)
- [ ] GND → Pin 6 (Ground)
- [ ] SDA → Pin 3 (GPIO 2)
- [ ] SCL → Pin 5 (GPIO 3)
- [ ] Thermocouple connected (Red→T+, Blue→T-)

**Relay (GPIO 16):**
- [ ] VCC → Pin 2 (5V)
- [ ] GND → Pin 9 (Ground)
- [ ] IN → Pin 36 (GPIO 16)

### Testing

```bash
# Test I2C
i2cdetect -y 1  # Should show 0x60

# Test temperature
python3 /opt/silvia-pid/temperature.py  # Should output temp in °C

# Restart service
sudo docker compose restart

# Check logs
sudo docker compose logs -f  # Should see actual temperatures
```

- [ ] I2C device detected at 0x60
- [ ] Temperature reading works
- [ ] No errors in logs
- [ ] Web UI shows live temperature
- [ ] Hardware validation passes: `node scripts/validate-hardware.js`

## Stage 5: Enable SSL (10 min)

```bash
cd /opt/silvia-pid/deploy
nano setup-ssl.sh  # Change EMAIL="your-email@example.com"
sudo bash setup-ssl.sh
```

- [ ] Email configured in script
- [ ] SSL certificate obtained
- [ ] Service restarted with HTTPS
- [ ] `https://coffee.srjwebster.com` works
- [ ] Valid SSL certificate (🔒 in browser)
- [ ] Health check: `curl https://coffee.srjwebster.com/health`

## Stage 6: Set Up Monitoring (10 min)

```bash
sudo docker compose up -d uptime-kuma
```

- [ ] Uptime Kuma accessible: `http://192.168.1.100:3001`
- [ ] Admin account created
- [ ] Email notifications configured
- [ ] Health monitor created (checks every 60s)
- [ ] Status page created: `/status/coffee`
- [ ] Test alert sent (stop/start service)
- [ ] Received DOWN email
- [ ] Received UP email

## Final Verification

### Services

```bash
sudo docker ps
# Should show 3 healthy containers:
# - silvia-pid-app
# - mongodb
# - uptime-kuma
```

- [ ] All containers running and healthy
- [ ] Systemd service active: `sudo systemctl status silvia-pid`
- [ ] No errors in logs: `sudo docker compose logs --tail 50`

### Web Access

- [ ] Dashboard: `https://coffee.srjwebster.com`
- [ ] Shows real-time temperature
- [ ] Chart populating
- [ ] Mode buttons work
- [ ] SSL certificate valid
- [ ] Health endpoint: `https://coffee.srjwebster.com/health` (200 OK)

### Hardware

- [ ] Temperature ~20-25°C (room temp)
- [ ] Heater output percentage shown
- [ ] Relay clicks when output changes
- [ ] No hardware errors in logs

### Monitoring

- [ ] Uptime Kuma dashboard shows green
- [ ] Email alerts working
- [ ] Status page accessible
- [ ] External monitoring works (from outside network)

## Optional: Google Assistant (5 min)

Follow `SSL_SETUP.md`:

- [ ] IFTTT account created
- [ ] Webhook applet: "turn on espresso mode"
- [ ] Webhook applet: "steam my milk"
- [ ] Voice commands tested

## Post-Deployment

- [ ] Clean up: `rm -rf ~/silvia-pid`
- [ ] Bookmark dashboard: `https://coffee.srjwebster.com`
- [ ] Bookmark status page: `http://192.168.1.100:3001/status/coffee`
- [ ] Add to phone home screen
- [ ] Document any custom settings

## Common Issues

### Temperature not reading
```bash
i2cdetect -y 1        # Check I2C device
python3 temperature.py # Test Python script
# Check wiring if fails
```

### SSL certificate error
```bash
sudo certbot certificates  # Check cert exists
sudo certbot renew --dry-run  # Test renewal
```

### Service won't start
```bash
sudo docker compose logs silvia-pid  # Check errors
sudo systemctl status docker         # Check Docker
sudo docker compose down && sudo docker compose up -d  # Restart all
```

### Can't access from internet
- Check DNS: `nslookup coffee.srjwebster.com`
- Check port forwarding on router (80, 443)
- Check from Pi: `curl http://localhost`

## Maintenance Commands

```bash
# View logs
sudo docker compose -f /opt/silvia-pid/docker-compose.yml logs -f

# Restart
sudo docker compose -f /opt/silvia-pid/docker-compose.yml restart

# Update code (after rsync)
cd /opt/silvia-pid
sudo docker compose build --no-cache
sudo docker compose up -d

# Check certificate expiry
sudo certbot certificates

# Backup config
cp /opt/silvia-pid/config.json ~/config.json.backup
```

## Documentation Reference

- **Full deployment:** `FRESH_DEPLOYMENT.md`
- **SSL setup:** `SSL_SETUP.md`
- **Monitoring:** `QUICK_START_MONITORING.md` or `UPTIME_KUMA_SETUP.md`
- **Safety:** `SAFETY.md`
- **Updates:** `UPDATING_FILES.md`

---

**Total Time:** ~55 minutes  
**Result:** Production-grade coffee machine controller ☕✅

✅ Deployed  
✅ Secured  
✅ Monitored  
✅ Ready for coffee!

