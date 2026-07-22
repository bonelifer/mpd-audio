#!/usr/bin/bash
#
# install-gpodder-cli.sh - Install gpo, the text-mode CLI for gPodder
# (https://gpodder.org/), plus a set of small operation-specific helper
# scripts, all placed in the invoking user's ~/bin.
#
# Avoids the Debian "gpodder" package: it bundles the CLI (gpo) and the
# GTK GUI in one binary package, so `apt install gpodder` pulls in
# gir1.2-gtk-3.0/python3-gi/python3-cairo etc. even though gpo itself
# never imports them. Instead this installs gpo via pipx directly from
# upstream source, with two adjustments to keep it CLI-only:
#   - GPODDER_INSTALL_UIS=cli tells gpodder's own setup.py to skip the
#     "gpodder" GTK launcher script and GTK-only data files.
#   - `pip install --no-deps` skips gpodder's declared dependencies,
#     because pyproject.toml lists PyGObject and dbus-python as
#     unconditional dependencies (used by the GTK UI, not by gpo), which
#     would otherwise need GObject-Introspection/D-Bus build headers.
#     The three packages gpo actually imports (podcastparser,
#     mygpoclient, requests) are installed explicitly afterward via
#     `pipx inject` instead.
#
# gpo has no dedicated "login" command; the closest equivalent is setting
# gpodder.net web-service credentials via `gpo set mygpo.*`, which is
# what the gpo-login helper below does.
#
# gpo also has no `gpo set` key for the download directory - it's not a
# config setting at all, but the GPODDER_DOWNLOAD_DIR environment
# variable (default: ~/gPodder/Downloads). If DOWNLOAD_DIR is given (or
# entered at the prompt), it's baked into gpo-update and gpo-download as
# an `export GPODDER_DOWNLOAD_DIR=...` line, so it applies whether those
# are run interactively or from cron. Left blank, gpo's own default is
# used and nothing is added.
#
# Usage:
#   sudo ./install-gpodder-cli.sh [DOWNLOAD_DIR]
#
#   If DOWNLOAD_DIR is omitted, the script prompts for one (30 second
#   timeout; leave blank to keep gpo's default).
#
# Inputs:
#   $1 (optional) - directory to download episodes into, e.g. a path
#                    under the MPD music library. Must be run as root.
#
# Outputs:
#   Installs git, pipx, and python3-venv. Installs gpo into a pipx-managed
#   virtualenv, symlinked into ~<user>/bin. Writes these helper scripts to
#   the same directory: gpo-login, gpo-update, gpo-download, gpo-subscribe,
#   gpo-unsubscribe, gpo-list, gpo-info, gpo-search, gpo-toplist. Creates
#   DOWNLOAD_DIR, owned by the invoking user, if one was given.
#
# Source: https://github.com/gpodder/gpodder

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
USER_BIN_DIR="${USER_HOME}/bin"

DOWNLOAD_DIR="${1:-}"

# If no download directory was given, offer to set one. Unlike the
# device prompts in setup-bluetooth-audio.sh/setup-alsa-equalizer.sh,
# leaving this blank (or letting it time out) is not an error - it just
# means gpo keeps its own default (~/gPodder/Downloads).
if [ -z "${DOWNLOAD_DIR}" ]; then
  echo "gpo's default download location is ~/gPodder/Downloads."
  read -t 30 -r -p "Custom download directory (leave blank to keep the default) [30s timeout]: " DOWNLOAD_DIR || true
  echo
fi

# Install pipx and its prerequisites
apt update
apt install -y git pipx python3-venv

# Create the invoking user's personal bin directory, if it doesn't exist
if [ ! -d "${USER_BIN_DIR}" ]; then
  mkdir -p "${USER_BIN_DIR}"
  chown "${SUDO_USER}:${SUDO_USER}" "${USER_BIN_DIR}"
fi

# Create the custom download directory, if one was given
if [ -n "${DOWNLOAD_DIR}" ]; then
  mkdir -p "${DOWNLOAD_DIR}"
  chown "${SUDO_USER}:${SUDO_USER}" "${DOWNLOAD_DIR}"
fi

# Install gpo (CLI-only, no GTK deps) as the invoking user. --force makes
# this safe to re-run, picking up the latest source each time.
sudo -u "${SUDO_USER}" env \
  GPODDER_INSTALL_UIS=cli \
  PIPX_BIN_DIR="${USER_BIN_DIR}" \
  pipx install --force --pip-args="--no-deps" "git+https://github.com/gpodder/gpodder.git"

# Inject the runtime dependencies gpo actually imports (skipped above via
# --no-deps to avoid pulling in PyGObject/dbus-python)
sudo -u "${SUDO_USER}" env \
  PIPX_BIN_DIR="${USER_BIN_DIR}" \
  pipx inject gpodder podcastparser mygpoclient requests

if [ ! -x "${USER_BIN_DIR}/gpo" ]; then
  echo "Warning: ${USER_BIN_DIR}/gpo was not created; check the pipx output above." >&2
fi

# gpo-login: configure gpodder.net web-service credentials. gpo has no
# dedicated login command - this drives `gpo set mygpo.*` instead.
cat <<'EOF' > "${USER_BIN_DIR}/gpo-login"
#!/usr/bin/bash
#
# gpo-login - Configure gpodder.net web-service credentials for gpo.

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

read -r -p "gpodder.net username: " username
read -r -s -p "gpodder.net password: " password
echo

"${gpo_bin}" set mygpo.username "${username}"
"${gpo_bin}" set mygpo.password "${password}"
"${gpo_bin}" set mygpo.enabled true

echo "gpodder.net credentials saved and sync enabled."

exit 0
EOF

# gpo-update: refresh all feeds, then download new episodes
cat <<'EOF' > "${USER_BIN_DIR}/gpo-update"
#!/usr/bin/bash
#
# gpo-update - Check all subscribed feeds for new episodes and download
# them. Safe to run from cron.

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

"${gpo_bin}" update
"${gpo_bin}" download

exit 0
EOF

# gpo-download: download pending episodes without re-checking feeds first
cat <<'EOF' > "${USER_BIN_DIR}/gpo-download"
#!/usr/bin/bash
#
# gpo-download - Download already-pending episodes, without refreshing
# feeds first (use gpo-update for that). Useful for retrying a failed
# batch.

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

"${gpo_bin}" download

exit 0
EOF

# If a custom download directory was chosen, bake GPODDER_DOWNLOAD_DIR
# into the two helpers that actually trigger downloads, so it applies
# whether they're run interactively or from cron.
if [ -n "${DOWNLOAD_DIR}" ]; then
  for helper in gpo-update gpo-download; do
    sed -i "/^gpo_bin=/a export GPODDER_DOWNLOAD_DIR=\"${DOWNLOAD_DIR}\"" "${USER_BIN_DIR}/${helper}"
  done
fi

# gpo-subscribe: subscribe to a podcast feed by URL
cat <<'EOF' > "${USER_BIN_DIR}/gpo-subscribe"
#!/usr/bin/bash
#
# gpo-subscribe - Subscribe to a podcast feed.
#
# Usage: gpo-subscribe <feed_url>

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <feed_url>" >&2
  exit 2
fi

"${gpo_bin}" subscribe "$1"

exit 0
EOF

# gpo-unsubscribe: unsubscribe from a podcast feed by URL
cat <<'EOF' > "${USER_BIN_DIR}/gpo-unsubscribe"
#!/usr/bin/bash
#
# gpo-unsubscribe - Unsubscribe from a podcast feed.
#
# Usage: gpo-unsubscribe <feed_url>

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <feed_url>" >&2
  exit 2
fi

"${gpo_bin}" unsubscribe "$1"

exit 0
EOF

# gpo-list: list all subscribed podcasts
cat <<'EOF' > "${USER_BIN_DIR}/gpo-list"
#!/usr/bin/bash
#
# gpo-list - List all subscribed podcasts.

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

"${gpo_bin}" list

exit 0
EOF

# gpo-info: show details and episodes for one subscribed podcast
cat <<'EOF' > "${USER_BIN_DIR}/gpo-info"
#!/usr/bin/bash
#
# gpo-info - Show details for one subscribed podcast.
#
# Usage: gpo-info <feed_url>

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") <feed_url>" >&2
  exit 2
fi

"${gpo_bin}" info "$1"

exit 0
EOF

# gpo-search: search gpodder.net's podcast directory
cat <<'EOF' > "${USER_BIN_DIR}/gpo-search"
#!/usr/bin/bash
#
# gpo-search - Search gpodder.net's podcast directory.
#
# Usage: gpo-search <search terms...>

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") <search terms...>" >&2
  exit 2
fi

"${gpo_bin}" search "$@"

exit 0
EOF

# gpo-toplist: show gpodder.net's top podcast list
cat <<'EOF' > "${USER_BIN_DIR}/gpo-toplist"
#!/usr/bin/bash
#
# gpo-toplist - Show gpodder.net's top podcast list.

set -euo pipefail

gpo_bin="$(dirname "$0")/gpo"

"${gpo_bin}" toplist

exit 0
EOF

chmod 0755 \
  "${USER_BIN_DIR}/gpo-login" \
  "${USER_BIN_DIR}/gpo-update" \
  "${USER_BIN_DIR}/gpo-download" \
  "${USER_BIN_DIR}/gpo-subscribe" \
  "${USER_BIN_DIR}/gpo-unsubscribe" \
  "${USER_BIN_DIR}/gpo-list" \
  "${USER_BIN_DIR}/gpo-info" \
  "${USER_BIN_DIR}/gpo-search" \
  "${USER_BIN_DIR}/gpo-toplist"
chown "${SUDO_USER}:${SUDO_USER}" \
  "${USER_BIN_DIR}/gpo-login" \
  "${USER_BIN_DIR}/gpo-update" \
  "${USER_BIN_DIR}/gpo-download" \
  "${USER_BIN_DIR}/gpo-subscribe" \
  "${USER_BIN_DIR}/gpo-unsubscribe" \
  "${USER_BIN_DIR}/gpo-list" \
  "${USER_BIN_DIR}/gpo-info" \
  "${USER_BIN_DIR}/gpo-search" \
  "${USER_BIN_DIR}/gpo-toplist"

# Print a message to indicate completion
echo "gpo and helper scripts installed to ${USER_BIN_DIR}."
echo "Run 'gpo-login' first if you want gpodder.net subscription sync."
echo "Make sure ${USER_BIN_DIR} is on your PATH (most default .bashrc setups add it automatically if it exists)."
if [ -n "${DOWNLOAD_DIR}" ]; then
  echo "Episodes will download to ${DOWNLOAD_DIR} (via gpo-update/gpo-download)."
else
  echo "Using gpo's default download location: ~/gPodder/Downloads."
fi

exit 0
