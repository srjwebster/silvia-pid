# Dockerfile for Silvia PID Node.js Application
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
RUN cd /tmp && \
    wget https://github.com/joan2937/pigpio/archive/refs/tags/v79.tar.gz && \
    tar zxf v79.tar.gz && \
    cd pigpio-79 && \
    make && \
    make install && \
    ldconfig && \
    cd / && \
    rm -rf /tmp/pigpio-79 /tmp/v79.tar.gz

# Install Python dependencies
RUN pip3 install --no-cache-dir mcp9600 --break-system-packages

WORKDIR /app

# Copy package files first for better caching
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production

# Copy application files
COPY pid-process.js .
COPY web-server.js .
COPY temperature.py .
COPY index.html .
COPY config.json .

# Make temperature.py executable
RUN chmod +x temperature.py

# Create groups and non-root user with GPIO and I2C access
RUN groupadd -r silvia \
    && groupadd -f gpio \
    && groupadd -f i2c \
    && useradd -r -g silvia silvia \
    && usermod -a -G dialout,gpio,i2c silvia

# Create directory for logs and data
RUN mkdir -p /var/log/silvia-pid && chown -R silvia:silvia /var/log/silvia-pid
RUN mkdir -p /app/data && chown -R silvia:silvia /app/data

# Switch to non-root user
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
