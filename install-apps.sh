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
#   None, except an interactive y/n prompt (30 second timeout, defaults
#   to No) asking whether to install Docker via install-docker.sh. Must
#   be run via sudo (so $SUDO_USER identifies the real user whose ~/bin
#   directory gets created). Expects install-docker.sh to be present in
#   the same directory as this script.
#
# Outputs:
#   Creates ~<user>/bin for the invoking user. Installs the mpc package.
#   If accepted, runs install-docker.sh to install Docker (which itself
#   sets up the mkdc Compose-project helper).

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

# Create the invoking user's personal bin directory, if it doesn't exist
USER_BIN_DIR="${USER_HOME}/bin"
if [ ! -d "${USER_BIN_DIR}" ]; then
  mkdir -p "${USER_BIN_DIR}"
  chown "${SUDO_USER}:${SUDO_USER}" "${USER_BIN_DIR}"
  echo "Created ${USER_BIN_DIR}."
else
  echo "${USER_BIN_DIR} already exists."
fi

# Install the `mpc` client if not already installed
if ! command -v mpc &>/dev/null; then
  apt update
  apt install -y mpc
else
  echo "mpc is already installed."
fi

# Ask whether to install Docker via install-docker.sh
install_docker="n"
if read -t 30 -r -p "Install Docker (via install-docker.sh)? [y/N]: " install_docker; then
  :
else
  echo
  echo "No response within 30 seconds; defaulting to No."
fi

if [[ "${install_docker,,}" == "y" || "${install_docker,,}" == "yes" ]]; then
  DOCKER_INSTALL_SCRIPT="${SCRIPT_DIR}/install-docker.sh"
  if [ -x "${DOCKER_INSTALL_SCRIPT}" ]; then
    "${DOCKER_INSTALL_SCRIPT}"
  else
    echo "Warning: ${DOCKER_INSTALL_SCRIPT} not found or not executable; skipping Docker install." >&2
  fi
else
  echo "Skipping Docker install."
fi

# Print a message to indicate completion
echo "install-apps.sh finished."

exit 0
