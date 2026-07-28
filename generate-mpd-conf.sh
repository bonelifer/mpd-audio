#!/usr/bin/bash
#
# generate-mpd-conf.sh - Detect Creative/Sound Blaster USB audio devices,
# the built-in analog (PCH) output, and paired Bluetooth A2DP speakers, and
# generate a template mpd.conf.
#
# IMPORTANT - run order: pair Bluetooth devices with
# setup-bluetooth-audio.sh BEFORE running this script - it only offers
# devices that are already paired. Run setup-alsa-equalizer.sh AFTER
# this script, not before - it reads /etc/mpd.conf to find what to wrap.
# Once /etc/mpd.conf exists, both of those scripts edit it directly; if
# you re-run this script later (e.g. to add a new USB device) and accept
# its offer to copy the result into /etc/mpd.conf, that overwrites
# whatever they added. It's backed up first, but you'd need to re-run
# them again afterward to restore those output blocks.
#
# Combines the previous audio.sh (USB device scan) and gen-mpd-conf.sh
# (mpd.conf generation) into one pass, so the USB scan only runs once and
# no longer round-trips through an intermediate usb-audio.txt file.
#
# The HTTP stream output is always included. If a USB audio device is
# found, it is used as the local output, and you're prompted (10 second
# timeout, defaults to No) whether to also include the built-in analog
# (PCH) output alongside it. If no USB device is found, PCH is used
# automatically as a fallback if present. Each detected USB device's
# vendor:product ID is wrapped in a proper audio_output {} block, e.g.
# device "hw:041e,324d". Separately, any Bluetooth device already paired
# (e.g. via setup-bluetooth-audio.sh) that advertises the A2DP "Audio
# Sink" service is offered, one prompt per device (10 second timeout,
# defaults to No), and can be added alongside whatever USB/PCH output was
# already selected. bluetoothctl is optional - if it isn't installed,
# Bluetooth detection is skipped with a note rather than an error. A single
# up-front prompt (30 second timeout, defaults to No), with an explanation
# of the tradeoff, asks whether to add
# mixer_type "software" to every local ALSA output, for a consistent volume
# curve across mixed hardware. Every local ALSA output also gets
# always_on "yes" unconditionally, so MPD keeps the device open between
# tracks instead of reopening it each time - this avoids audible pops and,
# for the Bluetooth output, re-establishing the A2DP stream on every song.
# music_directory comes from MPD_MUSIC_DIRECTORY in mpd-audio.conf (edit
# it there if your library lives elsewhere, e.g. a MergerFS pool from
# setup-mergerfs.sh), along with follow_outside_symlinks/
# follow_inside_symlinks "yes" so a MergerFS pool built from symlinked
# sources is scanned fully. zeroconf_enabled "yes" is also set
# unconditionally, with zeroconf_name including the host's hostname
# (via `hostname`), so this MPD instance is discoverable on the LAN and
# distinguishable from others. ReplayGain is enabled in "auto"
# mode. Playback state (queue, song position, volume) is persisted to
# state_file so it survives an MPD restart. auto_update is enabled so new
# library files are picked up automatically (via MPD's own inotify watch).
# An explicit log_file is set so log rotation (see setup-log-rotation.sh)
# has a file to act on.
#
# Inputs:
#   None. Reads USB device list via lsusb, ALSA devices via aplay -L, and
#   (if bluetoothctl is installed) paired Bluetooth devices via
#   bluetoothctl. Paths and ports (music_directory, log_file, state_file,
#   sticker_file, playlist_directory, database paths, MPD/HTTP ports) come
#   from mpd-audio.conf - copy mpd-audio.conf.example to mpd-audio.conf
#   and edit it first.
#
# Outputs:
#   Writes ./mpd.conf in the current directory. Then prompts (30 second
#   timeout, defaults to No) whether to copy it to /etc/mpd.conf; if
#   declined (or the file already exists and you decline), review it and
#   copy it into place yourself.

set -euo pipefail

for cmd in lsusb aplay; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

# Load MPD_MUSIC_DIRECTORY, MPD_LOG_FILE, and the other mpd.conf paths/ports
# from the shared config file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/mpd-audio.conf"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "${CONFIG_FILE} not found. Copy mpd-audio.conf.example to mpd-audio.conf and edit it, then re-run." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Ask once, up front, whether to use software mixing on ALSA outputs, so the
# same answer applies uniformly to every local output (USB/PCH/Bluetooth)
# built below. Software mixing gives a consistent volume curve across mixed
# hardware instead of relying on each card's own hardware mixer.
mixer_line=""
echo "Software mixing (mixer_type \"software\") gives one consistent volume"
echo "control across mixed ALSA outputs (USB/PCH/Bluetooth), since each"
echo "card's own hardware mixer can differ in range and step, and some"
echo "outputs (e.g. Bluetooth via bluealsa) don't expose one at all. It"
echo "costs a bit of extra CPU (MPD resamples volume in software instead"
echo "of the hardware doing it), which matters more on low-power boards."
echo "Skip it if you only use a single output and prefer its native"
echo "hardware mixer, or CPU headroom is tight."
use_software_mixer="n"
if read -t 30 -r -p "Enable software mixing for local ALSA outputs? [y/N]: " use_software_mixer; then
  :
else
  echo
  echo "No response within 30 seconds; defaulting to No."
fi
if [[ "${use_software_mixer,,}" == "y" || "${use_software_mixer,,}" == "yes" ]]; then
  mixer_line='
    mixer_type      "software"'
fi

# Scan USB devices for Creative/Sound Blaster hardware
declare -A device_ids
while IFS= read -r line; do
  if echo "${line}" | grep -qi 'Sound Blaster Play' || echo "${line}" | grep -qi 'Creative'; then
    vendor_id="$(echo "${line}" | awk '{print $6}' | cut -d':' -f1)"
    product_id="$(echo "${line}" | awk '{print $6}' | cut -d':' -f2)"
    device_ids["${vendor_id},${product_id}"]=1
  fi
done <<< "$(lsusb)"

# Detect the built-in analog (PCH) output up front, regardless of whether
# a USB device is also present, since USB-found still needs to know if
# PCH is available to offer it as an addition.
pch_available=0
alsa_output="$(aplay -L)"
if [[ "${alsa_output}" == *hw:CARD=PCH* ]]; then
  pch_available=1
  pch_device_field="hw:CARD=PCH"
  if [[ "${alsa_output}" == *hw:CARD=PCH,DEV=* ]]; then
    pch_device_field="$(echo "${alsa_output}" | grep -oP 'hw:CARD=PCH,DEV=[0-9]+' | head -1)"
  fi
fi
pch_block="audio_output {
    type      \"alsa\"
    name      \"Analog Output\"
    device    \"${pch_device_field:-}\"
    always_on \"yes\"${mixer_line}
}
"

# Build the local audio_output section: USB device(s) if found, otherwise
# fall back to the built-in analog (PCH) output if present.
#
# NOTE: an associative array with zero elements is treated as "unset" by
# `set -u` even after `declare -A` - a known bash quirk. Measure its size
# with nounset briefly disabled rather than referencing it directly.
set +u
usb_device_count="${#device_ids[@]}"
set -u

local_audio_output=""
if [ "${usb_device_count}" -gt 0 ]; then
  echo "USB audio device(s) found."
  device_num=0
  for device_id in "${!device_ids[@]}"; do
    device_num=$((device_num + 1))
    output_name="USB Audio Output"
    if [ "${usb_device_count}" -gt 1 ]; then
      output_name="USB Audio Output ${device_num}"
    fi
    local_audio_output+="audio_output {
    type      \"alsa\"
    name      \"${output_name}\"
    device    \"hw:${device_id}\"
    always_on \"yes\"${mixer_line}
}

"
  done

  # USB is already covered; PCH is optional here. Ask, defaulting to No
  # if there's no answer within 10 seconds.
  if [ "${pch_available}" -eq 1 ]; then
    include_pch="n"
    if read -t 10 -r -p "Also include the built-in analog (PCH) output alongside USB? [y/N]: " include_pch; then
      :
    else
      echo
      echo "No response within 10 seconds; defaulting to No."
    fi
    if [[ "${include_pch,,}" == "y" || "${include_pch,,}" == "yes" ]]; then
      local_audio_output+="${pch_block}"
      echo "Added the built-in analog (PCH) output alongside USB."
    fi
  fi
else
  echo "No USB audio devices found; checking for built-in analog (PCH) output."
  if [ "${pch_available}" -eq 1 ]; then
    local_audio_output="${pch_block}"
    echo "Audio output section for the built-in analog device (PCH) has been added to mpd.conf."
  else
    echo "Built-in analog audio device (PCH) not found either; only the HTTP stream output will be configured."
  fi
fi

# Detect paired Bluetooth A2DP sink devices (paired via setup-bluetooth-audio.sh
# or manually with bluetoothctl), so they can be offered as an audio_output
# alongside whatever USB/PCH output was selected above. Only devices
# advertising the A2DP "Audio Sink" service (UUID 0000110b) are considered, to
# avoid offering paired non-audio devices like keyboards or mice.
declare -A bt_devices
if command -v bluetoothctl &>/dev/null; then
  while IFS= read -r line; do
    if [[ "${line}" =~ ^Device\ ([0-9A-Fa-f:]+)\ (.+)$ ]]; then
      bt_mac="${BASH_REMATCH[1]}"
      bt_name="${BASH_REMATCH[2]}"
      if bluetoothctl info "${bt_mac}" 2>/dev/null | grep -qi '0000110b'; then
        bt_devices["${bt_mac}"]="${bt_name}"
      fi
    fi
  done <<< "$(bluetoothctl devices Paired 2>/dev/null || true)"
else
  echo "bluetoothctl not found; skipping Bluetooth device detection."
fi

set +u
bt_device_count="${#bt_devices[@]}"
set -u

if [ "${bt_device_count}" -gt 0 ]; then
  echo "Paired Bluetooth audio device(s) found."
  bt_num=0
  for bt_mac in "${!bt_devices[@]}"; do
    bt_num=$((bt_num + 1))
    bt_name="${bt_devices[${bt_mac}]}"
    output_name="Bluetooth Output"
    if [ "${bt_device_count}" -gt 1 ]; then
      output_name="Bluetooth Output ${bt_num}"
    fi
    include_bt="n"
    if read -t 10 -r -p "Include Bluetooth device '${bt_name}' (${bt_mac}) as an audio output? [y/N]: " include_bt; then
      :
    else
      echo
      echo "No response within 10 seconds; defaulting to No."
    fi
    if [[ "${include_bt,,}" == "y" || "${include_bt,,}" == "yes" ]]; then
      local_audio_output+="audio_output {
    type      \"alsa\"
    name      \"${output_name}\"
    device    \"bluealsa:DEV=${bt_mac},PROFILE=a2dp\"
    always_on \"yes\"${mixer_line}
}

"
      echo "Added Bluetooth device '${bt_name}' as an audio output."
    fi
  done
fi

# Define the mpd.conf text
mpd_zeroconf_name="MPD - $(hostname)"
mpd_conf="# For network
bind_to_address    \"any\"
port               \"${MPD_PORT}\"

# Advertise this MPD instance over mDNS/Avahi so zeroconf-aware clients can
# auto-discover it on the LAN. Name includes the hostname to tell multiple
# MPD instances apart.
zeroconf_enabled   \"yes\"
zeroconf_name      \"${mpd_zeroconf_name}\"

# Root directory MPD scans for your music library. Edit MPD_MUSIC_DIRECTORY
# in mpd-audio.conf if your library lives elsewhere (e.g. a MergerFS pool
# from setup-mergerfs.sh).
music_directory     \"${MPD_MUSIC_DIRECTORY}\"

# Follow symlinks in music_directory, in and out of it, so a MergerFS pool
# built from symlinked source directories (setup-mergerfs.sh) is scanned
# fully rather than silently skipped.
follow_outside_symlinks \"yes\"
follow_inside_symlinks  \"yes\"

# Log destination. Explicit (rather than relying on journald) so
# setup-log-rotation.sh has a file to rotate.
log_file            \"${MPD_LOG_FILE}\"

# Persist playback state (queue, song position, volume) across restarts
state_file          \"${MPD_STATE_FILE}\"

# Enable stickers - myMPD uses stickers for play statistics
sticker_file        \"${MPD_STICKER_FILE}\"

# Enable stored playlists, also needed for myMPD smart playlists
playlist_directory  \"${MPD_PLAYLIST_DIRECTORY}\"

# Enable metadata. If set to none, you can only browse the filesystem
metadata_to_use     \"AlbumArtist,Artist,Album,Title,Track,Disc,Genre,Name\"

# Enable ReplayGain volume normalization. \"auto\" applies per-track gain
# in random/single-track playback and per-album gain when playing
# consecutive tracks from the same album.
replaygain           \"auto\"

# Automatically update the database when files change in music_directory
# (uses inotify internally; no external watcher needed)
auto_update          \"yes\"

# bind mpd to a unix socket
# Only socket connection to mpd enables some myMPD auto configuration features
bind_to_address     \"${MPD_SOCKET}\"

# Mounting is only possible with the simple database plugin and a cache_directory
database {
    plugin          \"simple\"
    path            \"${MPD_DB_PATH}\"
    cache_directory \"${MPD_CACHE_DIRECTORY}\"
}

# Enable neighbor plugins
neighbors {
    plugin          \"udisks\"
}
neighbors {
    plugin          \"upnp\"
}

# Output for http stream - myMPD local playback
audio_output {
    type        \"httpd\"
    name        \"HTTP Stream\"
    encoder     \"lame\" #to support safari on ios
    port        \"${MPD_HTTP_PORT}\"
    bitrate     \"128\"
    format      \"44100:16:1\"
    always_on   \"yes\"
    tags        \"yes\"
}

${local_audio_output}"

# Output the combined configuration to mpd.conf
echo "${mpd_conf}" > mpd.conf
echo "Generated ./mpd.conf."

# Offer to copy it into place. Declining (or timing out) leaves the
# previous manual review-and-copy step available, unchanged.
MPD_CONF_LIVE="/etc/mpd.conf"
copy_to_etc="n"
if read -t 30 -r -p "Copy ./mpd.conf to ${MPD_CONF_LIVE} now? [y/N]: " copy_to_etc; then
  :
else
  echo
  echo "No response within 30 seconds; defaulting to No."
fi

if [[ "${copy_to_etc,,}" == "y" || "${copy_to_etc,,}" == "yes" ]]; then
  can_write=1
  if [ -f "${MPD_CONF_LIVE}" ]; then
    [ -w "${MPD_CONF_LIVE}" ] || can_write=0
  else
    [ -w "$(dirname "${MPD_CONF_LIVE}")" ] || can_write=0
  fi

  if [ "${can_write}" -eq 0 ]; then
    echo "No permission to write ${MPD_CONF_LIVE}. Re-run with sudo for this step, or:" >&2
    echo "  sudo cp mpd.conf ${MPD_CONF_LIVE}" >&2
  else
    if [ -f "${MPD_CONF_LIVE}" ]; then
      BACKUP_FILE="${MPD_CONF_LIVE}.bak.$(date +%Y%m%d%H%M%S)"
      cp "${MPD_CONF_LIVE}" "${BACKUP_FILE}"
      echo "Backed up existing ${MPD_CONF_LIVE} to ${BACKUP_FILE}."
      echo "Note: this overwrites any audio_output changes"
      echo "setup-bluetooth-audio.sh or setup-alsa-equalizer.sh made directly"
      echo "to ${MPD_CONF_LIVE} - re-run them afterward if you need those back."
    fi
    cp mpd.conf "${MPD_CONF_LIVE}"
    echo "Copied ./mpd.conf to ${MPD_CONF_LIVE}. Restart mpd to pick it up:"
    echo "  sudo systemctl restart mpd"
  fi
else
  echo "Review ./mpd.conf, then copy it to ${MPD_CONF_LIVE} yourself."
fi

exit 0
