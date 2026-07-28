#!/usr/bin/bash
#
# setup-mergerfs.sh - Configure and enable a persistent MergerFS pool as a
# systemd service.
#
# Installs mergerfs if needed, creates the pooled target directory, and
# registers/starts a "mergerfs-pool" systemd service that keeps the pool
# mounted (and remounts it on boot). Replaces the previous two-script
# approach (mergerfs_script.sh + automate-mergerfs.sh), which copied a
# wrapper script to ~/bin and ran it under a systemd Type=simple unit even
# though mergerfs forks and exits immediately once mounted - mismatched
# against Type=simple. This version runs mergerfs with -f (foreground) so
# the process systemd tracks is the one actually serving the mount.
#
# Inputs:
#   None. Reads MERGERFS_SOURCE_DIRS and MERGERFS_TARGET_DIR from
#   mpd-audio.conf (copy mpd-audio.conf.example to mpd-audio.conf and
#   edit those two values first). Must be run as root.
#
# Outputs:
#   Creates /etc/systemd/system/mergerfs-pool.service, enables and starts it.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Load MERGERFS_SOURCE_DIRS and MERGERFS_TARGET_DIR from the shared config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mpd-audio.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "${CONFIG_FILE} not found. Copy mpd-audio.conf.example to mpd-audio.conf and edit it, then re-run." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

SOURCE_DIRS=("${MERGERFS_SOURCE_DIRS[@]}")
TARGET_DIR="${MERGERFS_TARGET_DIR}"

# Guard against running with the unedited placeholder paths from the
# example config
if [[ "${TARGET_DIR}" == /path/to/* ]]; then
  echo "MERGERFS_TARGET_DIR in ${CONFIG_FILE} is still the placeholder value." >&2
  echo "Edit it to a real path before running this script." >&2
  exit 1
fi

# Install MergerFS if it's not already installed
if ! command -v mergerfs &>/dev/null; then
  apt update
  apt install -y mergerfs
fi
MERGERFS_BIN="$(command -v mergerfs)"

# Create the target directory if it doesn't exist
mkdir -p "${TARGET_DIR}"

# Join the source directories with ':' as mergerfs expects
SOURCE_SPEC="$(IFS=:; echo "${SOURCE_DIRS[*]}")"

# Create a systemd service unit that mounts the pool in the foreground
cat << EOF > /etc/systemd/system/mergerfs-pool.service
[Unit]
Description=MergerFS pooled storage mount
After=local-fs.target

[Service]
Type=simple
ExecStart=${MERGERFS_BIN} -f -o defaults,allow_other "${SOURCE_SPEC}" "${TARGET_DIR}"
ExecStop=/bin/fusermount -u "${TARGET_DIR}"
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, then enable and (re)start the mergerfs-pool service
systemctl daemon-reload
systemctl enable mergerfs-pool.service
systemctl restart mergerfs-pool.service

# Print a message to indicate completion
echo "MergerFS pool configured and running as a systemd service (mergerfs-pool)."

exit 0
