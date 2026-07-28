#!/usr/bin/bash
#
# setup-alsa-equalizer.sh - Install a 10-band ALSA-level equalizer
# (libasound2-plugin-equal, aka alsaequal) wrapping a chosen output
# device, plus an "mpd-eq" helper for saving/loading named EQ profiles
# as plain text, with the same built-in presets as the alsaequal-web-api
# project's browser/HTTP front-end.
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
# mpd-eq also ships the same 21 built-in presets (by name and per-band
# value) as https://github.com/bonelifer/alsaequal-web-api's app.py, so
# `sudo mpd-eq load rock` and that project's `/eq/rock` endpoint apply
# identical settings. A saved profile takes priority over a built-in of
# the same name.
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
#   If SLAVE_DEVICE is given, only that one device is wrapped (as
#   "equal"), same as before - /etc/mpd.conf is left untouched and you
#   update it yourself.
#
#   If SLAVE_DEVICE is omitted, the script instead reads every local
#   "alsa" audio_output already in /etc/mpd.conf (as written by
#   generate-mpd-conf.sh), wraps each one with its own "equal_<name>"
#   PCM sharing one EQ control surface, and rewrites each block's
#   `device` line in /etc/mpd.conf to point at its new wrapped PCM
#   (backing up /etc/mpd.conf first). Devices already wrapped (a prior
#   run) are skipped.
#
# Inputs:
#   $1 (optional) - ALSA device to wrap, e.g. "hw:CARD=PCH,DEV=0" or a
#                    bluealsa device from setup-bluetooth-audio.sh. Must
#                    be run as root.
#
# Outputs:
#   Installs alsa-utils and libasound2-plugin-equal. Backs up any
#   existing /etc/asound.conf, then writes a new one defining a shared
#   "equal" ctl plus one "equal_<name>" pcm per wrapped device (or a
#   single "equal" pcm, if SLAVE_DEVICE was given explicitly). Creates
#   /var/lib/mpd/alsaequal (profiles dir + controls file), owned by
#   mpd:mpd. Installs /usr/local/bin/mpd-eq (save|load|list|presets). In
#   auto-detect mode, also backs up and rewrites /etc/mpd.conf.

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
MPD_CONF="/etc/mpd.conf"

SLAVE_DEVICE="${1:-}"
AUTO_DETECT=0
declare -a DETECTED_NAMES=()
declare -a DETECTED_DEVICES=()
declare -a DETECTED_PCM_NAMES=()

if [ -z "${SLAVE_DEVICE}" ]; then
  AUTO_DETECT=1

  if [ ! -f "${MPD_CONF}" ]; then
    echo "${MPD_CONF} not found, so there's nothing to auto-detect." >&2
    echo "Run generate-mpd-conf.sh and copy the result to ${MPD_CONF} first," >&2
    echo "or pass a device to wrap explicitly, e.g.:" >&2
    echo "  sudo $0 hw:CARD=PCH,DEV=0" >&2
    exit 1
  fi

  # Parse each `audio_output { ... }` block in mpd.conf, keeping only
  # local "alsa" outputs with a device not already wrapped by a
  # previous run of this script.
  in_block=0
  block_type=""
  block_name=""
  block_device=""
  while IFS= read -r line; do
    if [[ "${line}" =~ ^[[:space:]]*audio_output[[:space:]]*\{ ]]; then
      in_block=1
      block_type=""
      block_name=""
      block_device=""
      continue
    fi
    if [ "${in_block}" -eq 1 ] && [[ "${line}" =~ ^[[:space:]]*\} ]]; then
      if [ "${block_type}" = "alsa" ] && [ -n "${block_device}" ] && [[ "${block_device}" != equal* ]]; then
        DETECTED_NAMES+=("${block_name}")
        DETECTED_DEVICES+=("${block_device}")
      fi
      in_block=0
      continue
    fi
    if [ "${in_block}" -eq 1 ]; then
      if [[ "${line}" =~ ^[[:space:]]*type[[:space:]]+\"([^\"]*)\" ]]; then
        block_type="${BASH_REMATCH[1]}"
      elif [[ "${line}" =~ ^[[:space:]]*name[[:space:]]+\"([^\"]*)\" ]]; then
        block_name="${BASH_REMATCH[1]}"
      elif [[ "${line}" =~ ^[[:space:]]*device[[:space:]]+\"([^\"]*)\" ]]; then
        block_device="${BASH_REMATCH[1]}"
      fi
    fi
  done < "${MPD_CONF}"

  if [ "${#DETECTED_DEVICES[@]}" -eq 0 ]; then
    echo "No wrappable local ALSA audio_output found in ${MPD_CONF}" >&2
    echo "(none configured, or all already wrapped with \"equal_*\"). Nothing to do." >&2
    exit 0
  fi

  # Turn each output's name into a unique "equal_<slug>" PCM name,
  # de-duplicating in the unlikely case two names collide once slugged.
  declare -A SEEN_SLUGS=()
  for name in "${DETECTED_NAMES[@]}"; do
    slug="$(echo "${name}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
    pcm_name="equal_${slug}"
    if [ -n "${SEEN_SLUGS[${pcm_name}]+set}" ]; then
      SEEN_SLUGS[${pcm_name}]=$((SEEN_SLUGS[${pcm_name}] + 1))
      pcm_name="${pcm_name}_${SEEN_SLUGS[${pcm_name}]}"
    else
      SEEN_SLUGS[${pcm_name}]=1
    fi
    DETECTED_PCM_NAMES+=("${pcm_name}")
  done

  echo "Detected local ALSA outputs in ${MPD_CONF}:"
  for i in "${!DETECTED_NAMES[@]}"; do
    echo "  - ${DETECTED_NAMES[${i}]} (${DETECTED_DEVICES[${i}]}) -> ${DETECTED_PCM_NAMES[${i}]}"
  done
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

# Write the "equal" ctl definition, plus one pcm per wrapped device (all
# sharing the same ctl/controls file, so one EQ curve applies to every
# wrapped output at once). slave.pcm is wrapped with "plug:" since
# alsaequal only supports floating point samples and a raw hw device
# won't do the conversion.
{
  echo "ctl.equal {"
  echo "    type equal;"
  echo "    controls \"${CONTROLS_FILE}\";"
  echo "}"
  echo

  if [ "${AUTO_DETECT}" -eq 1 ]; then
    for i in "${!DETECTED_DEVICES[@]}"; do
      echo "pcm.${DETECTED_PCM_NAMES[${i}]} {"
      echo "    type equal;"
      echo "    slave.pcm \"plug:${DETECTED_DEVICES[${i}]}\";"
      echo "    controls \"${CONTROLS_FILE}\";"
      echo "}"
      echo
    done
  else
    echo "pcm.equal {"
    echo "    type equal;"
    echo "    slave.pcm \"plug:${SLAVE_DEVICE}\";"
    echo "    controls \"${CONTROLS_FILE}\";"
    echo "}"
  fi
} > "${ASOUND_CONF}"

if [ "${AUTO_DETECT}" -eq 1 ]; then
  echo "Wrote ${ASOUND_CONF} wrapping ${#DETECTED_DEVICES[@]} device(s)."

  # Back up /etc/mpd.conf before rewriting its device lines, same as
  # /etc/asound.conf above.
  MPD_CONF_BACKUP="${MPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
  cp "${MPD_CONF}" "${MPD_CONF_BACKUP}"
  echo "Backed up existing ${MPD_CONF} to ${MPD_CONF_BACKUP}."

  for i in "${!DETECTED_DEVICES[@]}"; do
    sed -i "s#device[[:space:]]*\"${DETECTED_DEVICES[${i}]}\"#device \"${DETECTED_PCM_NAMES[${i}]}\"#" "${MPD_CONF}"
  done
  echo "Updated ${MPD_CONF}'s audio_output device lines to point at the wrapped PCMs."
else
  echo "Wrote ${ASOUND_CONF} wrapping ${SLAVE_DEVICE} as ALSA device \"equal\"."
fi

# Install the mpd-eq helper for saving/loading named EQ profiles
cat <<'EOF' > /usr/local/bin/mpd-eq
#!/usr/bin/bash
#
# mpd-eq - Save/load/list named EQ band profiles for the ALSA "equal"
# device set up by setup-alsa-equalizer.sh. Profiles are plain text
# ("control_name:value" per line, value in percent), so they can be
# committed, diffed, and edited by hand.
#
# Also ships the same built-in presets as
# https://github.com/bonelifer/alsaequal-web-api's app.py, as 10-band
# (31/63/125/250/500/1k/2k/4k/8k/16k Hz) percentage values, so `mpd-eq
# load rock` and that project's `/eq/rock` apply identical settings. The
# two PRESETS tables are maintained by hand in each project - keep them
# in sync if you add or change a preset. Built-in presets are applied
# positionally against whatever `amixer -D equal scontrols` reports, in
# ascending frequency order, the
# same way `save`/`load` already discover
# real control names - so no hardcoded band-name string is needed here.
# A saved profile of the same name always takes priority over a built-in.

set -euo pipefail

PROFILES_DIR="/var/lib/mpd/alsaequal/profiles"

# name -> "31 63 125 250 500 1k 2k 4k 8k 16k" band levels, 0-100%
declare -A PRESETS=(
  [flat]="50 50 50 50 50 50 50 50 50 50"
  [off]="50 50 50 50 50 50 50 50 50 50"
  [vocal]="55 48 45 65 60 68 70 66 58 52"
  [vocal_male]="62 58 48 64 58 64 68 62 54 50"
  [vocal_female]="52 45 42 68 62 70 72 68 60 54"
  [speech]="48 45 55 70 58 68 72 70 62 50"
  [rock]="70 60 45 65 55 60 68 70 64 58"
  [pop]="65 58 50 60 55 58 62 64 60 56"
  [metal]="75 65 40 68 50 58 68 74 68 60"
  [hip_hop]="75 70 50 58 52 54 56 58 56 52"
  [rap]="72 68 48 62 54 60 64 62 56 52"
  [jazz]="60 55 55 58 56 58 60 58 54 52"
  [blues]="65 62 52 60 56 60 62 60 54 50"
  [classical]="55 52 52 56 54 56 58 56 54 52"
  [ambient]="52 50 48 54 52 54 56 54 56 58"
  [electronic]="70 65 48 65 52 56 62 66 64 60"
  [edm]="78 72 45 70 50 54 64 72 68 62"
  [bass_boost]="66 56 48 62 54 50 50 48 46 44"
  [treble_boost]="45 50 60 68 58 64 68 72 74 76"
  [warm]="58 56 54 52 52 50 48 46 44 42"
  [bright]="52 54 56 62 64 66 68 70 72 74"
)

usage() {
  echo "Usage: mpd-eq save <profile_name>" >&2
  echo "       mpd-eq load <profile_name>" >&2
  echo "       mpd-eq list" >&2
  echo "       mpd-eq presets" >&2
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
    if [ -f "${profile_file}" ]; then
      while IFS=: read -r control_name value; do
        amixer -D equal set "${control_name}" "${value}%" > /dev/null
      done < "${profile_file}"
      echo "Loaded EQ profile ${profile_file}."
    elif [ -n "${PRESETS[$2]+set}" ]; then
      read -ra band_values <<< "${PRESETS[$2]}"
      mapfile -t control_names < <(amixer -D equal scontrols | sed -e "s/.*'\(.*\)'.*/\1/")
      if [ "${#control_names[@]}" -ne "${#band_values[@]}" ]; then
        echo "Warning: preset has ${#band_values[@]} bands but this device exposes ${#control_names[@]}; applying what matches." >&2
      fi
      for i in "${!control_names[@]}"; do
        [ "${i}" -lt "${#band_values[@]}" ] || break
        amixer -D equal set "${control_names[${i}]}" "${band_values[${i}]}%" > /dev/null
      done
      echo "Loaded built-in preset '$2'."
    else
      echo "No such saved profile or built-in preset: $2" >&2
      exit 1
    fi
    ;;
  list)
    ls -1 "${PROFILES_DIR}" 2>/dev/null | sed 's/\.txt$//'
    ;;
  presets)
    for name in "${!PRESETS[@]}"; do
      echo "${name}"
    done | sort
    ;;
  *)
    usage
    ;;
esac

exit 0
EOF
chmod 0755 /usr/local/bin/mpd-eq

# Print a message to indicate completion
if [ "${AUTO_DETECT}" -eq 1 ]; then
  echo "ALSA equalizer configured for ${#DETECTED_DEVICES[@]} device(s), and"
  echo "${MPD_CONF} already updated to match. Restart mpd to pick it up:"
  echo "  sudo systemctl restart mpd"
else
  echo "ALSA equalizer configured. Update mpd.conf's local audio_output to"
  echo "use device \"equal\" instead of \"${SLAVE_DEVICE}\", then restart mpd."
fi
echo "Use 'sudo mpd-eq save <name>' / 'sudo mpd-eq load <name>' to manage custom"
echo "profiles, or 'sudo mpd-eq load <preset>' for a built-in preset (see"
echo "'sudo mpd-eq presets' for the list)."

exit 0
