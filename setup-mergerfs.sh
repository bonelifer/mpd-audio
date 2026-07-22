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
#   Edit SOURCE_DIRS and TARGET_DIR below before running.
#   Must be run as root.
#
# Outputs:
#   Creates /etc/systemd/system/mergerfs-pool.service, enables and starts it.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Define the source directories and the target directory
SOURCE_DIRS=("/path/to/source1" "/path/to/source2" "/path/to/source3" "/path/to/source4") # Update before running
TARGET_DIR="/path/to/merged" # Update before running

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
