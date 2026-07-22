#!/usr/bin/bash
#
# setup-alsa-equalizer.sh - Install a 10-band ALSA-level equalizer
# (libasound2-plugin-equal, aka alsaequal) wrapping a chosen output
# device, plus an "mpd-eq" helper for saving/loading named EQ profiles
# as plain text.
#
# libasound2-plugin-equal stores its band gains in an opaque binary file
# (default ~/.alsaequal.bin) that you can only edit through an ALSA mixer
# (alsamixer/amixer) - there's no way to hand-author a text EQ curve for
# it directly. mpd-eq works around that by reading/writing the same
# controls via `amixer -D equal`, serialized as plain "name:value" lines,
# so profiles can be saved, edited, diffed, and reloaded. The save/load
# approach is adapted from the idea in
# https://github.com/perfinion/alsaequal-scripties (unmaintained since
# 2011, GUI/Python 2 parts unusable on a headless box) - only that idea
# is reused here, not its code.
#
# After running this script, point MPD's local audio_output at the "equal"
# PCM instead of the raw device, e.g.:
#   audio_output {
#       type   "alsa"
#       name   "Analog Output (EQ)"
#       device "equal"
#   }
#
# Usage:
#   sudo ./setup-alsa-equalizer.sh [SLAVE_DEVICE]
#
#   If SLAVE_DEVICE is omitted, the script lists ALSA devices (aplay -L)
#   and prompts for one (30 second timeout, no default).
#
# Inputs:
#   $1 (optional) - ALSA device to wrap, e.g. "hw:CARD=PCH,DEV=0" or a
#                    bluealsa device from setup-bluetooth-audio.sh. Must
#                    be run as root.
#
# Outputs:
#   Installs alsa-utils and libasound2-plugin-equal. Backs up any
#   existing /etc/asound.conf, then writes a new one defining the "equal"
#   ctl/pcm. Creates /var/lib/mpd/alsaequal (profiles dir + controls
#   file), owned by mpd:mpd. Installs /usr/local/bin/mpd-eq
#   (save|load|list).

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

EQUAL_DIR="/var/lib/mpd/alsaequal"
CONTROLS_FILE="${EQUAL_DIR}/current.bin"
PROFILES_DIR="${EQUAL_DIR}/profiles"
ASOUND_CONF="/etc/asound.conf"

SLAVE_DEVICE="${1:-}"

# If no device was given, list ALSA devices and prompt for one
if [ -z "${SLAVE_DEVICE}" ]; then
  if ! command -v aplay &>/dev/null; then
    echo "Required command 'aplay' not found. Install it and re-run." >&2
    exit 1
  fi
  echo "Available ALSA devices:"
  aplay -L
  if ! read -t 30 -r -p "Enter the device to wrap with the equalizer [30s timeout]: " SLAVE_DEVICE; then
    echo
    echo "No response within 30 seconds; aborting." >&2
    exit 1
  fi
  if [ -z "${SLAVE_DEVICE}" ]; then
    echo "No device entered; aborting." >&2
    exit 1
  fi
fi

# Install alsa-utils (amixer/aplay) and the alsaequal plugin
apt update
apt install -y alsa-utils libasound2-plugin-equal

# Create the directory for the controls file and saved profiles
mkdir -p "${PROFILES_DIR}"
chown -R mpd:mpd "${EQUAL_DIR}"

# Back up any existing /etc/asound.conf before overwriting it, since this
# is a shared system-wide file that may already hold other customizations
if [ -f "${ASOUND_CONF}" ]; then
  BACKUP_FILE="${ASOUND_CONF}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${ASOUND_CONF}" "${BACKUP_FILE}"
  echo "Backed up existing ${ASOUND_CONF} to ${BACKUP_FILE}."
fi

# Write the "equal" ctl/pcm definition. slave.pcm is wrapped with
# "plug:" since alsaequal only supports floating point samples and a raw
# hw device won't do the conversion.
cat <<EOF > "${ASOUND_CONF}"
ctl.equal {
    type equal;
    controls "${CONTROLS_FILE}";
}

pcm.equal {
    type equal;
    slave.pcm "plug:${SLAVE_DEVICE}";
    controls "${CONTROLS_FILE}";
}
EOF
echo "Wrote ${ASOUND_CONF} wrapping ${SLAVE_DEVICE} as ALSA device \"equal\"."

# Install the mpd-eq helper for saving/loading named EQ profiles
cat <<'EOF' > /usr/local/bin/mpd-eq
#!/usr/bin/bash
#
# mpd-eq - Save/load/list named EQ band profiles for the ALSA "equal"
# device set up by setup-alsa-equalizer.sh. Profiles are plain text
# ("control_name:value" per line, value in percent), so they can be
# committed, diffed, and edited by hand.

set -euo pipefail

PROFILES_DIR="/var/lib/mpd/alsaequal/profiles"

usage() {
  echo "Usage: mpd-eq save <profile_name>" >&2
  echo "       mpd-eq load <profile_name>" >&2
  echo "       mpd-eq list" >&2
  exit 2
}

if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

if [ "$#" -lt 1 ]; then
  usage
fi

command="$1"

case "${command}" in
  save)
    if [ "$#" -ne 2 ]; then
      usage
    fi
    profile_file="${PROFILES_DIR}/$2.txt"
    : > "${profile_file}"
    amixer -D equal scontrols | sed -e "s/.*'\(.*\)'.*/\1/" | while IFS= read -r control_name; do
      value="$(amixer -D equal get "${control_name}" | grep -m1 '%' | sed -e 's/.*\[\([0-9]\+\)%\].*/\1/')"
      echo "${control_name}:${value}" >> "${profile_file}"
    done
    echo "Saved current EQ settings to ${profile_file}."
    ;;
  load)
    if [ "$#" -ne 2 ]; then
      usage
    fi
    profile_file="${PROFILES_DIR}/$2.txt"
    if [ ! -f "${profile_file}" ]; then
      echo "No such profile: ${profile_file}" >&2
      exit 1
    fi
    while IFS=: read -r control_name value; do
      amixer -D equal set "${control_name}" "${value}%" > /dev/null
    done < "${profile_file}"
    echo "Loaded EQ profile ${profile_file}."
    ;;
  list)
    ls -1 "${PROFILES_DIR}" 2>/dev/null | sed 's/\.txt$//'
    ;;
  *)
    usage
    ;;
esac

exit 0
EOF
chmod 0755 /usr/local/bin/mpd-eq

# Print a message to indicate completion
echo "ALSA equalizer configured. Update mpd.conf's local audio_output to"
echo "use device \"equal\" instead of \"${SLAVE_DEVICE}\", then restart mpd."
echo "Use 'sudo mpd-eq save <name>' / 'sudo mpd-eq load <name>' to manage profiles."

exit 0
