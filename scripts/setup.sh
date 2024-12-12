#!/bin/bash

# Exit on error
set -e

# Function to validate domain name
validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        echo "❌ Error: Invalid domain name format"
        exit 1
    fi
}

# Function to get server IP
get_server_ip() {
    # Try different methods to get IP
    IP=$(curl -s -4 ifconfig.me || wget -qO- ifconfig.me || dig +short myip.opendns.com @resolver1.opendns.com)
    if [ -z "$IP" ]; then
        echo "❌ Error: Could not determine server IP address"
        exit 1
    fi
    echo "$IP"
}

# Clear screen
clear

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root or with sudo"
    exit 1
fi

# Get domain name
echo "Please enter your domain name (e.g., example.com):"
read DOMAIN_NAME

# Validate domain name
validate_domain "$DOMAIN_NAME"

# Get server IP
SERVER_IP=$(get_server_ip)
echo "📌 Server IP: $SERVER_IP"

# Install Certbot if not already installed
echo "📦 Installing Certbot..."
apt update
apt install -y certbot python3-certbot-nginx

# Backup existing Nginx configuration
echo "💾 Backing up existing Nginx configuration..."
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp /etc/nginx/sites-available/nextjs "/etc/nginx/sites-available/nextjs.backup.$TIMESTAMP"

# Update Nginx configuration with domain
echo "🔧 Updating Nginx configuration..."
cat > /etc/nginx/sites-available/nextjs << EOL
server {
    server_name ${DOMAIN_NAME} www.${DOMAIN_NAME};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Add security headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    }

    # Optimize SSL
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS (uncomment if you're sure)
    # add_header Strict-Transport-Security "max-age=63072000" always;
}
EOL

# Test Nginx configuration
echo "🔍 Testing Nginx configuration..."
nginx -t

# Reload Nginx
echo "🔄 Reloading Nginx..."
systemctl reload nginx

# Setup SSL with Certbot
echo "🔒 Setting up SSL certificate..."
certbot --nginx -d "$DOMAIN_NAME" -d "www.$DOMAIN_NAME" --non-interactive --agree-tos --email "admin@$DOMAIN_NAME" --redirect

# Final Nginx reload
echo "🔄 Final Nginx reload..."
systemctl reload nginx

# Print DNS instructions
echo "
==================================="
echo "✅ Setup completed successfully!"
echo "==================================="
echo "📝 DNS CONFIGURATION REQUIRED:"
echo "Add these records to your domain's DNS settings:"
echo ""
echo "Type  Name             Value"
echo "----  ---------------  ---------------"
echo "A     $DOMAIN_NAME     $SERVER_IP"
echo "A     www             $SERVER_IP"
echo ""
echo "🔍 After updating DNS records, verify SSL setup:"
echo "https://$DOMAIN_NAME"
echo ""
echo "⚠️ Note: DNS propagation might take up to 48 hours"
echo "You can check propagation status at: https://www.whatsmydns.net/#A/$DOMAIN_NAME"
echo ""
echo "🔄 SSL certificate will auto-renew via Certbot"
echo "==================================="

# Test domain resolution
echo "🔍 Testing domain resolution..."
if host "$DOMAIN_NAME" > /dev/null 2>&1; then
    RESOLVED_IP=$(host "$DOMAIN_NAME" | awk '/has address/ { print $4 }')
    if [ "$RESOLVED_IP" = "$SERVER_IP" ]; then
        echo "✅ Domain is correctly pointing to this server"
    else
        echo "⚠️ Domain is pointing to $RESOLVED_IP (should be $SERVER_IP)"
    fi
else
    echo "⚠️ Domain is not resolving yet. Please update DNS records"
fi