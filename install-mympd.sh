#!/usr/bin/bash
#
# install-mympd.sh - Build and install myMPD from source, and register it
# as a systemd service.
#
# Clones https://github.com/jcorporation/myMPD.git, builds it with
# cmake/make, installs it, and creates/enables a "mympd" systemd unit.
# Safe to re-run: pulls the latest source instead of failing on an
# existing clone, and rebuilds/restarts the service.
#
# Inputs:
#   None. Must be run as root.
#
# Outputs:
#   Installs myMPD to the default cmake install prefix (e.g. /usr/local).
#   Creates /etc/systemd/system/mympd.service and starts the service.
#
# Source: https://github.com/jcorporation/myMPD

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Verify required commands are available before doing any work
for cmd in git cmake make; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

REPO_DIR="/opt/myMPD"

# Update package lists
apt update

# Install dependencies
apt install -y git cmake g++ libcdio-paranoia-dev libmad0-dev libid3tag0-dev libflac-dev libvorbis-dev \
  libsqlite3-dev libudev-dev libupnp-dev libyajl-dev libmpdclient-dev

# Clone the myMPD repository, or pull the latest changes if already cloned
if [ -d "${REPO_DIR}/.git" ]; then
  echo "Existing clone found at ${REPO_DIR}; pulling latest changes."
  git -C "${REPO_DIR}" pull
else
  git clone https://github.com/jcorporation/myMPD.git "${REPO_DIR}"
fi

# Build and install myMPD
cd "${REPO_DIR}"
mkdir -p build
cd build
cmake ..
make -j4
make install

# Create a system service unit file for myMPD
cat << EOF > /etc/systemd/system/mympd.service
[Unit]
Description=MyMPD Server

[Service]
ExecStart=/usr/local/bin/mympd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, then enable and (re)start the myMPD service
systemctl daemon-reload
systemctl enable mympd
systemctl restart mympd

# Print a message to indicate completion
echo "MyMPD has been installed and is running as a service."

exit 0
