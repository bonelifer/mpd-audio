# Changelog

All notable changes to this project are documented here.

## Initial Release — 2026-07-22 to 2026-07-28

### ✨ Features

- **Headless MPD audio server setup**: The full set of scripts for building a headless Music Player Daemon (MPD) audio server from scratch.
- **Bluetooth support**: Set up a Bluetooth audio sink and generate an `mpd.conf` with expanded output options.
- **Built-in ALSA EQ presets**: `setup-alsa-equalizer.sh` now ships with ready-to-use `mpd-eq` presets, and wraps all local audio outputs at once instead of just one.
- **Optional ALSA EQ web UI**: New `install-alsaequal-web-api.sh` installs a web interface for controlling the ALSA equalizer, with a credential-prompt install flow.
- **Shared configuration file**: A single `mpd-audio.conf` now feeds settings to `build-mpd.sh`, `setup-mergerfs.sh`, `generate-mpd-conf.sh`, and `setup-log-rotation.sh`, so you configure paths once instead of per-script.
- **Guided Docker setup**: `install-apps.sh` and `install-docker.sh` prompt with a simple yes/no before installing Docker, and `mkdc` setup follows automatically. Your homelab path is now saved to a config file instead of hardcoded.
- **Direct `/etc/mpd.conf` install**: `generate-mpd-conf.sh` can now copy its generated config straight to `/etc/mpd.conf` for you.

### 🔧 Improvements

- Menu and script run order now matches the recommended setup order from the README, with clearer prompts for optional arguments.
- Bluetooth setup now edits an existing `mpd.conf` in place rather than requiring a fresh one.
- Documentation now calls out the run-order dependency between the Bluetooth, MPD config generation, and ALSA EQ scripts, and marks the MPD-RIS2 installer as optional.

## Links

- [GitHub Repository](https://github.com/bonelifer/mpd-audio)
