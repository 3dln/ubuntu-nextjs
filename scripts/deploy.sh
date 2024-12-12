#!/bin/bash

# Exit on error
set -e

# Function to validate port number
validate_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo "Error: Please provide a valid port number (1-65535)"
        exit 1
    fi
}

# Function to validate git URL
validate_git_url() {
    if [[ ! "$1" =~ ^git@github\.com:.+/.+\.git$ ]]; then
        echo "Error: Please provide a valid GitHub SSH URL (git@github.com:username/repo.git)"
        exit 1
    fi
}

# Clear screen
clear

# Get repository URL
echo "Please enter your GitHub repository SSH URL (git@github.com:username/repo.git):"
read REPO_URL

# Validate repository URL
validate_git_url "$REPO_URL"

# Get port number
echo "Please enter the port number your Next.js application should run on (default: 3000):"
read PORT_NUMBER

# If no port provided, use default
if [ -z "$PORT_NUMBER" ]; then
    PORT_NUMBER=3000
else
    validate_port "$PORT_NUMBER"
fi

# Navigate to deployment directory
echo "Navigating to deployment directory..."
cd /var/www/nextjs

# Remove existing files if any
echo "Cleaning deployment directory..."
rm -rf *

# Clone the repository
echo "Cloning repository..."
git clone "$REPO_URL" .

# Install dependencies
echo "Installing dependencies..."
npm install

# Create or update .env file with PORT
echo "Setting up environment variables..."
if [ -f .env ]; then
    # Update existing PORT in .env
    sed -i "/^PORT=/c\PORT=$PORT_NUMBER" .env
    # Add PORT if it doesn't exist
    grep -q "^PORT=" .env || echo "PORT=$PORT_NUMBER" >> .env
else
    # Create new .env file
    echo "PORT=$PORT_NUMBER" > .env
fi

# Build the application
echo "Building the application..."
npm run build

# Update PM2 configuration
echo "Configuring PM2..."
pm2 delete "next" 2>/dev/null || true  # Delete existing process if any
pm2 start npm --name "next" -- start -- -p $PORT_NUMBER

# Save PM2 process list and setup startup script
echo "Saving PM2 process list and setting up startup..."
pm2 save
pm2 startup

# Update Nginx configuration
echo "Updating Nginx configuration..."
sudo tee /etc/nginx/sites-available/nextjs << EOL
server {
    listen 80;
    server_name _;  # Replace with your domain name

    location / {
        proxy_pass http://localhost:$PORT_NUMBER;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# Test and reload Nginx
echo "Testing Nginx configuration..."
sudo nginx -t
echo "Reloading Nginx..."
sudo systemctl reload nginx

# Print completion message
echo "==================================="
echo "Deployment completed successfully!"
echo "==================================="
echo "Your Next.js application is now:"
echo "1. Cloned from: $REPO_URL"
echo "2. Running on port: $PORT_NUMBER"
echo "3. Managed by PM2 as 'next'"
echo "4. Accessible through Nginx"
echo ""
echo "You can:"
echo "- Monitor the application with: pm2 monit"
echo "- View logs with: pm2 logs next"
echo "- Restart the application with: pm2 restart next"
echo ""
echo "Note: If you have a domain name, update the server_name in"
echo "/etc/nginx/sites-available/nextjs and set up SSL with Let's Encrypt"

# Check if application is accessible
echo ""
echo "Checking if application is accessible..."
sleep 5  # Wait for the application to start
if curl -s http://localhost:$PORT_NUMBER > /dev/null; then
    echo "✅ Application is running and accessible!"
else
    echo "⚠️ Application might not be running. Check logs with: pm2 logs next"
fi