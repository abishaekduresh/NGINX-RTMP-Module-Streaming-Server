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

rtmp {
    server {
        listen 1935;
        chunk_size 4096;

        application live {
            live on;
            record off;
            allow publish all;
            allow play all;
        }

        application event {
            live on;
            record off;
            allow publish all;
            allow play all;
        }
    }
}
EOF

# Step 7: Create systemd service for NGINX
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

# Step 8: Enable and start NGINX service
echo "✅ Starting NGINX RTMP service..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx

# Step 9: Open firewall ports if ufw is present
if command -v ufw > /dev/null; then
    echo "🔓 Opening port 1935 for RTMP..."
    sudo ufw allow 1935/tcp
    sudo ufw --force enable
fi

echo "✅ NGINX RTMP-only installation complete!"
echo "➡️ Use rtmp://<your-server-ip>/live/streamkey"
