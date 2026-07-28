#!/usr/bin/bash
#
# install-alsaequal-web-api.sh - Install alsaequal-web-api, a browser/HTTP
# front-end for applying named ALSA equalizer presets to the "equal"
# device set up by setup-alsa-equalizer.sh.
# https://github.com/bonelifer/alsaequal-web-api
#
# Clones the repo into the invoking user's home directory (or pulls the
# latest changes if already cloned), then delegates to its own
# install.sh, which installs apt dependencies, copies app.py to
# ~/bin/, and installs/starts the "eqctl" systemd service under the
# invoking user. Safe to re-run: pulls the latest source and reinstalls
# instead of failing on an existing clone.
#
# Run this *after* setup-alsa-equalizer.sh: alsaequal-web-api's presets
# are applied via the same "equal" ALSA device that script wires up, and
# its own README lists that wiring as a prerequisite it doesn't set up
# itself.
#
# Usage:
#   sudo ./install-alsaequal-web-api.sh
#
# Inputs:
#   None (interactive). Must be run via sudo (so $SUDO_USER identifies
#   the real user whose ~/bin and systemd service get installed -
#   install.sh itself expects the same). On first install, install.sh
#   prompts for the HTTP Basic Auth username/password the service will
#   require - have those ready before running this non-interactively is
#   not supported.
#
# Outputs:
#   Clones/updates ~<user>/alsaequal-web-api. Runs its install.sh, which
#   installs python3-cherrypy3, libasound2-plugin-equal, and alsa-utils
#   via apt, copies app.py to ~<user>/bin/, prompts for and writes real
#   credentials to ~<user>/bin/eqctl.env on first install (leaving it
#   untouched on later reinstalls), and installs/starts the "eqctl"
#   systemd service.
#
# Source: https://github.com/bonelifer/alsaequal-web-api

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

REPO_DIR="${USER_HOME}/alsaequal-web-api"

# Verify required commands are available before doing any work
for cmd in git bash; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

# Clone the alsaequal-web-api repository, or pull the latest changes if
# already cloned. Run as the invoking user so the clone is owned by
# them, not root.
if [ -d "${REPO_DIR}/.git" ]; then
  echo "Existing clone found at ${REPO_DIR}; pulling latest changes."
  sudo -u "${SUDO_USER}" git -C "${REPO_DIR}" pull
else
  sudo -u "${SUDO_USER}" git clone https://github.com/bonelifer/alsaequal-web-api.git "${REPO_DIR}"
fi

# Delegate to alsaequal-web-api's own installer, which handles apt
# dependencies, the ~/bin copy, eqctl.env templating, and the systemd
# service. It reads $SUDO_USER itself (already set from this script's
# own invocation via sudo), so no need to re-invoke it through sudo.
bash "${REPO_DIR}/install.sh"

# Print a message to indicate completion
echo
echo "alsaequal-web-api installed and running as 'eqctl'."
echo "Open http://$(hostname -I | cut -d' ' -f1):5000/ and log in with the"
echo "credentials you just set."

exit 0
