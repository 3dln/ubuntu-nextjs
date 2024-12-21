#!/bin/bash

# Ubuntu Server Setup Script
# This script provides an interactive setup for Ubuntu Server with system checks
# Version: 1.0

set -euo pipefail

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
        local open_ports=$(ufw status | grep ALLOW | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
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

    # Check Prometheus
    if systemctl is-active prometheus >/dev/null 2>&1; then
        status="[✓]"
        details+=" Prometheus:Running"
    elif command -v prometheus >/dev/null; then
        status="[P]"
        details+=" Prometheus:Installed"
    else
        details+=" Prometheus:Not installed"
    fi

    # Check Node Exporter
    if systemctl is-active node_exporter >/dev/null 2>&1; then
        details+=", Node Exporter:Running"
    elif command -v node_exporter >/dev/null; then
        status="[P]"
        details+=", Node Exporter:Installed"
    else
        details+=", Node Exporter:Not installed"
    fi

    echo "${status} Monitoring${details}"
}

# Function to configure SSH
configure_ssh() {
    log_message "Configuring SSH..."
    
    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup."$TIMESTAMP"
    
    # Set secure SSH configuration
    {
        echo "Port 2222"
        echo "PermitRootLogin no"
        echo "PasswordAuthentication no"
        echo "X11Forwarding no"
        echo "MaxAuthTries 3"
        echo "PubkeyAuthentication yes"
        echo "Protocol 2"
    } >> /etc/ssh/sshd_config

    systemctl restart sshd
    log_message "SSH configured successfully"
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
    
    # Install Prometheus
    apt-get install -y prometheus
    
    # Install Node Exporter
    apt-get install -y prometheus-node-exporter
    
    # Configure Prometheus
    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF

    systemctl enable prometheus
    systemctl restart prometheus
    
    systemctl enable prometheus-node-exporter
    systemctl restart prometheus-node-exporter
    
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
    
    echo ""
    echo "Select options to configure:"
    echo "1) Security Hardening (SSH, Firewall, Fail2ban)"
    echo "2) System Optimization"
    echo "3) Monitoring Setup"
    echo "4) Run All Checks"
    echo "5) Configure All"
    echo "q) Quit"
    
    read -p "Enter selection [1-5 or q]: " selection
    
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
            check_ssh_config
            check_firewall
            check_fail2ban
            check_system_optimization
            check_monitoring
            read -p "Press enter to continue..."
            ;;
        5)
            configure_ssh
            configure_firewall
            configure_fail2ban
            configure_system_optimization
            configure_monitoring
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
