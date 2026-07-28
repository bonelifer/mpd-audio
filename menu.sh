#!/usr/bin/bash
#
# menu.sh - Interactive menu to run the setup/install scripts in this
# directory.
#
# Intentionally does not use `set -e`: a sub-script failing should return
# control to the menu, not kill the whole loop.

set -uo pipefail

# Define the script file paths, in the README's recommended run order
UNATTENDED_SCRIPT="./setup-unattended-upgrades.sh"
SUDOER_SCRIPT="./grant-passwordless-sudo.sh"
INSTALL_APPS_SCRIPT="./install-apps.sh"
MERGERFS_SCRIPT="./setup-mergerfs.sh"
MPD_COMPILE_SCRIPT="./build-mpd.sh"
BLUETOOTH_SCRIPT="./setup-bluetooth-audio.sh"
GEN_MPD_CONF_SCRIPT="./generate-mpd-conf.sh"
INSTALL_MYMPD_SCRIPT="./install-mympd.sh"
INSTALL_MPDRIS2_SCRIPT="./install-mpdris2.sh"
LOG_ROTATION_SCRIPT="./setup-log-rotation.sh"
MPD2CHROMECAST_SCRIPT="./install-mpd2chromecast.sh"
ALSA_EQUALIZER_SCRIPT="./setup-alsa-equalizer.sh"
GPODDER_CLI_SCRIPT="./install-gpodder-cli.sh"

while true; do
    # Display the menu
    clear
    echo "Select an option:"
    echo "1. Run setup-unattended-upgrades.sh"
    echo "2. Run grant-passwordless-sudo.sh"
    echo "3. Run install-apps.sh"
    echo "4. Run setup-mergerfs.sh"
    echo "5. Run build-mpd.sh"
    echo "6. Run setup-bluetooth-audio.sh"
    echo "7. Run generate-mpd-conf.sh"
    echo "8. Run install-mympd.sh"
    echo "9. Run install-mpdris2.sh"
    echo "10. Run setup-log-rotation.sh"
    echo "11. Run install-mpd2chromecast.sh"
    echo "12. Run setup-alsa-equalizer.sh"
    echo "13. Run install-gpodder-cli.sh"
    echo "14. Quit (or press 'q' to quit)"

    # Read the user's choice
    read -r -p "Enter the number of your choice: " choice

    case "${choice}" in
        1)
            sudo "${UNATTENDED_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        2)
            sudo "${SUDOER_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        3)
            sudo "${INSTALL_APPS_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        4)
            sudo "${MERGERFS_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        5)
            sudo "${MPD_COMPILE_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        6)
            sudo "${BLUETOOTH_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        7)
            # Does not need root; runs as the invoking user
            "${GEN_MPD_CONF_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        8)
            sudo "${INSTALL_MYMPD_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        9)
            sudo "${INSTALL_MPDRIS2_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        10)
            sudo "${LOG_ROTATION_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        11)
            sudo "${MPD2CHROMECAST_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        12)
            sudo "${ALSA_EQUALIZER_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        13)
            sudo "${GPODDER_CLI_SCRIPT}"
            read -r -p "Press Enter to continue..."
            ;;
        14|q)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice. Please enter a valid option (1-14 or 'q')."
            read -r -p "Press Enter to continue..."
            ;;
    esac
done
