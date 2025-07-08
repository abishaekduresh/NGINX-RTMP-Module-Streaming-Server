# 📺 NGINX - RTMP and HLS (https) Live Streaming Server

## ⚙️ Installation Steps

### 1. Install Dependencies

Start by installing the necessary dependencies:

```bash
sudo apt update
sudo apt install build-essential libpcre3 libpcre3-dev libssl-dev zlib1g zlib1g-dev
```

### 2. Download RTMP Module

If you don't already have the nginx-rtmp-module, clone it from GitHub:

```bash
cd /usr/local/src
git clone https://github.com/arut/nginx-rtmp-module.git
```

### 3. Download and Extract NGINX Source

Download the NGINX source code. Replace 1.24.0 with the version you prefer:

```bash
wget http://nginx.org/download/nginx-1.24.0.tar.gz
tar -xzvf nginx-1.24.0.tar.gz
cd nginx-1.24.0
```

### 4. Configure NGINX with Required Modules

Run the following command to configure NGINX with the required modules (including the RTMP module):

```bash
./configure --prefix=/usr/local/nginx \
    --add-module=../nginx-rtmp-module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_stub_status_module \
    --with-stream \
    --with-stream_ssl_module
```

Make sure that the nginx-rtmp-module folder is in the correct path (../nginx-rtmp-module from the NGINX source directory).

### 5. Build and Install NGINX

Now, build and install NGINX with the RTMP module:

```bash
sudo make install
```

### 6. Install Certbot

Certbot to obtain and install a Let's Encrypt SSL certificate.

```bash
sudo apt-get install -y certbot
```

### 7. Generate a certificate for your domain

```bash
sudo certbot certonly --standalone -d <your-domain.com>
```

Your certificates will be saved in /etc/letsencrypt/live/<your-domain.com>

### 8. Configure NGINX for RTMP and HLS (https) Streaming

Remove the Default Config and Add new Config

```bash
sudo rm /usr/local/nginx/conf/nginx.conf
sudo nano /usr/local/nginx/conf/nginx.conf
```

Use the following configuration:

```bash
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
        ssl_certificate /etc/letsencrypt/live/<your-domain.com>/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/<your-domain.com>/privkey.pem;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

        # Serve HLS segments over HTTPS
        location /hls/ {
            root /usr/local/nginx/html; # Should match hls_path in RTMP block
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
```

> 📝 **Note:** Replace `<your-domain.com>` in your NGINX configuration and streaming URLs with your actual domain name (e.g., `stream.example.com`).

### 📄 RTMP Configuration Explanation

Below is a breakdown of the RTMP-related section in the NGINX configuration file and what each directive means:

### 🔧 Core Settings

- `worker_processes auto;`  
  Automatically sets the number of worker processes based on the number of available CPU cores.  
  This ensures optimal performance by efficiently utilizing server resources.

- `worker_connections 1024;`  
  Sets the maximum number of simultaneous connections each worker process can handle.
  For example, on a 4-core CPU: `4 workers * 1024 connections = 4096 total connections`.

### 📡 RTMP Server Block

- `listen 1935;`  
  Listens for incoming RTMP streams on port `1935`, the standard RTMP port.
- `chunk_size 4096;`  
  Defines the RTMP chunk size (4 KB). Larger chunks improve performance but might increase latency.

### 🎬 RTMP Application (`live`)

- This defines the streaming endpoint used in your streaming URL (e.g., `rtmp://<your-domain.com>/live/streamkey`).  
  `live on;`
- Enables real-time live streaming. Viewers can watch the stream as it is being pushed.  
  `record off;`
- Disables stream recording on the server. No stream content will be saved to disk.  
  `allow publish all;`
- Allows any client to publish (push) a stream.
  > ⚠️ Note: In production, restrict this to specific IPs or users for security.  
  >  `allow play all;`
- Allows any client to play (view) a stream.
- Can also be restricted based on IP ranges or token authentication.

### 📦 MIME Type Configuration

- `include mime.types;`  
  Loads standard MIME type mappings so NGINX knows how to serve files (e.g., `.m3u8` as `application/vnd.apple.mpegurl`).
- `default_type application/octet-stream;`  
  Sets the fallback content type for unknown file types, treated as binary downloads.

### 🌐 HTTP to HTTPS Redirection Server Block

- `listen 80;`  
  Listens for incoming HTTP (non-secure) requests.
- `server_name localhost;`  
  Defines the domain this server responds to. Replace with your actual domain (e.g., `your-domain.com`) in production.
- `return 301 https://$host$request_uri;`  
  Permanently redirects all HTTP requests to their HTTPS equivalents, ensuring encrypted access.

### 🌐 HTTPS Server Block

- `listen 443 ssl;`  
  Listens for secure HTTPS traffic on port 443.
- `server_name <your-domain.com>;`  
  Replace this with your actual domain name for Let's Encrypt to verify your certificate.

### 🔐 SSL Certificate and Key

- `ssl_certificate` and `ssl_certificate_key`  
  Specifies the fullchain and private key issued by Let's Encrypt, typically located in:
  `/etc/letsencrypt/live/<your-domain.com>/`

### 🛡️ Security Enhancements

- `ssl_protocols TLSv1.2 TLSv1.3;`  
  Enforces the use of only secure and modern TLS versions.
- `ssl_ciphers`  
  Defines strong cipher suites that ensure data is securely encrypted during transmission.
- `ssl_session_cache` , `ssl_session_timeout`  
  Optimize SSL handshakes for repeat connections and reduce CPU load.
- `ssl_stapling` , `ssl_stapling_verify`  
  Speeds up SSL certificate verification and reduces client latency.

### 📺 HTTPS Streaming Configuration

- `location /hls/`  
  Handles the delivery of HLS content (e.g., `.m3u8` playlists and `.ts` segments) over HTTPS. It includes proper MIME types and CORS headers, ensuring compatibility with modern browsers, mobile devices, and streaming players such as Video.js, VLC, and Safari.
- `Access-Control-Allow-Origin *;`  
  Enables cross-origin resource sharing (CORS), allowing your HLS stream to be embedded or accessed from any external domain.
  > 🔒 Tip: You can replace `*` with a specific domain for tighter security in production.
- `location /`  
  Serves static files such as `index.html`, images, or JavaScript assets from `/usr/local/nginx/html`.  
  Useful for hosting a custom web-based video player or status page directly on the streaming server.

### 9. Test the Configuration

Test the NGINX configuration to make sure everything is set up correctly:

```bash
sudo /usr/local/nginx/sbin/nginx -t
```

You should see the following output:

> nginx: the configuration file /usr/local/nginx/conf/nginx.conf syntax is ok  
> nginx: configuration file /usr/local/nginx/conf/nginx.conf test is successful

### 10. Create the HLS Directory

Create the directory for storing HLS segments:

```bash
sudo mkdir -p /usr/local/nginx/html/hls
```

Set permissions for NGINX to write to this directory:

```bash
sudo chown -R www-data:www-data /usr/local/nginx/html/hls
sudo chmod -R 755 /usr/local/nginx/html/hls
```

### 11. Set Up Systemd Service for NGINX

Create a systemd service file for NGINX to manage its startup and restart:

```bash
sudo nano /etc/systemd/system/nginx.service
```

Add the following configuration:

```bash
[Unit]
Description=NGINX RTMP server
After=network.target

[Service]
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s stop
PIDFile=/usr/local/nginx/logs/nginx.pid
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Enable and start the NGINX service:

```bash
sudo systemctl enable nginx
sudo systemctl start nginx
```

### 12. Configure Firewall (if necessary)

Ensure that the RTMP (port 1935), HTTP (port 80), HTTPS (port 443) and SSH (port 22) ports are open:

```bash
sudo ufw allow 1935/tcp # RTMP
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 22/tcp   # SSH
```

If the firewall is inactive, enable it:

```bash
sudo ufw enable
```

Check the status of the firewall:

```bash
sudo ufw status
```

### 13. Verify NGINX Status

To check the status of the NGINX service:

```bash
sudo systemctl status nginx
```

## 🚀 Streaming & Playback

### Stream via OBS or FFmpeg

RTMP URL:

```bash
rtmp://<your-domain.com>/live
```

Stream key: `test`

```bash
rtmp://<your-domain.com>/<app-name>/<stream-key>
```

### ▶️ Playback via RTMP (e.g., VLC)

```bash
rtmp://<your-domain.com>/<app-name>/<stream-key>
```

### ▶️ Playback via HLS (e.g., Video.js, VLC, browser)

```bash
https://<your-domain.com>/hls/<app-name>/<stream-key>.m3u8
```

## 💡 Usage

This script automates the setup of an NGINX RTMP server on Ubuntu.  
Download the `install.sh` file and run the following commands to automate the installation:

```bash
chmod +x install.sh
sudo ./install.sh
```

## 🙌 Credits

- [NGINX](https://nginx.org/)
- [nginx-rtmp-module](https://github.com/arut/nginx-rtmp-module)
- [FFmpeg](https://ffmpeg.org/)

## 📬 Feedback & Contributions

Feel free to open issues or submit pull requests for improvements.
