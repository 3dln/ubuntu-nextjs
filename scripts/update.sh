#!/bin/bash

# Exit on error
set -e

# Project directory
PROJECT_DIR="/var/www/nextjs"

# Function to get current branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD
}

# Function to check if there are uncommitted changes
check_uncommitted_changes() {
    if ! git diff-index --quiet HEAD --; then
        return 1
    else
        return 0
    fi
}

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Error: Project directory not found at $PROJECT_DIR"
    echo "Please run the deployment script first."
    exit 1
fi

# Navigate to project directory
cd "$PROJECT_DIR"

# Check if it's a git repository
if [ ! -d ".git" ]; then
    echo "❌ Error: Not a git repository"
    echo "Please run the deployment script first."
    exit 1
fi

echo "🔍 Checking project status..."

# Store current branch
CURRENT_BRANCH=$(get_current_branch)
echo "📌 Current branch: $CURRENT_BRANCH"

# Check for uncommitted changes
if ! check_uncommitted_changes; then
    echo "⚠️ Warning: You have uncommitted changes"
    echo "Would you like to stash these changes before pulling? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "📦 Stashing changes..."
        git stash
    else
        echo "❌ Update cancelled. Please commit or stash your changes manually."
        exit 1
    fi
fi

# Check if PM2 process exists and get current PORT
echo "🔍 Checking PM2 process and port configuration..."
if pm2 describe next > /dev/null 2>&1; then
    PM2_PORT=$(pm2 describe next | grep -oP 'PORT=\K[0-9]+' || echo "3000")
    echo "📌 Found existing PM2 process on port: $PM2_PORT"
else
    # If no PM2 process exists, check .env file for PORT
    if [ -f .env ] && grep -q "^PORT=" .env; then
        PM2_PORT=$(grep "^PORT=" .env | cut -d '=' -f2)
    else
        PM2_PORT=3000
    fi
    echo "📌 No existing PM2 process found, will use port: $PM2_PORT"
fi

# Pull latest changes
echo "⬇️ Pulling latest changes from remote..."
git pull

# Check if package.json has changed
if git diff HEAD@{1} --name-only | grep -q "package.json"; then
    echo "📦 Package.json changes detected, installing dependencies..."
    npm install
else
    echo "📦 No package.json changes detected, skipping install..."
fi

# Build the application
echo "🔨 Rebuilding the application..."
npm run build

# Start or restart PM2 process
echo "🔄 Managing PM2 process..."
if pm2 describe next > /dev/null 2>&1; then
    echo "Restarting existing PM2 process..."
    pm2 restart next --update-env -- -p $PM2_PORT
else
    echo "Creating new PM2 process..."
    pm2 start npm --name "next" -- start -- -p $PM2_PORT
fi

# Save PM2 process list and setup startup script
echo "💾 Saving PM2 process list and setting up startup..."
pm2 save
pm2 startup

# Check if application is accessible
echo "🔍 Checking if application is accessible..."
sleep 5  # Wait for the application to restart
if curl -s http://localhost:$PM2_PORT > /dev/null; then
    echo "✅ Update completed successfully!"
    echo "✅ Application is running and accessible on port $PM2_PORT"
    
    # Show git log of new changes
    echo ""
    echo "📜 Recent changes:"
    git log -5 --oneline
else
    echo "⚠️ Application might not be running correctly"
    echo "Check the logs with: pm2 logs next"
fi

# Print completion message
echo ""
echo "==================================="
echo "You can:"
echo "- Monitor the application with: pm2 monit"
echo "- View logs with: pm2 logs next"
echo "- Check status with: pm2 status"
echo ""
echo "Current branch: $CURRENT_BRANCH"
echo "Current port: $PM2_PORT"