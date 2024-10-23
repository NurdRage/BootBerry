#!/bin/bash
# Automated script to set up Raspberry Pi 5 as a PXE Boot Server for Windows 11 installation on a Victus by HP Gaming Laptop 15-fbf1013dx

set -e

# Configuration
RETRY_COUNT=3
RETRY_INTERVAL=5
DRY_RUN=false

# Password check for additional options
echo "Please enter the password to continue:"
read -s PASSWORD
if [ "$PASSWORD" != "Kwirky" ]; then
  echo "[ERROR] Incorrect password. Exiting..."
  exit 1
fi

# Option to enable DRY_RUN
echo "Would you like to perform a dry run? (y/N)"
read -r DRY_RUN_OPTION
if [[ "$DRY_RUN_OPTION" =~ ^[Yy]$ ]]; then
  DRY_RUN=true
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Please run as root or use sudo"
  exit 1
fi

# Logging setup
LOG_FILE="/var/log/pxe_setup.log"
if command -v ts > /dev/null 2>&1; then
    exec > >(ts '[%Y-%m-%d %H:%M:%S]' | tee -a "$LOG_FILE") 2>&1
else
    echo '[WARNING] moreutils is not installed. Logging without timestamp.'
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

# Set log file permissions
sudo chmod 600 "$LOG_FILE"

# Log rotation setup to prevent log file from growing indefinitely
LOG_MAX_SIZE=10485760  # 10MB
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -ge $LOG_MAX_SIZE ]; then
    mv "$LOG_FILE" "$LOG_FILE.bak"
    echo "[INFO] Log file size exceeded limit. Rotated to $LOG_FILE.bak." | tee -a "$LOG_FILE"
fi

# Rollback function to undo changes in case of failure
installed_packages=()
rollback() {
    echo "[ERROR] An error occurred. Rolling back changes..."
    sudo systemctl stop dnsmasq smbd tftpd-hpa
    [ -d "$TFTP_DIR" ] && sudo rm -rf "$TFTP_DIR"
    [ -d "$SAMBA_DIR" ] && sudo rm -rf "$SAMBA_DIR"
    for pkg in "${installed_packages[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" | grep -q "installed"; then
            sudo apt purge -y "$pkg"
        fi
    done
    echo "[INFO] Rollback complete. Exiting..."
    exit 1
}

trap rollback ERR

# Utility function for downloading and validating files
download_and_validate_iso() {
    local url="$1"
    local file="$2"
    local checksum="$3"
    retry_count=0
    while [ $retry_count -lt $RETRY_COUNT ]; do
        if [ "$DRY_RUN" = true ]; then
            echo "[DRY-RUN] gdown \"$url\" -O \"$file\""
            echo "[DRY-RUN] Checksum verification for $file"
            return 0
        else
            gdown "$url" -O "$file" && \
            calculated_checksum=$(sha256sum "$file" | awk '{print $1}')
            if [ "$calculated_checksum" == "$checksum" ]; then
                echo "[INFO] Checksum verification successful."
                return 0
            else
                echo "[WARNING] Checksum verification failed. Expected: $checksum, Got: $calculated_checksum. Retrying ($retry_count/$RETRY_COUNT)..."
                rm -f "$file"
            fi
        fi
        retry_count=$((retry_count + 1))
        sleep $RETRY_INTERVAL
    done
    echo "[ERROR] Download or checksum validation failed after $RETRY_COUNT attempts. Exiting..."
    echo "[ERROR] Please verify the URL or network connection." | tee -a "$LOG_FILE"
    exit 1
}

# Update system with retry mechanism
update_system() {
    echo "[INFO] Updating system..."
    retry_count=0
    until sudo apt update && sudo apt upgrade -y && \
    sudo apt install -y dnsmasq tftpd-hpa samba wget moreutils ufw python3-pip; do
        retry_count=$((retry_count + 1))
        echo "[WARNING] Package installation failed. Retrying ($retry_count/$RETRY_COUNT)..."
        sleep $RETRY_INTERVAL
    done
    if [ $retry_count -eq $RETRY_COUNT ]; then
        echo "[ERROR] Failed to install necessary packages after $RETRY_COUNT attempts. Exiting..."
        exit 1
    fi
    installed_packages+=(dnsmasq tftpd-hpa samba wget moreutils ufw python3-pip)

    # Install gdown using pip
    echo "[INFO] Installing gdown..."
    pip3 install gdown
}

if [ "$DRY_RUN" = false ]; then
    update_system
else
    echo "[DRY-RUN] System update, package installation, and gdown installation."
fi

# Set up TFTP directory
TFTP_DIR="/srv/tftp"
echo "[INFO] Setting up TFTP directory at $TFTP_DIR..."
if [ "$DRY_RUN" = false ]; then
    sudo mkdir -p "$TFTP_DIR"
    sudo chmod -R 755 "$TFTP_DIR"
else
    echo "[DRY-RUN] sudo mkdir -p \"$TFTP_DIR\""
    echo "[DRY-RUN] sudo chmod -R 755 \"$TFTP_DIR\""
fi

# Set up Samba share for Windows installation files
SAMBA_DIR="/srv/samba"
echo "[INFO] Setting up Samba directory at $SAMBA_DIR..."
if [ "$DRY_RUN" = false ]; then
    sudo mkdir -p "$SAMBA_DIR"
    sudo chmod -R 755 "$SAMBA_DIR"
else
    echo "[DRY-RUN] sudo mkdir -p \"$SAMBA_DIR\""
    echo "[DRY-RUN] sudo chmod -R 755 \"$SAMBA_DIR\""
fi

# Set Samba password non-interactively for full automation
echo "[INFO] Setting Samba password for user 'pxeuser'..."
SAMBA_PASSWORD=$(openssl rand -base64 12)  # Use a strong, random password
echo "Please enter a password for Samba user 'pxeuser':"
read -s SAMBA_PASSWORD
if [ -z "$SAMBA_PASSWORD" ]; then
    echo "[ERROR] Password cannot be empty. Exiting..."
    exit 1
fi
echo -e "$SAMBA_PASSWORD
$SAMBA_PASSWORD" | sudo smbpasswd -s -a pxeuser

# Save Samba password securely
SAMBA_PASS_FILE="/root/pxe_samba_password.txt"
echo "[INFO] Saving Samba password to $SAMBA_PASS_FILE..."
echo "Samba user 'pxeuser' password: $SAMBA_PASSWORD" | sudo tee "$SAMBA_PASS_FILE"
sudo chmod 600 "$SAMBA_PASS_FILE"

# Configure firewall with retry mechanism
configure_firewall() {
    echo "[INFO] Configuring firewall rules..."
    retry_count=0
    until sudo ufw allow 69/udp && sudo ufw allow 445/tcp && sudo ufw allow 67:68/udp && sudo ufw default deny incoming && sudo ufw enable || [ $retry_count -ge $RETRY_COUNT ]; do
        retry_count=$((retry_count + 1))
        echo "[WARNING] Firewall configuration failed. Retrying ($retry_count/$RETRY_COUNT)..."
        sleep $RETRY_INTERVAL
    done
    if [ $retry_count -eq $RETRY_COUNT ]; then
        echo "[ERROR] Failed to configure firewall after $RETRY_COUNT attempts. Exiting..."
        exit 1
    fi
}

if [ "$DRY_RUN" = false ]; then
    configure_firewall
else
    echo "[DRY-RUN] Configuring firewall rules."
fi

# Check for active internet connection with retries
check_internet_connection() {
    echo "[INFO] Checking for active internet connection..."
    retry_count=0
    until ping -c 1 ${TEST_HOST:-google.com} > /dev/null 2>&1 || ping -c 1 ${TEST_HOST:-8.8.8.8} > /dev/null 2>&1 || [ $retry_count -ge $RETRY_COUNT ]; do
        retry_count=$((retry_count + 1))
        echo "[WARNING] No active internet connection. Retrying ($retry_count/$RETRY_COUNT)..."
        sleep $RETRY_INTERVAL
    done
    if [ $retry_count -eq $RETRY_COUNT ]; then
        echo "[ERROR] No active internet connection after $RETRY_COUNT attempts. Exiting..."
        exit 1
    fi
}

if [ "$DRY_RUN" = false ]; then
    check_internet_connection
else
    echo "[DRY-RUN] Checking for active internet connection."
fi

# Set static IP for Raspberry Pi
STATIC_IP="192.168.99.1"
echo "[INFO] Configuring static IP address $STATIC_IP for network interface eth0..."
if [ "$DRY_RUN" = false ]; then
    cat <<EOL | sudo tee /etc/dhcpcd.conf
interface eth0
static ip_address=$STATIC_IP/24
EOL
    sudo systemctl restart dhcpcd
else
    echo "[DRY-RUN] Configure static IP for eth0 to $STATIC_IP."
fi

# Verify static IP configuration with retries
verify_static_ip() {
    echo "[INFO] Verifying static IP configuration..."
    retry_count=0
    until ip -4 addr show eth0 | grep -q "$STATIC_IP" || [ $retry_count -ge $RETRY_COUNT ]; do
        retry_count=$((retry_count + 1))
        echo "[WARNING] Failed to set static IP address. Retrying ($retry_count/$RETRY_COUNT)..."
        if [ "$DRY_RUN" = false ]; then
            sudo systemctl restart dhcpcd
        else
            echo "[DRY-RUN] Restart dhcpcd service."
        fi
        sleep $RETRY_INTERVAL
    done
    if [ $retry_count -eq $RETRY_COUNT ]; then
        echo "[ERROR] Failed to set static IP address after $RETRY_COUNT attempts. Exiting..."
        exit 1
    fi
}

if [ "$DRY_RUN" = false ]; then
    verify_static_ip
else
    echo "[DRY-RUN] Verifying static IP configuration."
fi

# Preselect network interface for PXE boot
interfaces=$(ip link | awk -F: '$0 !~ "lo|vir|wl|docker|^[^0-9]"{print $2; getline}' | xargs)
interface_list=($interfaces)

if [ ${#interface_list[@]} -gt 1 ]; then
    echo "[INFO] Multiple network interfaces detected. Please select the interface to use:"
    select INTERFACE in "${interface_list[@]}"; do
        if [ -n "$INTERFACE" ]; then
            echo "[INFO] Selected network interface: $INTERFACE"
            break
        else
            echo "[ERROR] Invalid selection. Please try again."
        fi
    done
else
    if [ -z "$INTERFACE" ]; then
    INTERFACE=${interface_list[0]}
    echo "[INFO] Auto-selected network interface: $INTERFACE"
fi
# Validate selected interface
echo "[INFO] Validating selected network interface: $INTERFACE"
if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    echo "[ERROR] Selected network interface $INTERFACE is not valid. Exiting..."
    exit 1
fi
    echo "[INFO] Using network interface: $INTERFACE"
fi

# Add automatic selection fallback
timeout=10
echo "[INFO] Auto-selecting network interface in $timeout seconds if no selection is made..."
SECONDS=0
while [ $SECONDS -lt $timeout ]; do
    if [ "$INTERFACE" ]; then
        break
    fi
    sleep 1
done
if [ -z "$INTERFACE" ]; then
    INTERFACE=${interface_list[0]}
    echo "[INFO] Auto-selected network interface: $INTERFACE"
fi

# Predefined IP range for DHCP configuration
DHCP_RANGE="192.168.99.10,192.168.99.100,12h"

# Download Windows 11 ISO from Google Drive
echo "[INFO] Downloading Windows 11 ISO from Google Drive..."
GDRIVE_URL="https://drive.google.com/uc?export=download&id=1xXEsI-O5bHzjS4g_DTAAolwhqLd-Aq_s"
ISO_FILE="$SAMBA_DIR/win11.iso"
EXPECTED_CHECKSUM="b56b911bf18a2ceaeb3904d87e7c770bdf92d3099599d61ac2497b91bf190b11"
download_and_validate_iso "$GDRIVE_URL" "$ISO_FILE" "$EXPECTED_CHECKSUM"

# Configure dnsmasq for DHCP and TFTP
echo "[INFO] Configuring dnsmasq for DHCP and TFTP..."
cat <<EOL | sudo tee /etc/dnsmasq.conf
# Configuring dnsmasq for PXE boot
interface=$INTERFACE
bind-interfaces
dhcp-range=$DHCP_RANGE
log-queries
log-dhcp
enable-tftp
tftp-root=$TFTP_DIR
EOL

# Restart dnsmasq to apply the new configuration
restart_service_with_retries() {
    local service_name="$1"
    retry_count=0
    echo "[INFO] Restarting $service_name..."
    while ! sudo systemctl is-active --quiet "$service_name" && [ $retry_count -lt $RETRY_COUNT ]; do
        if [ "$DRY_RUN" = false ]; then
            sudo systemctl restart "$service_name"
        else
            echo "[DRY-RUN] Restarting $service_name."
        fi
        echo "[WARNING] $service_name service failed to start. Retrying ($retry_count/$RETRY_COUNT)..."
        retry_count=$((retry_count + 1))
        sleep $RETRY_INTERVAL
    done
    if ! sudo systemctl is-active --quiet "$service_name"; then
        echo "[ERROR] $service_name service failed to start after $RETRY_COUNT attempts. Exiting..."
        exit 1
    fi
}

restart_service_with_retries dnsmasq
restart_service_with_retries tftpd-hpa
restart_service_with_retries smbd

# Print completion message
echo "[INFO] PXE Boot Server setup is complete. Windows 11 ISO is ready for use."

