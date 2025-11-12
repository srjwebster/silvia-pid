# Silvia PID

A software-based PID controller for Rancilio Silvia espresso machines, running on Raspberry Pi with Docker.

## Overview

This PID controller provides precise temperature control for the Rancilio Silvia espresso machine, eliminating the need for "temperature surfing" and providing consistent brew temperatures. The system uses:

- **MCP9600 thermocouple** for accurate temperature sensing
- **Node.js PID controller** for precise heating control
- **Real-time web interface** with WebSocket updates
- **MongoDB** for temperature history and graphing
- **Docker** for easy deployment and updates

Created and tested using a V6 E edition Silvia. Results may vary with other models - please share your experiences in Issues!

## Features

- 🌡️ Real-time temperature monitoring and control
- 📊 Live temperature graphing via web interface
- 🎛️ Adjustable PID parameters via REST API
- 🔄 WebSocket-based live updates (no polling!)
- 🐳 Containerized deployment with Docker Compose
- 🔒 Optional SSL/HTTPS support
- 📝 Comprehensive logging and error handling
- 🛡️ Safety features (automatic shutdown on sensor failures)

## Quick Start

### Prerequisites

- Raspberry Pi 3/4/5 with 64-bit Raspberry Pi OS (Bookworm/Trixie/Debian)
- MCP9600 thermocouple amplifier connected via I2C
- K-type thermocouple attached to boiler
- Solid-state relay or relay module on GPIO 16
- Internet connection for initial setup

**Note**: Works with Debian Bookworm and Trixie. The installation script automatically compiles `pigpio` from source since it's no longer available in these repos.

### Installation

1. Clone this repository to your Raspberry Pi:
```bash
git clone <repository-url> silvia-pid
cd silvia-pid
```

2. Run the automated installation script:
```bash
sudo bash deploy/install.sh
```

3. Reboot:
```bash
sudo reboot
```

4. Start the service:
```bash
sudo systemctl start silvia-pid
```

5. Access the web interface at `http://raspberrypi.local` or your Pi's IP address

📖 **For detailed installation instructions, hardware setup, and troubleshooting, see [DEPLOYMENT.md](DEPLOYMENT.md)**

## Configuration

### PID Parameters

Edit `/opt/silvia-pid/config.json` to adjust PID parameters:

```json
{
  "target_temperature": 100,
  "proportional": 2.6,
  "integral": 0.8,
  "derivative": 80.0
}
```

Changes are applied automatically within 1 second - no need to restart!

### Environment Variables

Optional settings can be configured in `/opt/silvia-pid/.env`:

- `USE_SSL=true` - Enable HTTPS
- `HTTP_PORT=80` - HTTP port
- `MONGODB_URL` - MongoDB connection string

See `env.example` for all available options.

## Hardware Requirements

- **Raspberry Pi** (3/4/5) with 64-bit OS
- **MCP9600** I2C thermocouple amplifier (address 0x60)
- **K-type thermocouple** attached to Silvia boiler
- **SSR or relay module** for heater control (GPIO 16)

See [DEPLOYMENT.md](DEPLOYMENT.md) for wiring diagrams and detailed hardware setup.

## Testing

### Validate Thermocouple
```bash
cd /opt/silvia-pid
node scripts/test-thermocouple.js
```

### Full Hardware Validation
```bash
cd /opt/silvia-pid
node scripts/validate-hardware.js
```

## Management

### Service Control
```bash
# Start the service
sudo systemctl start silvia-pid

# Stop the service
sudo systemctl stop silvia-pid

# Restart the service
sudo systemctl restart silvia-pid

# Check status
sudo systemctl status silvia-pid

# View logs
sudo journalctl -u silvia-pid -f
```

### Docker Management
```bash
cd /opt/silvia-pid

# View running containers
sudo docker compose ps

# View logs
sudo docker compose logs -f

# Restart containers
sudo docker compose restart

# Rebuild after code changes
sudo docker compose build --no-cache
sudo docker compose up -d
```

## API Endpoints

- `GET /` - Web interface with live temperature graph
- `GET /api/temp/get/:limit` - Get temperature history
- `GET /api/temp/set/:temp` - Set target temperature (°C)
- `GET /api/pid/set/:p-:i-:d` - Set PID parameters (Kp-Ki-Kd)

WebSocket connection provides real-time temperature updates every 3 seconds.

## Architecture

```
┌─────────────────────────────────────────┐
│          Raspberry Pi                    │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  Docker Compose                    │ │
│  │                                    │ │
│  │  ┌──────────────┐  ┌────────────┐ │ │
│  │  │ Node.js App  │  │  MongoDB   │ │ │
│  │  │              │  │            │ │ │
│  │  │ • PID Loop   │  │ • Temp     │ │ │
│  │  │ • Web Server │  │   History  │ │ │
│  │  │ • WebSockets │  │ • Graphing │ │ │
│  │  └──────────────┘  └────────────┘ │ │
│  └────────────────────────────────────┘ │
│         ↓            ↓                   │
│  ┌──────────┐  ┌──────────┐             │
│  │ MCP9600  │  │ GPIO 16  │             │
│  │ (I2C)    │  │ (Relay)  │             │
│  └──────────┘  └──────────┘             │
└─────────────────────────────────────────┘
       ↓                ↓
  Thermocouple    Heating Element
```

## Technical Details

- **Language**: Node.js (JavaScript) + Python for thermocouple reading
- **PID Library**: liquid-pid
- **Web Framework**: Express.js
- **Real-time Updates**: Socket.IO (WebSockets)
- **Database**: MongoDB 7.0 (64-bit)
- **Deployment**: Docker + Docker Compose + systemd
- **Temperature Sensor**: MCP9600 via I2C (Python library)
- **GPIO Control**: pigpio library

The system uses WebSockets instead of HTTP polling for real-time updates, which dramatically reduces load and provides truly live data streaming to clients.

## Safety Features

- Automatic heater shutdown after 5 consecutive temperature read failures
- Temperature range validation (0-200°C)
- Configurable safety limits
- Comprehensive error logging
- Graceful degradation on sensor failures

## Contributing

Contributions are welcome! Please:

1. Test your changes on actual hardware
2. Update documentation as needed
3. Follow existing code style
4. Submit pull requests with clear descriptions

## Troubleshooting

Common issues and solutions are documented in [DEPLOYMENT.md](DEPLOYMENT.md#troubleshooting).

Quick checks:
- Is I2C enabled? `sudo i2cdetect -y 1`
- Are containers running? `sudo docker compose ps`
- Check logs: `sudo journalctl -u silvia-pid -f`

## License

ISC License - See LICENSE file for details

## Credits

Originally created by srjwebster

Tested on Rancilio Silvia V6 E edition

---

**⚠️ Safety Warning**: This project controls high-voltage heating elements. Ensure proper electrical installation and always maintain a manual shutoff method. Use at your own risk.
