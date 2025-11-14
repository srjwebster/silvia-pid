# Docker-Only Installation Steps

Quick reference for running just the Docker build and startup steps, skipping the full install script.

## Prerequisites

- Docker and Docker Compose already installed
- Application files already in `/opt/silvia-pid`
- Power supply checked (optional, but recommended)

## Steps

### 1. Navigate to install directory

```bash
cd /opt/silvia-pid
```

### 2. Pre-pull Docker images

**If power is good (full speed):**
```bash
sudo docker pull mongo:4.4.18 node:18-bookworm louislam/uptime-kuma:1
```

**If power issues detected (power-saving mode):**
```bash
sudo docker pull mongo:4.4.18
sleep 5
sudo docker pull node:18-bookworm
sleep 5
sudo docker pull louislam/uptime-kuma:1
```

### 3. Build Docker images

```bash
sudo docker compose build --no-cache
```

**Note:** This may take 10-20 minutes on a Raspberry Pi.

### 4. Start services

```bash
sudo docker compose up -d
```

### 5. Check status

```bash
sudo docker compose ps
sudo docker compose logs -f
```

## Quick One-Liner (Full Speed)

```bash
cd /opt/silvia-pid && \
sudo docker pull mongo:4.4.18 node:18-bookworm louislam/uptime-kuma:1 && \
sudo docker compose build --no-cache && \
sudo docker compose up -d
```

## Troubleshooting

### Check if MongoDB is running
```bash
sudo docker compose logs mongodb
```

### Restart a specific service
```bash
sudo docker compose restart mongodb
sudo docker compose restart silvia-pid
```

### Stop all services
```bash
sudo docker compose down
```

### Rebuild and restart
```bash
sudo docker compose down
sudo docker compose build --no-cache
sudo docker compose up -d
```

### Check power status (if issues)
```bash
vcgencmd get_throttled
# Should be: 0x0 (no issues)
```

