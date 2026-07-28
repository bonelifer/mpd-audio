#!/usr/bin/bash
#
# build-mpd.sh - Compile and install Music Player Daemon (MPD) from source.
#
# Downloads the MPD source tarball for MPD_VERSION from musicpd.org,
# builds it with meson/ninja, and installs it system-wide.
#
# Inputs:
#   None. Reads MPD_VERSION from mpd-audio.conf (copy
#   mpd-audio.conf.example to mpd-audio.conf first). Must be run as
#   root (uses sudo-equivalent privileges to install build dependencies
#   and the compiled binaries).
#
# Outputs:
#   Installs MPD MPD_VERSION to the system (default meson prefix, e.g. /usr/local).
#   Build artifacts are created in a temporary directory that is removed
#   on exit.
#
# Source: https://www.musicpd.org/

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Verify required commands are available before doing any work
for cmd in wget tar meson ninja; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

# Load MPD_VERSION from the shared config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mpd-audio.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "${CONFIG_FILE} not found. Copy mpd-audio.conf.example to mpd-audio.conf and edit it, then re-run." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Extract the major version (e.g., 0.24) from the full version
MPD_MAJOR_VERSION="$(echo "${MPD_VERSION}" | cut -d'.' -f1,2)"

# Install build dependencies (alphabetized, grouped with backslashes)
apt update
apt install -y \
  g++ \
  libadplug-dev \
  libao-dev \
  libasound2-dev \
  libaudiofile-dev \
  libavahi-client-dev \
  libavcodec-dev \
  libavformat-dev \
  libboost-dev \
  libbz2-dev \
  libcdio-paranoia-dev \
  libchromaprint-dev \
  libcurl4-gnutls-dev \
  libexpat1-dev \
  libfaad-dev \
  libflac-dev \
  libfluidsynth-dev \
  libfmt-dev \
  libgcrypt20-dev \
  libgme-dev \
  libgtest-dev \
  libicu-dev \
  libid3tag0-dev \
  libiso9660-dev \
  libjack-jackd2-dev \
  libmad0-dev \
  libmikmod-dev \
  libmms-dev \
  libmodplug-dev \
  libmp3lame-dev \
  libmpcdec-dev \
  libmpdclient-dev \
  libmpg123-dev \
  libnfs-dev \
  libogg-dev \
  libopenal-dev \
  libopus-dev \
  libpcre2-dev \
  libpipewire-0.3-dev \
  libpulse-dev \
  libresid-builder-dev \
  libsamplerate0-dev \
  libshine-dev \
  libshout3-dev \
  libsidplay2-dev \
  libsidutils-dev \
  libsndfile1-dev \
  libsndio-dev \
  libsoxr-dev \
  libsqlite3-dev \
  libsystemd-dev \
  libtwolame-dev \
  libupnp-dev \
  libvorbis-dev \
  libwavpack-dev \
  libwildmidi-dev \
  libzzip-dev \
  meson \
  ninja-build \
  nlohmann-json3-dev \
  pkgconf

# Download and extract the MPD source code into a temporary directory,
# which is cleaned up automatically when the script exits.
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "${BUILD_DIR}"' EXIT

cd "${BUILD_DIR}"
wget "https://www.musicpd.org/download/mpd/${MPD_MAJOR_VERSION}/mpd-${MPD_VERSION}.tar.xz"
tar xf "mpd-${MPD_VERSION}.tar.xz"
cd "mpd-${MPD_VERSION}"

# Configure the source tree
meson setup . output/release --buildtype=debugoptimized -Db_ndebug=true

# Compile and install
ninja -C output/release
ninja -C output/release install

# Print a message to indicate completion
echo "MPD ${MPD_VERSION} has been successfully compiled and installed."

exit 0
