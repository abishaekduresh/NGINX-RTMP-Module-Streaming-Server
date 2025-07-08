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
./configure --prefix=/usr/local/nginx \
    --add-module=../nginx-rtmp-module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_stub_status_module \
    --with-stream \
    --with-stream_ssl_module
# Make sure the nginx-rtmp-module folder is in the correct path (../nginx-rtmp-module from the Nginx source directory).

# Step 5: Build and install
echo "🔨 Building and installing NGINX..."
make -j$(nproc)
sudo make install

# Step 6: Install Certbot
sudo apt-get install -y certbot

echo "Enter your domain name (e.g., stream.example.com):"
read DOMAIN

# Step 7: Run Certbot with the user-provided domain
echo "⚠️ Stopping any services using port 80 to allow Certbot to bind..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop apache2 2>/dev/null || true

echo "🔐 Requesting SSL certificate for: $DOMAIN"
sudo certbot certonly --standalone -d "$DOMAIN"

echo "✅ Certificate obtained. Restarting any stopped services..."
sudo systemctl start nginx 2>/dev/null || true
sudo systemctl start apache2 2>/dev/null || true

# Step 8: Configure NGINX for RTMP only
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

        # Redirect HTTP to HTTPS
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl;  # HTTPS listen port
        server_name localhost;

        # SSL configuration
        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

        # Serve HLS segments over HTTPS
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

# Step 9: Create the directory if it doesn't exist
sudo mkdir -p /usr/local/nginx/html/hls

# Step 10: Set permissions for NGINX to write to this directory
sudo chown -R www-data:www-data /usr/local/nginx/html/hls
sudo chmod -R 755 /usr/local/nginx/html/hls

# Step 11: Test the Configuration
echo "Testing NGINX configuration"
sudo sudo /usr/local/nginx/sbin/nginx -t

echo "You should see the following output:"
echo "nginx: the configuration file /usr/local/nginx/conf/nginx.conf syntax is ok"
echo "nginx: configuration file /usr/local/nginx/conf/nginx.conf test is successful"

# Step 12: Create systemd service for NGINX
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

# Step 13: Enable and start NGINX service
echo "✅ Starting NGINX RTMP service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx

# Step 14: Open firewall ports if UFW is installed or install it

# Step 15: Check if UFW is installed
if ! command -v ufw > /dev/null; then
    echo "🔧 UFW is not installed. Installing..."
    sudo apt update
    sudo apt install -y ufw
fi

# Step 16: Now configure UFW
echo "🔓 Opening port 1935 for RTMP..."
sudo ufw allow 1935/tcp

echo "🔓 Opening port 80 for HTTP..."
sudo ufw allow 80/tcp

echo "🔓 Opening port 443 for HTTPS..."
sudo ufw allow 443/tcp

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

echo "✅ NGINX RTMP and HLS (HTTPS) installation complete success!"
echo "➡️ RTMP URL: rtmp://$DOMAIN/<app-name>/<stream-key> (e.g., rtmp://$DOMAIN/live/test)"
echo "➡️ HLS URL : https://$DOMAIN/hls/<app-name>/<stream-key>.m3u8 (e.g., https://$DOMAIN/hls/live/test.m3u8)"
