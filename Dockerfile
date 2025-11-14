# Dockerfile for Silvia PID Node.js Application
# Using Node.js v18 (LTS) - better compatibility with native modules like pigpio
FROM node:18-bookworm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-smbus \
    python3-setuptools \
    python3-full \
    i2c-tools \
    wget \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install pigpio from source (not available in Bookworm/Trixie repos)
# make install should put headers in /usr/local/include/pigpio.h
RUN cd /tmp && \
    wget https://github.com/joan2937/pigpio/archive/refs/tags/v79.tar.gz && \
    tar zxf v79.tar.gz && \
    cd pigpio-79 && \
    make && \
    make install && \
    ldconfig && \
    # Verify headers are installed (needed for npm pigpio package)
    ls -la /usr/local/include/pigpio*.h || echo "WARNING: pigpio headers not found" && \
    cd / && \
    rm -rf /tmp/pigpio-79 /tmp/v79.tar.gz

# Install Python dependencies
RUN pip3 install --no-cache-dir mcp9600 --break-system-packages

WORKDIR /app

# Create groups and non-root user with GPIO and I2C access (before npm install)
# Use fixed GIDs to match host system (gpio=986, i2c=987 on this Raspberry Pi)
# Delete existing groups first (base image may have them with wrong GIDs)
RUN groupdel i2c 2>/dev/null || true \
    && groupdel gpio 2>/dev/null || true \
    && groupadd -r -g 986 gpio \
    && groupadd -r -g 987 i2c \
    && groupadd -r silvia \
    && useradd -r -g silvia silvia \
    && usermod -a -G dialout,gpio,i2c silvia

# Copy package files first for better caching
COPY package*.json ./

# Install Node.js dependencies as root (needed for native module compilation)
RUN npm ci --only=production

# Copy application files
COPY pid-process.js .
COPY web-server.js .
COPY temperature.py .
COPY index.html .
COPY config.json .

# Make temperature.py executable
RUN chmod +x temperature.py

# Create directory for logs and data
RUN mkdir -p /var/log/silvia-pid && chown -R silvia:silvia /var/log/silvia-pid
RUN mkdir -p /app/data && chown -R silvia:silvia /app/data

# Change ownership of app files to silvia user
RUN chown -R silvia:silvia /app

# Give Node.js binary capability to bind to ports < 1024 (for network_mode: host)
# This allows the silvia user to bind to port 80 without being root
RUN apt-get update && apt-get install -y libcap2-bin && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/node && \
    rm -rf /var/lib/apt/lists/* && \
    getcap /usr/local/bin/node || echo "WARNING: setcap failed"

# Switch to non-root user (GPIO access is via pigpiod daemon, not direct)
USER silvia

# Environment variables (can be overridden)
ENV MONGODB_URL=mongodb://mongodb:27017
ENV USE_SSL=false
ENV HTTP_PORT=80

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:${HTTP_PORT}/', (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }).on('error', () => process.exit(1));"

# Start both processes using a simple shell script
# In production, consider using a process manager like PM2
CMD ["sh", "-c", "node pid-process.js & node web-server.js"]
