#!/bin/bash

set -e

# Constants
NGINX_VERSION=1.24.0
INSTALL_DIR="/usr/local/nginx"
SRC_DIR="/usr/local/src"
SERVICE_FILE="/etc/systemd/system/nginx.service"

echo "🚀 Starting minimal NGINX RTMP installation..."

# Step 1: Install required packages
echo "📦 Installing dependencies..."
sudo apt update
sudo apt install -y build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev wget git

# Step 2: Clone nginx-rtmp-module
cd $SRC_DIR
if [ ! -d "nginx-rtmp-module" ]; then
    git clone https://github.com/arut/nginx-rtmp-module.git
fi

# Step 3: Download and extract NGINX source
if [ ! -d "nginx-$NGINX_VERSION" ]; then
    wget http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz
    tar -xzvf nginx-$NGINX_VERSION.tar.gz
fi

cd nginx-$NGINX_VERSION

# Step 4: Configure NGINX with RTMP module
echo "⚙️ Configuring NGINX with RTMP module..."
./configure --prefix=$INSTALL_DIR \
    --add-module=../nginx-rtmp-module \
    --with-http_stub_status_module

# Step 5: Build and install
echo "🔨 Building and installing NGINX..."
make -j$(nproc)
sudo make install

# Step 6: Configure NGINX for RTMP only
echo "📝 Creating RTMP-only nginx.conf..."
sudo tee $INSTALL_DIR/conf/nginx.conf > /dev/null <<EOF
worker_processes auto;

events {
    worker_connections 1024;
}

# RTMP configuration
rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        # Multi-stream application block
        application live {
            live on;
            record off;

            allow publish all;
            allow play all;

            # HLS settings
            hls on;
            hls_path /usr/local/nginx/html/hls/live;  # Path for storing .ts segments
            hls_fragment 3s;  # Duration of each HLS segment in seconds
            hls_playlist_length 60s;  # Length of the playlist
        }

        # Optional separate application
        application event {
            live on;
            record off;

            allow publish all;
            allow play all;

            # HLS settings
            hls on;
            hls_path /usr/local/nginx/html/hls/event;  # Path for storing .ts segments
            hls_fragment 3s;  # Duration of each HLS segment in seconds
            hls_playlist_length 60s;  # Length of the playlist
        }
    }
}

# HTTP configuration for serving HLS streams
http {
    include       mime.types;
    default_type  application/octet-stream;

    server {
        listen 80;  # HTTP listen port
        server_name localhost;

        # Serve HLS segments
        location /hls/ {
            root /usr/local/nginx/html;
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
            add_header Access-Control-Allow-Headers 'Origin, X-Requested-With, Content-Type, Accept';
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
        }

        # Optional: serve other static files (like an index.html)
        location / {
            root /usr/local/nginx/html;
            index index.html index.htm;
        }
    }
}
EOF

# Step 7: Create the directory if it doesn't exist
sudo mkdir -p /usr/local/nginx/html/hls

# Set permissions for NGINX to write to this directory
sudo chown -R www-data:www-data /usr/local/nginx/html/hls
sudo chmod -R 755 /usr/local/nginx/html/hls

# Step 8: Create systemd service for NGINX
echo "🛠 Creating NGINX systemd service..."
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=NGINX RTMP Server
After=network.target

[Service]
ExecStart=$INSTALL_DIR/sbin/nginx
ExecReload=$INSTALL_DIR/sbin/nginx -s reload
ExecStop=$INSTALL_DIR/sbin/nginx -s stop
PIDFile=$INSTALL_DIR/logs/nginx.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Step 9: Enable and start NGINX service
echo "✅ Starting NGINX RTMP service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx

# Step 10: Open firewall ports if UFW is installed
if command -v ufw > /dev/null; then

    echo "🔓 Opening port 1935 for RTMP..."
    sudo ufw allow 1935/tcp

    echo "🔓 Opening port 80 for HTTP..."
    sudo ufw allow 80/tcp

    echo "🔓 Opening port 22 for SSH..."
    sudo ufw allow 22/tcp

    echo "✅ Enabling UFW firewall..."
    sudo ufw --force enable

    echo "🛡️ UFW firewall status:"
    sudo ufw status

    echo "🔍 Checking NGINX server status..."
    sudo systemctl status nginx

    echo "🌐 Your server's IP address:"
    hostname -I
fi

echo "✅ NGINX RTMP and HLS (HTTP) installation complete!"
echo "➡️ RTMP URL: rtmp://<your-server-ip>/<app-name>/<stream-key>"
echo "➡️ HLS URL : http://<your-server-ip>/hls/<app-name>/<stream-key>.m3u8"
