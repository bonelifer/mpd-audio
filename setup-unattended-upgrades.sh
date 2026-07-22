#!/usr/bin/bash
#
# setup-unattended-upgrades.sh - Configure automatic security updates via
# unattended-upgrades.
#
# Usage:
#   chmod +x setup-unattended-upgrades.sh
#   sudo ./setup-unattended-upgrades.sh
#
# Inputs:
#   None. Must be run as root.
#
# Outputs:
#   Installs the unattended-upgrades package and writes
#   /etc/apt/apt.conf.d/20auto-upgrades to enable periodic checks.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Install unattended-upgrades package
apt update
apt install -y unattended-upgrades

# Create a configuration file for unattended-upgrades
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Enable and (re)start the unattended-upgrades service
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# Print a message to indicate completion
echo "Unattended upgrades are now set up on this system."

exit 0
