# Silvia PID

A software PID temperature controller for the Rancilio Silvia espresso machine, running on a Raspberry Pi with Docker Compose. Built and tested on a Silvia V6 E. Other models may need different tuning.

**⚠️ Safety warning:** this project switches a mains-voltage heating element. Wire it properly, keep a manual way to cut power, and use it at your own risk.

## How it works

- `temperature.py` reads the boiler temperature from an **MCP9600** thermocouple amplifier (I2C address `0x60`) with a K-type thermocouple.
- `pid-process.js` runs the control loop once a second. It calls `temperature.py`, works out the heater output with [liquid-pid](https://www.npmjs.com/package/liquid-pid) and writes it as PWM (0–255) to **GPIO 16**, which drives a solid-state relay. GPIO goes through the `pigpiod` daemon on `localhost:8888`, via `pigpio-client`.
- `web-server.js` serves the web UI (`index.html`) and the REST API. It pushes live readings, mode changes and machine state to the browser over Socket.IO.
- Readings are stored in **MongoDB** (database `pid`, collection `temperatures`) and kept for 7 days.
- `config.json` holds the target temperature and PID gains. Both processes read and write it, and the PID loop picks up changes within about 10 seconds without a restart.

### Control behaviour

- **Modes:** espresso (default 100 °C), steam (default 140 °C, falls back to espresso after 5 minutes or a set duration) and off (target 0 °C). The mode lives in the web server's memory, so a restart puts it back to espresso.
- **Recovery gains:** if the temperature drops 5 °C or more below its peak within 60 seconds (for example, after a cold water refill), the loop switches to the `recovery_*` gains until it is within 5 °C of target.
- **Hard cut-off at target:** output is forced to 0 whenever the temperature is at or above target.
- **Integral reset:** the PID is re-initialised when the machine goes from "off" to "heating", to clear wind-up.
- **Machine state** (`off` / `heating` / `ready`) is inferred from the temperature trend and saved to `config.json`.

### Safety cut-outs

- Readings outside 0–200 °C are rejected.
- The heater is switched off after 5 failed temperature reads in a row. A read that takes longer than 5 seconds counts as a failure.
- Emergency shutdown above 160 °C.
- The heater is switched off on process exit.

## Hardware

- Raspberry Pi 3, 4 or 5 running 64-bit Raspberry Pi OS (Bookworm or Trixie)
- MCP9600 I2C thermocouple amplifier at address `0x60`, on `/dev/i2c-1`
- K-type thermocouple attached to the boiler
- SSR (or relay module) driven from GPIO 16

## Services

`docker-compose.yml` runs four containers:

| Service | Image | Purpose |
| --- | --- | --- |
| `pigpiod` | `zinen2/alpine-pigpiod` | GPIO daemon on port 8888 (privileged, host network) |
| `mongodb` | `mongo:4.4.18` | Temperature history. 4.4 is used because newer versions need ARMv8.2, which the Pi 3 lacks. |
| `silvia-pid` | built from `Dockerfile` | Runs `pid-process.js` and `web-server.js` (host network, port 80 by default) |
| `uptime-kuma` | `louislam/uptime-kuma:1` | Optional status monitoring on port 3001 |

The app image is `node:18-bookworm` with Python 3, the `mcp9600` Python package and pigpio built from source. `config.json`, `index.html` and the three app source files are bind-mounted into the container, so editing them on the Pi takes effect after `docker compose restart silvia-pid`. You only need to rebuild the image when dependencies change.

## Installation

On the Pi:

```bash
git clone https://github.com/srjwebster/silvia-pid.git
cd silvia-pid
sudo bash deploy/install.sh
sudo reboot
```

`deploy/install.sh` does the following:

1. Updates packages, then installs Docker and the Compose plugin.
2. Edits the boot config: enables I2C, disables the `vc4-kms-v3d` overlay and sets GPU memory, both for pigpiod.
3. Loads the I2C kernel modules and adds udev rules for I2C and GPIO access.
4. Builds pigpio from source and installs a host `pigpiod` systemd service.
5. Copies the project to `/opt/silvia-pid`, pulls the images, builds the app and starts the stack.
6. Installs and enables `deploy/silvia-pid.service`, a systemd unit that runs `docker compose up -d` on boot.

If it detects undervoltage, it slows the CPU and pulls the images one at a time. After the reboot, the stack starts on its own via systemd.

> Note: `install.sh` sets up a host `pigpiod` service **and** the compose file runs a `pigpiod` container. Both use port 8888 on the host network, so only one of them can actually hold the port. Either one works for the app.

### Manual install (Docker already set up)

Enable I2C (`sudo raspi-config` → Interface Options → I2C), then:

```bash
cp env.example .env   # optional, edit as needed
sudo docker compose up -d --build
```

## Configuration

### `config.json`

```json
{
  "target_temperature": 100,
  "espresso_temperature": 100,
  "steam_temperature": 140,
  "proportional": 3.0,
  "integral": 0.05,
  "derivative": 30.0,
  "recovery_proportional": 4.0,
  "recovery_integral": 0.08,
  "recovery_derivative": 35.0
}
```

`target_temperature` is the active setpoint. Mode changes copy `espresso_temperature` or `steam_temperature` into it. Out-of-range values fall back to the last good value: Kp 0–10, Ki 0–5, Kd 0–100, target 0–200 °C. The app also adds `machine_state` and `machine_state_updated` at runtime. The container user has to be able to write to this file.

### Environment (`.env`)

| Variable | Default | Notes |
| --- | --- | --- |
| `HTTP_PORT` | `80` | Web UI / API port |
| `USE_SSL` | `false` | `true` serves HTTPS on `HTTPS_PORT` and redirects HTTP to it |
| `HTTPS_PORT` | `443` | |
| `SSL_KEY_PATH`, `SSL_CERT_PATH` | Let's Encrypt paths for `coffee.srjwebster.com` | `/etc/letsencrypt` is mounted read-only. If the certs can't be read, the server falls back to HTTP. |
| `API_KEY` | empty | When set, write endpoints need it (see below). When empty, anyone on the network can change settings. |
| `DEBUG` | `false` | Verbose logging. Off by default to reduce SD card wear. |

`MONGODB_URL` is fixed to `mongodb://localhost:27017` in `docker-compose.yml`.

## Web UI and API

Open `http://<pi-address>/`. The page shows a live temperature/output graph, mode buttons (espresso, steam, off), a target temperature control and a field for the API key. The key is kept in the browser's local storage and sent as an `X-API-Key` header. PID gains are changed through the API or by editing `config.json`.

Write endpoints accept the API key as an `x-api-key` header, an `api_key` cookie or an `?api_key=` query parameter.

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| GET | `/` | | Web UI |
| GET | `/health` | | Health of the web server, MongoDB and recent readings (503 when unhealthy) |
| GET | `/api/temp/get/:limit` | | Up to `limit` readings from the last hour, newest first |
| GET | `/api/temp/set/:temp` | ✓ | Set the target (0–200 °C) and save it as the current mode's temperature |
| GET | `/api/pid/set/:p-:i-:d` | ✓ | Set Kp, Ki and Kd together |
| GET/POST | `/api/pid/update` | ✓ | Set one gain: `parameter` (`proportional`, `integral`, `derivative` or a `recovery_*` one) and `value`, as query parameters or a JSON body |
| GET | `/api/mode` | | Current mode, temperatures, remaining steam time and machine state |
| GET | `/api/mode/espresso` | ✓ | Espresso mode |
| GET | `/api/mode/steam/:duration?` | ✓ | Steam mode. Optional duration 10–600 s, default 300 s. |
| GET | `/api/mode/off` | ✓ | Target 0 °C |
| GET | `/api/machine-state` | | `off` / `heating` / `ready` |

The mode endpoints are plain GETs, so they also work from Home Assistant, IFTTT or Node-RED.

Socket.IO events from the server: `temp_history` (on connect), `temp_update`, `machine_state`, `mode_change`.

## Operating

```bash
cd /opt/silvia-pid

sudo docker compose ps                         # status
sudo docker compose logs -f silvia-pid         # app logs
sudo docker compose restart silvia-pid         # pick up edited source/config
sudo docker compose up -d --build              # rebuild after dependency changes
sudo systemctl status silvia-pid               # boot-time unit

# Hardware checks
sudo i2cdetect -y 1                                        # MCP9600 at 0x60
sudo docker compose exec silvia-pid python3 temperature.py # one reading
```

`temperature.py` exit codes: `0` success, `1` sensor/I2C error, `2` reading out of range, `3` `mcp9600` library missing.

## License

ISC
