#!/bin/bash

# Ubuntu Server Setup Script
# This script provides an interactive setup for Ubuntu Server with system checks
# Version: 1.0

# Removing strict mode for menu interaction
# set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
INFO="${GREEN}[INFO]${NC}"
WARN="${YELLOW}[WARN]${NC}"
ERROR="${RED}[ERROR]${NC}"

# Log file setup
LOG_FILE="/var/log/server-setup.log"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "$timestamp - $message" | tee -a "$LOG_FILE"
}

# Check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${ERROR} Please run as root"
        exit 1
    fi
}

# Function to create new admin user
create_admin_user() {
    log_message "Setting up admin user..."
    
    # Prompt for username
    read -p "Enter new admin username: " admin_user
    
    # Check if user already exists
    if id "$admin_user" &>/dev/null; then
        echo -e "${ERROR} User $admin_user already exists"
        return 1
    fi
    
    # Create user with home directory
    useradd -m -s /bin/bash "$admin_user"
    
    # Generate a secure password
    admin_pass=$(openssl rand -base64 12)
    
    # Set the password
    echo "$admin_user:$admin_pass" | chpasswd
    
    # Add user to sudo group
    usermod -aG sudo "$admin_user"
    
    # Save credentials securely
    echo "Admin User Credentials:" > /root/.admin_credentials
    echo "Username: $admin_user" >> /root/.admin_credentials
    echo "Password: $admin_pass" >> /root/.admin_credentials
    chmod 600 /root/.admin_credentials
    
    # Create .ssh directory for new user
    mkdir -p "/home/$admin_user/.ssh"
    chmod 700 "/home/$admin_user/.ssh"
    touch "/home/$admin_user/.ssh/authorized_keys"
    chmod 600 "/home/$admin_user/.ssh/authorized_keys"
    chown -R "$admin_user:$admin_user" "/home/$admin_user/.ssh"
    
    log_message "Admin user $admin_user created successfully"
    echo -e "${INFO} Admin user credentials saved to /root/.admin_credentials"
    echo -e "${INFO} Please save these credentials NOW:"
    echo -e "Username: $admin_user"
    echo -e "Password: $admin_pass"
    echo -e "${WARN} After setting up SSH keys, you'll need to use these credentials for sudo access"
}


# Function to setup SSH keys
setup_ssh_keys() {
    log_message "Setting up SSH key authentication..."
    
    # Get username
    read -p "Enter the username to setup SSH keys for: " ssh_user
    
    # Verify user exists
    if ! id "$ssh_user" &>/dev/null; then
        echo -e "${ERROR} User $ssh_user does not exist"
        return 1
    }
    
    # Get the SSH public key
    echo "Please paste your SSH public key (ssh-rsa or ssh-ed25519 format):"
    read -r ssh_key
    
    # Validate SSH key format
    if [[ ! $ssh_key =~ ^(ssh-rsa|ssh-ed25519) ]]; then
        echo -e "${ERROR} Invalid SSH key format"
        return 1
    }
    
    # Ensure .ssh directory exists
    user_home=$(eval echo ~$ssh_user)
    mkdir -p "$user_home/.ssh"
    chmod 700 "$user_home/.ssh"
    
    # Add the SSH key
    echo "$ssh_key" >> "$user_home/.ssh/authorized_keys"
    chmod 600 "$user_home/.ssh/authorized_keys"
    chown -R "$ssh_user:$ssh_user" "$user_home/.ssh"
    
    log_message "SSH key added for user $ssh_user"
    echo -e "${INFO} SSH key authentication configured for $ssh_user"
}

# Function to verify SSH access
verify_ssh_access() {
    local test_user=$1
    local current_port=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    
    echo -e "${INFO} Please test SSH access with:"
    echo "ssh -p ${current_port:-22} $test_user@$(curl -s ifconfig.me)"
    echo -e "${WARN} DO NOT CONTINUE until you've verified SSH access in a new terminal"
    echo -e "${WARN} Are you able to connect via SSH in a new terminal? (yes/no)"
    read -r ssh_test_result
    
    if [[ ! $ssh_test_result =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        echo -e "${ERROR} SSH verification failed. Please check your configuration"
        return 1
    }
    
    return 0
}

# Function to check DNS configuration
check_dns_config() {
    local status="[ ]"
    local details=""
    
    if [ -f "/etc/systemd/resolved.conf" ]; then
        local current_dns=$(grep "^DNS=" /etc/systemd/resolved.conf 2>/dev/null | cut -d= -f2)
        if [ -n "$current_dns" ]; then
            status="[✓]"
            details=" (Current DNS: $current_dns)"
        else
            status="[!]"
            details=" (Using default DNS)"
        fi
    else
        status="[!]"
        details=" (resolved.conf not found)"
    fi
    
    echo "${status} DNS Configuration${details}"
}

# Function to configure DNS
configure_dns() {
    log_message "Configuring DNS..."
    
    # Backup original config
    if [ -f "/etc/systemd/resolved.conf" ]; then
        cp /etc/systemd/resolved.conf "/etc/systemd/resolved.conf.backup.$TIMESTAMP"
    fi
    
    echo "Enter DNS server IPs (space-separated, e.g., '8.8.8.8 8.8.4.4'):"
    read -r dns_servers
    
    # Validate DNS servers
    for ip in $dns_servers; do
        if ! [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${ERROR} Invalid IP address format: $ip"
            return 1
        fi
    done
    
    # Configure using systemd-resolved
    cat > /etc/systemd/resolved.conf <<EOF
[Resolve]
DNS=$dns_servers
FallbackDNS=1.1.1.1 9.9.9.9
DNSStubListener=yes
EOF
    
    # Restart systemd-resolved
    systemctl restart systemd-resolved
    
    # Also update netplan if it exists
    if [ -d "/etc/netplan" ]; then
        # Find the first netplan config file
        netplan_file=$(find /etc/netplan -name "*.yaml" | head -n 1)
        if [ -n "$netplan_file" ]; then
            # Backup netplan config
            cp "$netplan_file" "$netplan_file.backup.$TIMESTAMP"
            
            # Get interface name
            interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
            
            # Create new netplan config
            cat > "$netplan_file" <<EOF
network:
  version: 2
  ethernets:
    $interface:
      dhcp4: yes
      nameservers:
        addresses: [${dns_servers// /, }]
EOF
            
            # Apply netplan changes
            netplan apply
        fi
    fi
    
    log_message "DNS configuration completed with servers: $dns_servers"
    echo -e "${INFO} DNS configuration has been updated. Changes will take effect after a system restart."
    echo -e "${INFO} You can verify the new DNS settings with 'resolvectl status'"
}

# Function to check SSH configuration
check_ssh_config() {
    local status="[ ]"
    local details=""

    if ! command -v sshd >/dev/null; then
        echo "${status} SSH not installed"
        return 1
    fi

    local current_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    local root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    local password_auth=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

    if [ -n "$current_port" ] && [ -n "$root_login" ] && [ -n "$password_auth" ]; then
        status="[✓]"
        details=" (Port: $current_port, Root Login: $root_login, Password Auth: $password_auth)"
    else
        status="[!]"
        details=" (Needs configuration)"
    fi

    echo "${status} SSH Configuration${details}"
}

# Function to check firewall status
check_firewall() {
    local status="[ ]"
    local details=""

    if ! command -v ufw >/dev/null; then
        echo "${status} UFW not installed"
        return 1
    fi

    if ufw status | grep -q "Status: active"; then
        status="[✓]"
        # Use awk to get unique ports and sort them
        local open_ports=$(ufw status | grep ALLOW | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//')
        details=" (Active, Open ports: $open_ports)"
    else
        status="[!]"
        details=" (Installed but not active)"
    fi

    echo "${status} Firewall${details}"
}

# Function to check fail2ban status
check_fail2ban() {
    local status="[ ]"
    local details=""

    if ! command -v fail2ban-client >/dev/null; then
        echo "${status} Fail2ban not installed"
        return 1
    fi

    if systemctl is-active fail2ban >/dev/null 2>&1; then
        status="[✓]"
        local jails=$(fail2ban-client status | grep "Jail list" | cut -f2- -d:)
        details=" (Active, Jails:$jails)"
    else
        status="[!]"
        details=" (Installed but not active)"
    fi

    echo "${status} Fail2ban${details}"
}

# Function to check system optimization
check_system_optimization() {
    local status="[ ]"
    local details=""

    # Check timezone
    local timezone=$(timedatectl | grep "Time zone" | awk '{print $3}')
    
    # Check swap
    local swap_total=$(free -m | grep Swap | awk '{print $2}')
    
    # Check system limits
    local open_files_limit=$(ulimit -n)
    
    details=" (Timezone: $timezone, Swap: ${swap_total}MB, Open files limit: $open_files_limit)"
    
    if [ "$swap_total" -gt 0 ] && [ "$open_files_limit" -ge 65535 ]; then
        status="[✓]"
    else
        status="[!]"
    fi

    echo "${status} System Optimization${details}"
}

# Function to check monitoring setup
check_monitoring() {
    local status="[ ]"
    local details=""

    if [ -f "/usr/local/bin/system_monitor.sh" ]; then
        if systemctl is-active system-monitor >/dev/null 2>&1; then
            status="[✓]"
            details+=" (Active, Monitoring running)"
        else
            status="[!]"
            details+=" (Script installed but service not running)"
        fi
    else
        details+=" (Monitoring not installed)"
    fi

    echo "${status} Monitoring${details}"
}

# Function to configure SSH
configure_ssh() {
    log_message "Configuring SSH..."
    
    # If root is running the script and no other admin user exists
    if [ "$EUID" -eq 0 ] && [ -z "$(grep sudo /etc/group | cut -d: -f4)" ]; then
        echo -e "${WARN} Running as root with no other admin users. Creating admin user first..."
        create_admin_user
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} Failed to create admin user. Aborting SSH configuration"
            return 1
        }
        
        # Setup SSH keys for new admin user
        setup_ssh_keys "$admin_user"
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} Failed to setup SSH keys. Aborting SSH configuration"
            return 1
        }
        
        # Verify SSH access before proceeding
        verify_ssh_access "$admin_user"
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} SSH verification failed. Aborting remaining configuration"
            return 1
        }
    fi
    
    # Backup original config
    cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.$TIMESTAMP"
    
    # Set secure SSH configuration
    {
        echo "Port 2222"
        echo "PermitRootLogin no"
        echo "PasswordAuthentication no"
        echo "X11Forwarding no"
        echo "MaxAuthTries 3"
        echo "PubkeyAuthentication yes"
        echo "Protocol 2"
        echo "AllowUsers $admin_user" # Only allow the admin user
    } > /etc/ssh/sshd_config
    
    systemctl restart sshd
    log_message "SSH configured successfully"
    
    echo -e "${INFO} SSH has been configured with the following settings:"
    echo -e "- Port: 2222"
    echo -e "- Root login disabled"
    echo -e "- Password authentication disabled"
    echo -e "- Only key-based authentication allowed"
    echo -e "- Only $admin_user can SSH"
    echo -e "\n${WARN} Make sure to save the following SSH command for future access:"
    echo -e "ssh -p 2222 $admin_user@$(curl -s ifconfig.me)"
}

# Function to configure firewall
configure_firewall() {
    log_message "Configuring firewall..."
    
    # Install UFW if not present
    apt-get install -y ufw
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (on custom port if configured)
    ufw allow 2222/tcp
    
    # Allow HTTP/HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    echo "y" | ufw enable
    
    log_message "Firewall configured successfully"
}

# Function to check installed applications
check_applications() {
    local status="[ ]"
    local details=""
    
    # List of common server applications to check
    declare -A apps=(
        ["nginx"]="Web Server"
        ["docker"]="Container Runtime"
        ["postgresql"]="Database"
        ["redis-server"]="Cache"
        ["nodejs"]="Runtime"
        ["python3"]="Runtime"
    )
    
    local installed_count=0
    local installed_apps=""
    
    for app in "${!apps[@]}"; do
        if command -v "$app" >/dev/null 2>&1 || systemctl list-units --full -all | grep -Fq "$app"; then
            installed_count=$((installed_count + 1))
            installed_apps+="${app}, "
        fi
    done
    
    if [ $installed_count -gt 0 ]; then
        status="[✓]"
        # Remove trailing comma and space
        installed_apps=$(echo "$installed_apps" | sed 's/, $//')
        details=" ($installed_count/${#apps[@]} installed: $installed_apps)"
    else
        status="[!]"
        details=" (No applications installed)"
    fi
    
    echo "${status} Applications${details}"
}

# Function to install applications
install_applications() {
    log_message "Starting application installation..."
    
    # Define available applications
    declare -A available_apps=(
        ["1"]="nginx|Web Server"
        ["2"]="docker.io|Container Runtime"
        ["3"]="postgresql|Database Server"
        ["4"]="redis-server|Cache Server"
        ["5"]="python3|Python Runtime"
    )
    
    while true; do
        clear
        echo "=== Application Installation ==="
        echo "Available applications:"
        echo ""
        
        # Display available applications
        for key in "${!available_apps[@]}"; do
            local app_info=(${available_apps[$key]//|/ })
            local app_name=${app_info[0]}
            local app_desc=${app_info[1]}
            
            if command -v "$app_name" >/dev/null 2>&1 || systemctl list-units --full -all | grep -Fq "$app_name"; then
                echo -e "${key}) ${app_name} (${app_desc}) ${GREEN}[Installed]${NC}"
            else
                echo "${key}) ${app_name} (${app_desc})"
            fi
        done
        
        echo ""
        echo "a) Install All"
        echo "b) Back to main menu"
        
        read -r -p "Select application to install [1-6, a, b]: " app_choice
        
        case $app_choice in
            [1-6])
                local app_info=(${available_apps[$app_choice]//|/ })
                local app_name=${app_info[0]}
                log_message "Installing $app_name..."
                apt-get install -y "$app_name"
                log_message "$app_name installation completed"
                ;;
            a)
                log_message "Installing all applications..."
                for app_info in "${available_apps[@]}"; do
                    local app_name=(${app_info//|/ })[0]
                    apt-get install -y "$app_name"
                done
                log_message "All applications installed"
                ;;
            b)
                break
                ;;
            *)
                echo "Invalid selection"
                sleep 2
                ;;
        esac
    done
}

check_nvm() {
    local status="[ ]"
    local details=""

    if [ -d "$HOME/.nvm" ]; then
        # Source NVM if it exists
        [ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
        
        if command -v nvm >/dev/null; then
            status="[✓]"
            local node_version=$(node -v 2>/dev/null || echo "none")
            local npm_version=$(npm -v 2>/dev/null || echo "none")
            details=" (Node ${node_version}, npm ${npm_version})"
        else
            status="[!]"
            details=" (NVM installed but not loaded)"
        fi
    else
        details=" (NVM not installed)"
    fi

    echo "${status} Node.js (NVM)${details}"
}

# Function to check PM2 installation
check_pm2() {
    local status="[ ]"
    local details=""

    if command -v pm2 >/dev/null; then
        status="[✓]"
        local pm2_version=$(pm2 -v 2>/dev/null || echo "unknown")
        details=" (Version: ${pm2_version})"
        
        # Check if PM2 startup is configured
        if systemctl list-unit-files | grep -q "pm2-"; then
            details+=" [Startup configured]"
        fi
    else
        details=" (PM2 not installed)"
    fi

    echo "${status} PM2${details}"
}

# Function to install NVM and Node.js
install_nvm() {
    log_message "Installing NVM and Node.js..."
    
    # Install dependencies
    apt-get install -y curl git

    # Download and run the NVM installation script for root
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Source NVM
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Add NVM to root's bash profile
    echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.bashrc"
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm' >> "$HOME/.bashrc"
    
    # Install latest LTS version of Node.js
    nvm install --lts
    nvm use --lts
    
    # Set default Node.js version
    nvm alias default 'lts/*'
    
    # Create a system-wide node command
    ln -sf "$NVM_DIR/versions/node/$(nvm version)/bin/node" /usr/local/bin/node
    ln -sf "$NVM_DIR/versions/node/$(nvm version)/bin/npm" /usr/local/bin/npm
    
    log_message "NVM and Node.js installation completed"
    echo -e "${INFO} NVM $(nvm --version) installed"
    echo -e "${INFO} Node.js $(node -v) installed"
    echo -e "${INFO} npm $(npm -v) installed"
}

# Function to install and configure PM2
install_pm2() {
    log_message "Installing and configuring PM2..."
    
    # Check if Node.js is installed
    if ! command -v node >/dev/null; then
        echo -e "${ERROR} Node.js is required for PM2. Please install Node.js first."
        return 1
    fi
    
    # Install PM2 globally
    npm install -g pm2
    
    # Create directory for Node.js applications
    mkdir -p /var/www/nodejs
    chown -R www-data:www-data /var/www/nodejs
    
    # Setup PM2 to start on boot with the www-data user
    pm2 startup systemd -u www-data --hp /var/www/nodejs
    
    # Create PM2 ecosystem file
    cat > /var/www/nodejs/ecosystem.config.js <<EOL
module.exports = {
  apps: [{
    name: 'app',
    script: 'npm',
    args: 'start',
    cwd: '/var/www/nodejs/current',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production'
    }
  }]
};
EOL
    
    # Set proper ownership
    chown www-data:www-data /var/www/nodejs/ecosystem.config.js
    
    log_message "PM2 installation completed"
    echo -e "${INFO} PM2 $(pm2 -v) installed and configured"
    echo -e "${INFO} PM2 startup configured for www-data user"
    echo -e "${INFO} Default ecosystem file created at /var/www/nodejs/ecosystem.config.js"
}

# Function to check PostgreSQL configuration
check_postgres_config() {
    local status="[ ]"
    local details=""
    
    if ! command -v psql >/dev/null; then
        echo "${status} PostgreSQL not installed"
        return 1
    fi
    
    if systemctl is-active postgresql >/dev/null 2>&1; then
        status="[✓]"
        # Get version without connecting to database
        local version=$(pg_config --version 2>/dev/null | awk '{print $2}')
        # Try to get port from config file
        local pg_version=$(ls /etc/postgresql/ 2>/dev/null | sort -V | tail -n1)
        if [ -n "$pg_version" ]; then
            local port=$(grep "^port =" "/etc/postgresql/$pg_version/main/postgresql.conf" 2>/dev/null | awk '{print $3}')
            details=" (Version: $version, Port: ${port:-5432})"
        else
            details=" (Version: $version, Port: 5432)"
        fi
    else
        status="[!]"
        details=" (Service not running)"
    fi
    
    echo "${status} PostgreSQL${details}"
}

# Function to check Redis configuration
check_redis_config() {
    local status="[ ]"
    local details=""
    
    if ! command -v redis-cli >/dev/null; then
        echo "${status} Redis not installed"
        return 1
    fi
    
    if systemctl is-active redis-server >/dev/null 2>&1; then
        status="[✓]"
        local version=$(redis-server --version | awk '{print $3}' | cut -d= -f2)
        # Get port from config file instead of connecting
        local port=$(grep "^port " /etc/redis/redis.conf 2>/dev/null | awk '{print $2}')
        details=" (Version: $version, Port: ${port:-6379})"
    else
        status="[!]"
        details=" (Service not running)"
    fi
    
    echo "${status} Redis${details}"
}

# Function to configure PostgreSQL
configure_postgres() {
    log_message "Configuring PostgreSQL..."
    
    # Install PostgreSQL if not present
    if ! command -v psql >/dev/null; then
        apt-get install -y postgresql postgresql-contrib
    fi
    
    # Get PostgreSQL version
    local pg_version=$(pg_config --version | awk '{print $2}' | cut -d. -f1)
    
    # Stop PostgreSQL and ensure it's fully stopped
    systemctl stop postgresql
    pkill postgres || true
    sleep 2
    
    # Remove any existing cluster completely
    if pg_lsclusters | grep -q "main"; then
        pg_dropcluster ${pg_version} main --stop || true
    fi
    
    # Clean up PostgreSQL directories to ensure fresh start
    rm -rf /var/lib/postgresql/${pg_version}/main
    rm -rf /etc/postgresql/${pg_version}/main
    mkdir -p /var/lib/postgresql/${pg_version}
    mkdir -p /etc/postgresql/${pg_version}
    
    # Set correct ownership
    chown -R postgres:postgres /var/lib/postgresql
    chown -R postgres:postgres /etc/postgresql
    
    # Create new cluster without starting it
    pg_createcluster ${pg_version} main --start-conf=manual
    
    # Get configuration file paths
    local pg_conf="/etc/postgresql/$pg_version/main/postgresql.conf"
    local pg_hba="/etc/postgresql/$pg_version/main/pg_hba.conf"
    local data_dir="/var/lib/postgresql/$pg_version/main"
    
    # Wait for files to be created
    sleep 2
    
    # Verify directory structure
    if [ ! -d "$data_dir" ]; then
        echo -e "${ERROR} Data directory $data_dir not created"
        return 1
    fi
    
    # Configure postgresql.conf
    if [ -f "$pg_conf" ]; then
        # Backup original config
        cp "$pg_conf" "${pg_conf}.backup.$TIMESTAMP"
        
        # Configure postgresql.conf
        cat > "$pg_conf" <<EOF
# DB Version: $pg_version
# OS Type: linux
listen_addresses = 'localhost'
port = 5432
max_connections = 100
shared_buffers = 128MB
dynamic_shared_memory_type = posix
max_wal_size = 1GB
min_wal_size = 80MB
log_timezone = 'UTC'
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'C'
lc_monetary = 'C'
lc_numeric = 'C'
lc_time = 'C'
default_text_search_config = 'pg_catalog.english'
EOF
    else
        echo -e "${ERROR} postgresql.conf not found at $pg_conf"
        return 1
    fi

    # Configure pg_hba.conf
    if [ -f "$pg_hba" ]; then
        # Backup original config
        cp "$pg_hba" "${pg_hba}.backup.$TIMESTAMP"
        
        # Configure pg_hba.conf
        cat > "$pg_hba" <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all            postgres                                peer
local   all            all                                     peer
host    all            all             127.0.0.1/32            scram-sha-256
host    all            all             ::1/128                 scram-sha-256
EOF
    else
        echo -e "${ERROR} pg_hba.conf not found at $pg_hba"
        return 1
    fi

    # Double check permissions
    chown -R postgres:postgres /etc/postgresql
    chown -R postgres:postgres /var/lib/postgresql
    chmod 700 "$data_dir"
    
    # Start PostgreSQL service
    systemctl start postgresql
    
    # Wait for PostgreSQL to start and verify
    echo -n "Waiting for PostgreSQL to start"
    for i in {1..30}; do
        if pg_lsclusters | grep -q "online"; then
            echo " done!"
            log_message "PostgreSQL configured successfully"
            echo -e "${INFO} PostgreSQL has been configured with secure defaults"
            echo -e "${INFO} PostgreSQL cluster is running properly"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    
    echo -e "\n${ERROR} PostgreSQL failed to start after 30 seconds"
    echo "Recent logs:"
    tail -n 20 /var/log/postgresql/postgresql-${pg_version}-main.log
    return 1
}

# Function to configure Redis
configure_redis() {
    log_message "Configuring Redis..."
    
    # Install Redis if not present
    if ! command -v redis-cli >/dev/null; then
        apt-get install -y redis-server
    fi
    
    # Backup original config
    cp /etc/redis/redis.conf "/etc/redis/redis.conf.backup.$TIMESTAMP"
    
    # Generate a strong Redis password
    redis_pass=$(openssl rand -base64 32)
    
    # Configure redis.conf with secure defaults
    cat > /etc/redis/redis.conf <<EOF
# Basic Settings
port 6379
bind 127.0.0.1
daemonize yes
supervised systemd

# Security
requirepass $redis_pass
rename-command FLUSHALL ""
rename-command FLUSHDB ""
rename-command DEBUG ""
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000
rdbcompression yes
dbfilename dump.rdb
dir /var/lib/redis

# Logging
logfile /var/log/redis/redis-server.log
loglevel notice

# Performance Tuning
maxclients 10000
timeout 300
tcp-keepalive 300
EOF

    # Create log directory if it doesn't exist
    mkdir -p /var/log/redis
    chown redis:redis /var/log/redis
    
    # Save Redis password
    echo "Redis Password: $redis_pass" > /root/.redis_credentials
    chmod 600 /root/.redis_credentials
    
    # Restart Redis
    systemctl restart redis-server
    
    log_message "Redis configured successfully"
    echo -e "${INFO} Redis password saved to /root/.redis_credentials"
}

# Function to configure fail2ban
configure_fail2ban() {
    log_message "Configuring fail2ban..."
    
    apt-get install -y fail2ban
    
    # Create local jail configuration
    cat > /etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_message "Fail2ban configured successfully"
}

# Function to optimize system
configure_system_optimization() {
    log_message "Optimizing system..."
    
    # Set timezone to UTC
    timedatectl set-timezone UTC
    
    # Configure swap
    if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    # Configure system limits
    cat > /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
EOF

    # Configure sysctl parameters
    cat > /etc/sysctl.d/99-sysctl-custom.conf <<EOF
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
EOF
    
    sysctl -p /etc/sysctl.d/99-sysctl-custom.conf
    
    log_message "System optimization completed"
}

# Function to setup monitoring
configure_monitoring() {
    log_message "Setting up monitoring..."
    
    # Create monitoring script
    cat > /usr/local/bin/system_monitor.sh <<'EOF'
#!/bin/bash

# Configuration
LOG_DIR="/var/log/system-monitor"
ALERT_EMAIL="root@localhost"  # Change this to your email
THRESHOLD_CPU=80  # CPU threshold percentage
THRESHOLD_MEM=80  # Memory threshold percentage
THRESHOLD_DISK=80  # Disk threshold percentage

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Function to get CPU usage
get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1
}

# Function to get memory usage
get_memory_usage() {
    free | grep Mem | awk '{print int($3/$2 * 100)}'
}

# Function to get disk usage
get_disk_usage() {
    df -h / | awk 'NR==2 {print int($5)}'
}

# Function to get system load
get_system_load() {
    uptime | awk -F'load average:' '{ print $2 }' | tr -d ' '
}

# Function to send alert
send_alert() {
    local subject="$1"
    local message="$2"
    echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
    logger -t system-monitor "$subject: $message"
}

# Main monitoring function
monitor_system() {
    # Get current values
    CPU_USAGE=$(get_cpu_usage)
    MEM_USAGE=$(get_memory_usage)
    DISK_USAGE=$(get_disk_usage)
    SYSTEM_LOAD=$(get_system_load)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Log current status
    echo "$TIMESTAMP - CPU: $CPU_USAGE%, MEM: $MEM_USAGE%, DISK: $DISK_USAGE%, LOAD: $SYSTEM_LOAD" >> "$LOG_DIR/status.log"

    # Check thresholds and send alerts
    if [ "$CPU_USAGE" -gt "$THRESHOLD_CPU" ]; then
        send_alert "High CPU Usage" "CPU usage is at $CPU_USAGE%"
    fi

    if [ "$MEM_USAGE" -gt "$THRESHOLD_MEM" ]; then
        send_alert "High Memory Usage" "Memory usage is at $MEM_USAGE%"
    fi

    if [ "$DISK_USAGE" -gt "$THRESHOLD_DISK" ]; then
        send_alert "High Disk Usage" "Disk usage is at $DISK_USAGE%"
    fi
}

# Run monitoring
monitor_system
EOF

    # Make script executable
    chmod +x /usr/local/bin/system_monitor.sh

    # Create systemd service
    cat > /etc/systemd/system/system-monitor.service <<EOF
[Unit]
Description=System Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/system_monitor.sh; sleep 300; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Create log rotation configuration
    cat > /etc/logrotate.d/system-monitor <<EOF
/var/log/system-monitor/status.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable system-monitor
    systemctl start system-monitor
    
    log_message "Monitoring setup completed"
}

# Main menu function
show_menu() {
    clear
    echo "=== Ubuntu Server Setup ==="
    echo "Current System Status:"
    echo ""
    
    check_ssh_config
    check_firewall
    check_fail2ban
    check_system_optimization
    check_monitoring
    check_applications
    check_dns_config
    check_postgres_config
    check_redis_config
    check_nvm
    check_pm2

    echo ""
    echo "Select options to configure:"
    echo ""
    echo "1) Security Hardening (SSH, Firewall, Fail2ban)"
    echo "2) System Optimization"
    echo "3) Monitoring Setup"
    echo "4) Install Applications"
    echo "5) Configure DNS"
    echo "6) Configure PostgreSQL"
    echo "7) Configure Redis"
    echo "8) Install Node.js (using NVM)"
    echo "9) Install & Configure PM2"
    echo "10) Run All Checks"
    echo "11) Configure All"
    echo "q) Quit"
    
    read -r -p "Enter selection [1-11 or q]: " selection
    echo "You selected: $selection"
    
    # Add debug output
    echo "Debug: Selection entered: $selection"
    
    case $selection in
        1)
            configure_ssh
            configure_firewall
            configure_fail2ban
            ;;
        2)
            configure_system_optimization
            ;;
        3)
            configure_monitoring
            ;;
        4)
            install_applications
            ;;
        5)
            configure_dns
            ;;
        6)
            configure_postgres
            ;;
        7)
            configure_redis
            ;;
        8)
            install_nvm
            ;;
        9)
            install_pm2
            ;;
        10)
            check_ssh_config
            check_firewall
            check_fail2ban
            check_system_optimization
            check_monitoring
            check_applications
            check_dns_config
            check_postgres_config
            check_redis_config
            check_nvm
            check_pm2
            read -p "Press enter to continue..."
            ;;
        11)
            configure_ssh
            configure_firewall
            configure_fail2ban
            configure_system_optimization
            configure_monitoring
            install_applications
            configure_dns
            configure_postgres
            configure_redis
            install_nvm
            install_pm2
            ;;
        q)
            exit 0
            ;;
        *)
            echo "Invalid selection"
            ;;
    esac
}

# Main script execution
main() {
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    
    # Update system
    log_message "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    
    while true; do
        show_menu
    done
}

main "$@"
