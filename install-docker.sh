#!/usr/bin/bash
#
# install-docker.sh - Install Docker Engine (docker-ce) from Docker's
# official apt repository, and grant the invoking user access to it.
#
# Reference: https://docs.docker.com/engine/install/ubuntu/
# Postinstall reference: https://docs.docker.com/engine/install/linux-postinstall/
#
# Usage:
#   sudo ./install-docker.sh
#
# Inputs:
#   None. Must be run via sudo (so $SUDO_USER identifies the real user to
#   add to the docker group).
#
# Outputs:
#   Installs docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
#   and docker-compose-plugin. Adds $SUDO_USER to the docker group. Enables
#   and starts the docker and containerd services.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Identify the user who invoked sudo, not root itself
if [ -z "${SUDO_USER:-}" ]; then
  echo "SUDO_USER is not set. Run this script with 'sudo' as a regular user, not directly as root." >&2
  exit 1
fi

# Remove conflicting Docker-related packages, if any are installed
# (matches current Docker docs' broader conflict list)
CONFLICTING_PACKAGES="$(dpkg --get-selections docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc 2>/dev/null | cut -f1)"
if [ -n "${CONFLICTING_PACKAGES}" ]; then
  # Intentionally unquoted: this needs to split into separate package
  # name arguments for apt remove.
  apt remove -y ${CONFLICTING_PACKAGES}
else
  echo "No conflicting Docker-related packages found."
fi

# Install prerequisites
apt update
apt install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update the package index
apt update

# Install Docker
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start the Docker and containerd services
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker.service

# Create the docker group if it doesn't already exist
# (docker-ce's postinstall usually creates it already)
if ! getent group docker &>/dev/null; then
  groupadd docker
fi

# Add the invoking user to the docker group
usermod -aG docker "${SUDO_USER}"
echo "Added ${SUDO_USER} to the docker group. This takes effect on their next login;"
echo "existing shells/sessions for that user won't see it until they log out and back in."

# Test Docker installation as that user in a fresh process, which picks
# up the updated group membership immediately (unlike the current shell)
sudo -u "${SUDO_USER}" docker run hello-world

# Print a message to indicate completion
echo "Docker has been installed and is running as a service."

exit 0
