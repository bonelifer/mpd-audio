#!/usr/bin/bash
#
# generate-mpd-conf.sh - Detect Creative/Sound Blaster USB audio devices
# and the built-in analog (PCH) output, and generate a template mpd.conf.
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
# device "hw:041e,324d". ReplayGain is enabled in "auto" mode. Playback
# state (queue, song position, volume) is persisted to state_file so it
# survives an MPD restart. auto_update is enabled so new library files are
# picked up automatically (via MPD's own inotify watch). An explicit
# log_file is set so log rotation (see setup-log-rotation.sh) has a file
# to act on.
#
# Inputs:
#   None. Reads USB device list via lsusb and ALSA devices via aplay -L.
#
# Outputs:
#   Writes ./mpd.conf in the current directory. Does not touch
#   /etc/mpd.conf - review the generated file, then copy it into place
#   manually.

set -euo pipefail

for cmd in lsusb aplay; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

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
    type   \"alsa\"
    name   \"Analog Output\"
    device \"${pch_device_field:-}\"
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
    type   \"alsa\"
    name   \"${output_name}\"
    device \"hw:${device_id}\"
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

# Define the mpd.conf text
mpd_conf="# For network
bind_to_address    \"any\"
port               \"6600\"

# Log destination. Explicit (rather than relying on journald) so
# setup-log-rotation.sh has a file to rotate.
log_file            \"/var/lib/mpd/log\"

# Persist playback state (queue, song position, volume) across restarts
state_file          \"/var/lib/mpd/state\"

# Enable stickers - myMPD uses stickers for play statistics
sticker_file        \"/var/lib/mpd/sticker.sql\"

# Enable stored playlists, also needed for myMPD smart playlists
playlist_directory  \"/var/lib/mpd/playlists\"

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
bind_to_address     \"/run/mpd/socket\"

# Mounting is only possible with the simple database plugin and a cache_directory
database {
    plugin          \"simple\"
    path            \"/var/lib/mpd/tag_cache\"
    cache_directory \"/var/lib/mpd/cache\"
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
    port        \"8000\"
    bitrate     \"128\"
    format      \"44100:16:1\"
    always_on   \"yes\"
    tags        \"yes\"
}

${local_audio_output}"

# Output the combined configuration to mpd.conf
echo "${mpd_conf}" > mpd.conf
echo "Generated ./mpd.conf. Review it, then copy it to /etc/mpd.conf."

exit 0
