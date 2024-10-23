#!/usr/bin/env bats

# Test script for PXE Boot Server setup for Raspberry Pi 5

load "/usr/local/lib/bats-support/load.bash"
load "/usr/local/lib/bats-assert/load.bash"

# Mock functions for testing purposes
setup() {
  # Mock gdown command
  gdown() {
    echo "[MOCK] Downloading from Google Drive"
    return 0
  }
  # Mock sudo to bypass privilege requirements during testing
  sudo() {
    echo "[MOCK] sudo command"
    "$@"
  }
}

# Test: Check root privileges
@test "Check script requires root privileges" {
  run bash pxe_setup_script.sh
  [ "$status" -eq 1 ]
  [[ "$output" == *"Please run as root or use sudo"* ]]
}

# Test: Verify log file setup and permissions
@test "Verify log file setup and permissions" {
  LOG_FILE="/var/log/pxe_setup.log"
  run sudo touch "$LOG_FILE"
  run sudo chmod 600 "$LOG_FILE"
  [ -f "$LOG_FILE" ]
  run sudo stat -c "%a" "$LOG_FILE"
  assert_output "600"
}

# Test: System update with retry
@test "System update and package installation" {
  run bash pxe_setup_script.sh update_system
  [ "$status" -eq 0 ]
  assert_output --partial "Updating system..."
}

# Test: Samba password non-interactive setup
@test "Samba password non-interactive setup" {
  run bash pxe_setup_script.sh set_samba_password
  assert_output --partial "Setting Samba password for user 'pxeuser'"
}

# Test: Firewall configuration
@test "Configure firewall rules" {
  run bash pxe_setup_script.sh configure_firewall
  [ "$status" -eq 0 ]
  assert_output --partial "Configuring firewall rules..."
}

# Test: Static IP setup and verification
@test "Static IP setup and verification" {
  STATIC_IP="192.168.99.1"
  run bash pxe_setup_script.sh verify_static_ip
  [ "$status" -eq 0 ]
  assert_output --partial "Verifying static IP configuration..."
}

# Test: Download Windows ISO
@test "Download Windows 11 ISO" {
  GDRIVE_URL="https://drive.google.com/uc?export=download&id=1xXEsI-O5bHzjS4g_DTAAolwhqLd-Aq_s"
  ISO_FILE="/srv/samba/win11.iso"
  EXPECTED_CHECKSUM="b56b911bf18a2ceaeb3904d87e7c770bdf92d3099599d61ac2497b91bf190b11"
  run bash pxe_setup_script.sh download_and_validate_iso "$GDRIVE_URL" "$ISO_FILE" "$EXPECTED_CHECKSUM"
  [ "$status" -eq 0 ]
  assert_output --partial "Checksum verification successful."
}

# Test: Network interface selection
@test "Select network interface for PXE boot" {
  run bash pxe_setup_script.sh preselect_interface
  assert_output --partial "Multiple network interfaces detected"
}

# Test: Service restart with retries
@test "Restart services with retry mechanism" {
  run bash pxe_setup_script.sh restart_service_with_retries dnsmasq
  [ "$status" -eq 0 ]
  assert_output --partial "Restarting dnsmasq..."
}

