#!/usr/bin/bash
#
# install-docker.sh - Install Docker Engine (docker-ce) from Docker's
# official apt repository, and grant the invoking user access to it.
#
# Reference: https://docs.docker.com/engine/install/ubuntu/
# Postinstall reference: https://docs.docker.com/engine/install/linux-postinstall/
#
# After installing Docker, always sets up "mkdc" (a bash function
# appended to the invoking user's ~/.bashrc) that creates or opens a
# Docker Compose project directory under a root you choose, e.g.
# `mkdc myproject` - it's a Docker Compose helper, so it follows Docker
# itself rather than needing a separate opt-in. The root directory comes
# from install-docker.conf if present; otherwise it's prompted for once
# and saved there, so re-running this script doesn't ask again. Leaving
# the prompt blank (or unanswered) skips just mkdc, not the Docker
# install, and nothing is saved.
#
# Usage:
#   sudo ./install-docker.sh
#
# Inputs:
#   None required. Reads HOMELAB_ROOT from install-docker.conf if it
#   exists (see install-docker.conf.example); otherwise prompts for it
#   interactively (30 second timeout). Must be run via sudo (so
#   $SUDO_USER identifies the real user to add to the docker group and
#   whose ~/.bashrc mkdc may be added to).
#
# Outputs:
#   Installs docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
#   and docker-compose-plugin. Adds $SUDO_USER to the docker group. Enables
#   and starts the docker and containerd services. Appends the mkdc
#   function to ~<user>/.bashrc, unless no root directory was ever given
#   or the function is already present. Writes install-docker.conf on
#   first successful prompt.

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

# mkdc is a Docker Compose helper, so it's set up automatically here
# whenever Docker is installed - no separate opt-in, just the root
# directory it should use. That directory is read from install-docker.conf
# if it exists (skipping the prompt entirely); otherwise it's prompted
# for once and saved there, so re-running this script doesn't ask again.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/install-docker.conf"
homelab_root=""
if [ -f "${CONFIG_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${CONFIG_FILE}"
  homelab_root="${HOMELAB_ROOT:-}"
  echo "Using HOMELAB_ROOT from ${CONFIG_FILE}: ${homelab_root}"
else
  echo
  echo "mkdc is a helper function (added to ~/.bashrc) that creates or opens"
  echo "a Docker Compose project directory under a root you choose, e.g."
  echo "\`mkdc myproject\`."
  if ! read -t 30 -r -p "Docker Compose projects root directory (leave blank to skip mkdc) [30s timeout]: " homelab_root; then
    echo
    echo "No response within 30 seconds; skipping mkdc setup." >&2
  elif [ -n "${homelab_root}" ]; then
    printf 'HOMELAB_ROOT="%s"\n' "${homelab_root}" > "${CONFIG_FILE}"
    echo "Saved HOMELAB_ROOT to ${CONFIG_FILE} for future runs."
  fi
fi

if [ -z "${homelab_root}" ]; then
  echo "No directory entered; skipping mkdc setup." >&2
else
  USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  USER_BASHRC="${USER_HOME}/.bashrc"
  if [ ! -f "${USER_BASHRC}" ]; then
    touch "${USER_BASHRC}"
    chown "${SUDO_USER}:${SUDO_USER}" "${USER_BASHRC}"
  fi
  if grep -q '^function mkdc' "${USER_BASHRC}" 2>/dev/null; then
    echo "mkdc function already present in ${USER_BASHRC}."
  else
    cat <<'EOF' >> "${USER_BASHRC}"

function mkdc {
    # ------------------------------------------------------------------------------
    # Create and enter a Docker Compose project directory under a homelab root
    # - Accepts 1 argument: <folder_name>
    # - Opens directory in Thunar file manager
    # ------------------------------------------------------------------------------

    local base_dir="__HOMELAB_ROOT__"
    local folder_name="$1"

    # Validate argument
    if [ -z "$folder_name" ]; then
        echo "Usage: mkdc <folder_name>"
        return 1
    fi

    local target_dir="$base_dir/$folder_name"

    # If the directory exists, open it
    if [ -d "$target_dir" ]; then
        echo "✓ Directory exists: $target_dir"
        cd "$target_dir" || { echo "✗ Failed to change directory"; return 1; }
        (thunar "$target_dir" &>/dev/null & disown)
        return 0
    fi

    # Create the new directory and structure
    echo "⚙ Creating new project: $target_dir"
    mkdir -p "$target_dir" || { echo "✗ Failed to create directory"; return 1; }
    cd "$target_dir" || { echo "✗ Failed to change directory"; return 1; }

    # Create boilerplate files
    touch docker-compose.yml .env
    mkdir -p data

    # Copy default Makefile if it exists
    if [ -f "$HOME/bin/staging/Makefile" ]; then
        cp "$HOME/bin/staging/Makefile" ./
    fi

    # Open project folder in Thunar
    (thunar "$target_dir" &>/dev/null & disown)
    echo "✓ Project created and opened in Thunar"
}
EOF
    sed -i "s|__HOMELAB_ROOT__|${homelab_root}|" "${USER_BASHRC}"
    chown "${SUDO_USER}:${SUDO_USER}" "${USER_BASHRC}"
    echo "Added mkdc function to ${USER_BASHRC}."
  fi
fi

exit 0
