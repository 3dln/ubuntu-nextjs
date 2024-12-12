# Ubuntu Next.js Server Setup Scripts 🚀

A collection of shell scripts to automate the setup and deployment of Next.js applications on Ubuntu servers. These scripts handle everything from initial server setup to SSL configuration.

## 📦 Features

- Complete Ubuntu server setup for Next.js hosting
- Automated Node.js and npm installation
- PM2 process management configuration
- Nginx setup and configuration
- UFW firewall setup
- SSH key generation for GitHub
- SSL/TLS certificate installation with Let's Encrypt
- Automated deployment and updates
- Domain configuration

## 🛠️ Scripts

### 1. `setup.sh`

Initial server setup script that:

- Updates system packages
- Installs Node.js, npm, and essential tools
- Sets up PM2 for process management
- Configures Nginx
- Sets up UFW firewall
- Generates SSH key for GitHub

### 2. `deploy.sh`

Deployment script that:

- Clones your Next.js repository
- Installs dependencies
- Builds the application
- Configures PM2
- Updates Nginx settings
- Sets up environment variables

### 3. `update.sh`

Update script that:

- Pulls latest changes from Git
- Handles dependency updates
- Rebuilds the application
- Manages PM2 processes
- Maintains environment settings

### 4. `setup-domain.sh`

Domain and SSL setup script that:

- Configures domain settings
- Installs SSL certificates using Let's Encrypt
- Updates Nginx configuration
- Sets up automatic SSL renewal
- Configures security headers

## 🚀 Getting Started

1. Clone this repository:

```bash
git clone https://github.com/yourusername/ubuntu-nextjs-setup.git
cd ubuntu-nextjs-setup
```

2. Make scripts executable:

```bash
chmod +x *.sh
```

3. Run the initial setup:

```bash
sudo ./setup.sh
```

4. Deploy your application:

```bash
./deploy.sh
```

## 📋 Prerequisites

- Ubuntu 24.04 LTS server
- Root or sudo access
- Domain name (for SSL setup)
- GitHub repository with your Next.js project

## ⚙️ Usage

### Initial Server Setup

```bash
sudo ./setup.sh
```

### Deploy Application

```bash
./deploy.sh
```

### Update Application

```bash
./update.sh
```

### Configure Domain and SSL

```bash
sudo ./setup-domain.sh
```

## 🔒 Security Features

- UFW firewall configuration
- Secure Nginx settings
- SSL/TLS certification
- Security headers
- PM2 process management
- Automated updates

## 📝 Environment Variables

The scripts handle the following environment variables:

- `PORT`: Application port (default: 3000)
- Additional variables can be added to `.env`

## 🔄 Automatic Updates

The update script can be scheduled using cron for automatic updates:

```bash
# Example: Update every day at 2 AM
0 2 * * * /path/to/update.sh >> /var/log/nextjs-update.log 2>&1
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Note

- Always backup your data before running scripts
- Test in a staging environment first
- Update script parameters according to your needs
- Keep your system and packages updated

## 🐛 Troubleshooting

Common issues and solutions:

1. **PM2 Process Not Found**

   - Solution: The update script will automatically create a new PM2 process if none exists

2. **Nginx Configuration Errors**

   - Solution: Check nginx error logs: `sudo nginx -t`

3. **SSL Certificate Issues**
   - Solution: Ensure correct domain DNS settings
   - Verify Certbot logs: `sudo certbot certificates`

## 📫 Support

For support, please open an issue in the GitHub repository.
