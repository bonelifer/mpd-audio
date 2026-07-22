#!/usr/bin/bash
#
# install-mpdris2.sh - Build and install mpDris2 (MPRIS2 bridge for MPD)
# from source.
# https://github.com/eonpatapon/mpDris2
#
# Needs to be run after the mpd.conf file is generated and installed.
# Assumes mpc is already installed (see install-apps.sh).
#
# Usage:
#   chmod +x install-mpdris2.sh
#   sudo ./install-mpdris2.sh
#
# Inputs:
#   None. Must be run via sudo (so $SUDO_USER identifies the real user
#   whose config directory and D-Bus session mpDris2 will use).
#
# Outputs:
#   Builds and installs mpDris2 from source (skipped on re-run if already
#   installed). Writes ~<user>/.config/mpDris2/mpDris2.conf for the
#   invoking user.

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

# Install `mpDris2` if not already installed (it's built from source, so
# it won't show up in dpkg -l; check for the installed binary instead)
if ! command -v mpDris2 &>/dev/null; then
  # Install dependencies for building from source
  apt install -y git automake autoconf libtool

  BUILD_DIR="$(mktemp -d)"
  trap 'rm -rf "${BUILD_DIR}"' EXIT

  git clone https://github.com/eonpatapon/mpDris2.git "${BUILD_DIR}/mpDris2"
  cd "${BUILD_DIR}/mpDris2"
  ./autogen.sh --sysconfdir=/etc
  make
  make install
fi

# Create the necessary directory for `mpDris2` and set permissions
mkdir -p /var/lib/mpd/mpDris2
chown mpd:mpd /var/lib/mpd/mpDris2

# Get the local machine's hostname and resolve it to the local IP address
local_ip="$(hostname -I | cut -d' ' -f1)"

# Get the music_dir from mpd.conf
music_dir="$(grep -E '^\s*music_directory' /etc/mpd.conf | awk -F '"' '{print $2}')"
if [ -z "${music_dir}" ]; then
  echo "Warning: could not read music_directory from /etc/mpd.conf; leaving it blank in mpDris2.conf." >&2
fi

# Create the mpDris2.conf file with the updated values, in the invoking
# user's config directory (creating it first, since it won't exist yet)
CONF_DIR="${USER_HOME}/.config/mpDris2"
mkdir -p "${CONF_DIR}"
cat <<EOF > "${CONF_DIR}/mpDris2.conf"
[Connection]
host = ${local_ip}
port = 6600
music_dir = ${music_dir}

[Bling]
notify = False
notify_paused = False
mmkeys = False
cdprev = True

[Notify]
# Urgency of the notification: 0 for low, 1 for medium and 2 for high.
#urgency = 0
# Timeout of the notification in milliseconds. -1 uses the notification's default
# and 0 sets the notification to never timeout.
#timeout = -1
# Format the notification's summary and body in either playing or paused state.
# Leave blank to use mpDris2's internal defaults.
# Possible values:
#     %album%, %title%, %id%, %time%, %timeposition%, %date%, %track%,
#     %disc%, %artist%, %albumartist%, %composer%, %genre%, %file%
#summary =
#body =
#paused_summary =
#paused_body =
EOF
chown "${SUDO_USER}:${SUDO_USER}" "${CONF_DIR}/mpDris2.conf"

# Enable and start the mpDris2 service, if a unit file for it exists
# (mpDris2's build does not always install one)
if systemctl list-unit-files | grep -q '^mpDris2\.service'; then
  systemctl enable mpDris2
  systemctl start mpDris2
else
  echo "No mpDris2 systemd unit found; skipping service enable/start." >&2
fi

# Print a message to indicate completion
echo "mpDris2 has been successfully installed and set up for MPD."

exit 0
