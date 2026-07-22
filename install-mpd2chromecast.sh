#!/usr/bin/bash
#
# install-mpd2chromecast.sh - Install mpd2chromecast, a Python service that
# relays MPD playback to Chromecast/Google Home devices on the LAN.
# https://github.com/dresdner353/mpd2chromecast
#
# Clones the repo into the invoking user's home directory, installs its
# Python dependencies, and registers/starts it as the "mpd2chromecast"
# systemd service. Safe to re-run: pulls the latest source instead of
# failing on an existing clone, and rebuilds the service file/restarts.
#
# Pairs with the "httpd" audio_output already in mpd.conf (see
# generate-mpd-conf.sh): mpd2chromecast's web UI can cast that stream
# (http://<host>:8000) directly to a Chromecast instead of per-file URLs,
# for gapless/DSP-aware playback.
#
# Deviates from upstream's install.sh in one respect: upstream branches on
# `VERSION_ID -ge 12` from /etc/os-release to choose apt vs. pip, which
# breaks on non-integer version strings (e.g. Ubuntu's "22.04"). This
# script instead probes apt directly for package availability, and only
# adds pip's --break-system-packages flag when the PEP 668
# EXTERNALLY-MANAGED marker is actually present.
#
# Usage:
#   sudo ./install-mpd2chromecast.sh
#
# Inputs:
#   None. Must be run via sudo (so $SUDO_USER identifies the real user
#   who owns the clone and runs the service).
#
# Outputs:
#   Clones/updates ~<user>/mpd2chromecast. Installs git, pip, and the
#   cherrypy/pychromecast/python-mpd2 Python modules (via apt where
#   available, otherwise pip). Creates /etc/systemd/system/
#   mpd2chromecast.service and starts the service. Web control interface
#   listens on port 8090.
#
# Source: https://github.com/dresdner353/mpd2chromecast

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

REPO_DIR="${USER_HOME}/mpd2chromecast"

apt update

# Prefer apt packages where available; fall back to pip otherwise
if apt-cache show python3-pychromecast &>/dev/null; then
  apt install -y \
    git \
    python3-cherrypy3 \
    python3-mpd \
    python3-pip \
    python3-pychromecast
else
  apt install -y git python3-pip

  # PEP 668 (EXTERNALLY-MANAGED) landed in Debian Bookworm/Ubuntu 23.04+;
  # older pip versions reject the --break-system-packages flag outright,
  # so only pass it when the marker is actually present.
  pip_flags=()
  if compgen -G "/usr/lib/python3*/EXTERNALLY-MANAGED" > /dev/null; then
    pip_flags+=(--break-system-packages)
  fi
  pip3 install "${pip_flags[@]}" cherrypy pychromecast python-mpd2
fi

# Clone the mpd2chromecast repository, or pull the latest changes if
# already cloned. Run as the invoking user so the clone is owned by them,
# not root.
if [ -d "${REPO_DIR}/.git" ]; then
  echo "Existing clone found at ${REPO_DIR}; pulling latest changes."
  sudo -u "${SUDO_USER}" git -C "${REPO_DIR}" pull
else
  sudo -u "${SUDO_USER}" git clone https://github.com/dresdner353/mpd2chromecast.git "${REPO_DIR}"
fi

# Create a user-specific variant of the shipped service template
sed -e "s%__USER__%${SUDO_USER}%g" \
    -e "s%__HOME__%${USER_HOME}%g" \
    "${REPO_DIR}/mpd2chromecast.service" > /etc/systemd/system/mpd2chromecast.service

# Reload systemd, then enable and (re)start the mpd2chromecast service
systemctl daemon-reload
systemctl enable mpd2chromecast
systemctl restart mpd2chromecast

# Print a message to indicate completion
echo "mpd2chromecast has been installed and is running as a service."
echo "Web control interface: http://$(hostname -I | cut -d' ' -f1):8090"

exit 0
