#!/usr/bin/bash
#
# setup-bluetooth-audio.sh - Pair a Bluetooth A2DP speaker/receiver and
# expose it as an ALSA output via BlueALSA, for use as an MPD audio_output.
#
# Uses BlueALSA (the "bluealsa" package) rather than PulseAudio/PipeWire,
# so the resulting device can be dropped straight into an
# `audio_output { type "alsa" ... }` block, matching the USB/PCH outputs
# generate-mpd-conf.sh already produces.
#
# Usage:
#   sudo ./setup-bluetooth-audio.sh [MAC_ADDRESS]
#
#   If MAC_ADDRESS is omitted, the script scans for nearby devices and
#   prompts for one (15 second scan, 15 second prompt timeout).
#
# Inputs:
#   $1 (optional) - Bluetooth MAC address of the target device, e.g.
#                    AA:BB:CC:DD:EE:FF. Must be run as root.
#
# Outputs:
#   Installs bluez and bluealsa. Enables and starts the bluetooth and
#   bluealsa services. Pairs, trusts, and connects the target device.
#   Does not modify mpd.conf - prints the audio_output {} block to add
#   manually, consistent with generate-mpd-conf.sh.
#
# Caveats:
#   Pairing relies on bluetoothctl's default no-input/no-output agent,
#   which auto-confirms Simple Secure Pairing. Devices that require a PIN
#   or on-device confirmation are not supported by this script; pair them
#   manually with `bluetoothctl` instead.

set -euo pipefail

# Check if the script is running as root
if [ "${EUID}" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo." >&2
  exit 1
fi

# Verify required commands are available before doing any work
for cmd in bluetoothctl systemctl; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "Required command '${cmd}' not found. Install it and re-run." >&2
    exit 1
  fi
done

SCAN_SECONDS=15

# Install bluez (bluetoothctl/bluetoothd) and bluealsa (ALSA PCM bridge)
if ! command -v bluetoothd &>/dev/null || ! dpkg -s bluealsa &>/dev/null; then
  apt update
  apt install -y bluealsa bluez
fi

# Enable and start the bluetooth and bluealsa services
systemctl enable bluetooth.service bluealsa.service
systemctl start bluetooth.service bluealsa.service

MAC_ADDRESS="${1:-}"

# If no MAC address was given, scan for nearby devices and prompt for one
if [ -z "${MAC_ADDRESS}" ]; then
  bluetoothctl power on
  bluetoothctl agent on
  bluetoothctl default-agent

  echo "Scanning for Bluetooth devices for ${SCAN_SECONDS} seconds..."
  bluetoothctl scan on &>/dev/null &
  SCAN_PID="$!"
  sleep "${SCAN_SECONDS}"
  kill "${SCAN_PID}" &>/dev/null || true
  bluetoothctl scan off &>/dev/null || true

  echo "Discovered devices:"
  bluetoothctl devices

  if ! read -t 15 -r -p "Enter the MAC address to pair [15s timeout]: " MAC_ADDRESS; then
    echo
    echo "No response within 15 seconds; aborting." >&2
    exit 1
  fi
  if [ -z "${MAC_ADDRESS}" ]; then
    echo "No MAC address entered; aborting." >&2
    exit 1
  fi
fi

bluetoothctl power on
bluetoothctl agent on
bluetoothctl default-agent

# Pair, trust, and connect the target device
bluetoothctl pair "${MAC_ADDRESS}"
bluetoothctl trust "${MAC_ADDRESS}"
bluetoothctl connect "${MAC_ADDRESS}"

echo
echo "Paired, trusted, and connected ${MAC_ADDRESS}."
echo "Add this to mpd.conf as a local audio_output (see generate-mpd-conf.sh):"
echo
echo "audio_output {"
echo "    type   \"alsa\""
echo "    name   \"Bluetooth Output\""
echo "    device \"bluealsa:DEV=${MAC_ADDRESS},PROFILE=a2dp\""
echo "}"

exit 0
