#!/usr/bin/bash
#
# install-apps.sh - Install standalone apps/packages that other scripts in
# this collection depend on (currently: ashuffle, curl, git, mpc,
# mpdcron, nano, ncmpc, ncmpcpp, wget, Docker).
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
#   the same directory as this script. Reads GIT_USER_NAME and
#   GIT_USER_EMAIL from gitconfigure.conf if present; for any value
#   that's missing, prompts for it interactively (blank input skips
#   git identity setup entirely).
#
# Outputs:
#   Creates ~<user>/bin for the invoking user. Installs the ashuffle,
#   curl, git, mpc, mpdcron, nano, ncmpc, ncmpcpp, and wget packages.
#   Sets the invoking user's global git identity, writing any
#   interactively entered values back to gitconfigure.conf for future
#   runs. If accepted, runs install-docker.sh to install Docker (which
#   itself sets up the mkdc Compose-project helper).

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

# Install required packages if not already installed
PACKAGES=(ashuffle curl git mpc mpdcron nano ncmpc ncmpcpp wget)
MISSING_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
  if ! command -v "${pkg}" &>/dev/null; then
    MISSING_PACKAGES+=("${pkg}")
  else
    echo "${pkg} is already installed."
  fi
done

if [ "${#MISSING_PACKAGES[@]}" -gt 0 ]; then
  apt update
  apt install -y "${MISSING_PACKAGES[@]}"
fi

# Set the invoking user's global git identity, if configured
GIT_CONFIGURE_FILE="${SCRIPT_DIR}/gitconfigure.conf"
GIT_USER_NAME=""
GIT_USER_EMAIL=""
if [ -f "${GIT_CONFIGURE_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${GIT_CONFIGURE_FILE}"
fi

# Prompt for whatever is missing, rather than silently skipping
if [ -z "${GIT_USER_NAME}" ] || [ -z "${GIT_USER_EMAIL}" ]; then
  echo "gitconfigure.conf is missing or incomplete; enter a git identity now (leave blank to skip)."
  [ -z "${GIT_USER_NAME}" ] && read -r -p "Git user.name: " GIT_USER_NAME
  [ -z "${GIT_USER_EMAIL}" ] && read -r -p "Git user.email: " GIT_USER_EMAIL

  if [ -n "${GIT_USER_NAME}" ] && [ -n "${GIT_USER_EMAIL}" ]; then
    cat <<EOF > "${GIT_CONFIGURE_FILE}"
# gitconfigure.conf - Git global identity for install-apps.sh.
#
# Copy this file to gitconfigure.conf (same directory) and edit the
# values for your system, then run install-apps.sh. gitconfigure.conf
# is gitignored, so local edits never conflict with a future update to
# the scripts themselves.
#
# If either value below is left empty, install-apps.sh prompts for it
# interactively instead.

GIT_USER_NAME="${GIT_USER_NAME}"
GIT_USER_EMAIL="${GIT_USER_EMAIL}"
EOF
    chown "${SUDO_USER}:${SUDO_USER}" "${GIT_CONFIGURE_FILE}"
    echo "Saved git identity to ${GIT_CONFIGURE_FILE} for future runs."
  fi
fi

if [ -n "${GIT_USER_NAME}" ] && [ -n "${GIT_USER_EMAIL}" ]; then
  sudo -u "${SUDO_USER}" git config --global user.name "${GIT_USER_NAME}"
  sudo -u "${SUDO_USER}" git config --global user.email "${GIT_USER_EMAIL}"
  echo "Set global git identity for ${SUDO_USER}: ${GIT_USER_NAME} <${GIT_USER_EMAIL}>"
else
  echo "No git identity provided; skipping git identity setup."
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
