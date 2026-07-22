#!/usr/bin/bash
#
# grant-passwordless-sudo.sh - Add the invoking (non-root) user to the sudo
# group and grant them passwordless sudo access.
#
# Usage:
#   sudo ./grant-passwordless-sudo.sh
#
# Inputs:
#   None. Must be run via sudo (so $SUDO_USER identifies the real user;
#   running this directly as root has nothing to grant, since root
#   already has full access).
#
# Outputs:
#   Adds the user to the 'sudo' group and creates
#   /etc/sudoers.d/nopasswd_for_user granting NOPASSWD:ALL.

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
CURRENT_USER="${SUDO_USER}"

# Check if the user is already in the sudo group
if id "${CURRENT_USER}" | grep -q "sudo"; then
  echo "The user ${CURRENT_USER} is already in the sudo group."
else
  # Add the user to the sudo group
  usermod -aG sudo "${CURRENT_USER}"
  echo "User ${CURRENT_USER} has been added to the sudo group."
fi

# Create a file in /etc/sudoers.d/ with NOPASSWD option.
# sudoers.d files must be mode 0440, or sudo ignores them.
echo "${CURRENT_USER} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd_for_user
chmod 440 /etc/sudoers.d/nopasswd_for_user

# Print a message to indicate completion
echo "NOPASSWD has been enabled for user ${CURRENT_USER} for all commands."

exit 0
