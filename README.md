# BootBerry

BootBerry is a project that sets up a Raspberry Pi 5 as a PXE Boot Server to install Windows 11 on a Victus by HP Gaming Laptop 15-fbf1013dx.

## Overview
This project aims to automate the setup of a PXE Boot Server using a Raspberry Pi 5. The server will allow for network-based installation of Windows 11 on target machines, making the installation process more convenient and efficient. The script provided in this repository (`pxe_setup.sh`) is designed to simplify the entire process, including DHCP, TFTP, and Samba configurations.

## Features
- Automatic installation of necessary packages
- Configures DHCP and TFTP services for PXE boot
- Provides Samba shares for accessing Windows installation files
- Rollback mechanism to undo changes in case of errors
- Log management for easier troubleshooting

## Prerequisites
- A Raspberry Pi 5 running Raspberry Pi OS
- A Windows 11 ISO file
- Access to the internet for downloading dependencies
- Administrative privileges on the Raspberry Pi

## Getting Started
1. **Clone the Repository**
   ```bash
   git clone https://github.com/NurdRage/BootBerry.git
   cd BootBerry
   ```

2. **Make the Script Executable**
   ```bash
   chmod +x pxe_setup.sh
   ```

3. **Run the Script**
   Execute the script with root privileges to start the setup process:
   ```bash
   sudo ./pxe_setup.sh
   ```

4. **Follow the Prompts**
   During the setup process, you'll be asked for a password and given the option to perform a dry run. Follow the on-screen instructions to complete the configuration.

## Configuration
The script will automatically configure the following services:
- **DHCP and TFTP**: Configured using `dnsmasq` to handle PXE boot requests.
- **Samba Share**: Provides access to Windows installation files over the network.
- **Firewall**: Configures UFW to allow necessary ports for DHCP, TFTP, and Samba.

## Rollback
In case of any errors during the setup, a rollback function is available to undo changes. This ensures that your system remains in a clean state.

## Notes
- Ensure that the Raspberry Pi is connected to the same network as the target device that will be PXE-booted.
- The script has a retry mechanism for package installations and firewall configurations to improve reliability.

## Contributions
Contributions to improve the script or add new features are welcome. Please submit a pull request with a detailed description of your changes.

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.


