#!/usr/bin/bash
#
# install-apps.sh - Install standalone apps/packages that other scripts in
# this collection depend on (currently: mpc, Docker).
#
# Add new installs here as they come up, rather than duplicating install
# logic across individual scripts.
#
# Usage:
#   chmod +x install-apps.sh
#   sudo ./install-apps.sh
#
# Inputs:
#   None. Reads HOMELAB_ROOT from install-apps.conf (copy
#   install-apps.conf.example to install-apps.conf and edit it first).
#   Must be run via sudo (so $SUDO_USER identifies the real user whose
#   ~/bin directory and ~/.bashrc get updated). Expects install-docker.sh
#   to be present in the same directory as this script.
#
# Outputs:
#   Creates ~<user>/bin for the invoking user. Appends the `mkdc` helper
#   function to ~<user>/.bashrc (skipped if already present). Installs the
#   mpc package. Runs install-docker.sh to install Docker.

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
USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load HOMELAB_ROOT from this script's own config file
CONFIG_FILE="${SCRIPT_DIR}/install-apps.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "${CONFIG_FILE} not found. Copy install-apps.conf.example to install-apps.conf and edit it, then re-run." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Create the invoking user's personal bin directory, if it doesn't exist
USER_BIN_DIR="${USER_HOME}/bin"
if [ ! -d "${USER_BIN_DIR}" ]; then
  mkdir -p "${USER_BIN_DIR}"
  chown "${SUDO_USER}:${SUDO_USER}" "${USER_BIN_DIR}"
  echo "Created ${USER_BIN_DIR}."
else
  echo "${USER_BIN_DIR} already exists."
fi

# Append the `mkdc` helper function to the invoking user's ~/.bashrc, if
# it isn't already there (idempotent across re-runs)
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
  sed -i "s|__HOMELAB_ROOT__|${HOMELAB_ROOT}|" "${USER_BASHRC}"
  chown "${SUDO_USER}:${SUDO_USER}" "${USER_BASHRC}"
  echo "Added mkdc function to ${USER_BASHRC}."
fi

# Install the `mpc` client if not already installed
if ! command -v mpc &>/dev/null; then
  apt update
  apt install -y mpc
else
  echo "mpc is already installed."
fi

# Install Docker via install-docker.sh
DOCKER_INSTALL_SCRIPT="${SCRIPT_DIR}/install-docker.sh"
if [ -x "${DOCKER_INSTALL_SCRIPT}" ]; then
  "${DOCKER_INSTALL_SCRIPT}"
else
  echo "Warning: ${DOCKER_INSTALL_SCRIPT} not found or not executable; skipping Docker install." >&2
fi

# Print a message to indicate completion
echo "install-apps.sh finished."

exit 0
