#!/usr/bin/bash
#
# setup-log-rotation.sh - Install a logrotate policy for MPD's log file.
#
# Run after generate-mpd-conf.sh / mpd.conf is installed to /etc/mpd.conf,
# since that's what sets log_file to MPD_LOG_FILE (from mpd-audio.conf)
# in the first place - both scripts read the same value, so they can't
# drift out of sync. Uses `copytruncate` rather than a postrotate reload
# signal, because MPD has no documented signal for reopening its log
# file after rotation; with `copytruncate` there's a small window where
# writes between the copy and the truncate can be lost, but it avoids
# relying on unverified daemon behavior.
#
# myMPD and mpDris2 are not covered here: as set up by install-mympd.sh
# and install-mpdris2.sh, both run under systemd with no log_file of
# their own, so their output goes to the journal, which journald already
# rotates independently (see journald.conf).
#
# Usage:
#   sudo ./setup-log-rotation.sh
#
# Inputs:
#   None. Reads MPD_LOG_FILE from mpd-audio.conf (copy
#   mpd-audio.conf.example to mpd-audio.conf first - the same file
#   generate-mpd-conf.sh reads). Must be run as root.
#
# Outputs:
#   Writes /etc/logrotate.d/mpd.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Load MPD_LOG_FILE from the shared config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mpd-audio.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "${CONFIG_FILE} not found. Copy mpd-audio.conf.example to mpd-audio.conf and edit it, then re-run." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Install logrotate if it's not already present
if ! command -v logrotate &>/dev/null; then
  apt update
  apt install -y logrotate
fi

# Write the logrotate policy for MPD's log file
cat <<EOF > /etc/logrotate.d/mpd
${MPD_LOG_FILE} {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 mpd mpd
}
EOF

# Print a message to indicate completion
echo "Log rotation for ${MPD_LOG_FILE} configured via /etc/logrotate.d/mpd."

exit 0
