# mpd-audio

Scripts to set up a headless Debian/Ubuntu box as a Music Player Daemon (MPD)
audio server, with myMPD (web UI), mpDris2 (MPRIS2/D-Bus bridge), MergerFS
pooled storage, Docker, and automatic security updates.

Run everything interactively via `menu.sh`, or run individual scripts
directly. Most scripts must be run as root (`sudo ./script.sh`); each checks
for this itself and exits with an error if not.

## Quick start

```bash
chmod +x *.sh
./menu.sh
```

`menu.sh` presents a numbered list and runs the corresponding script with
`sudo` where needed. It does not exit on a sub-script failure — it returns
you to the menu so you can retry or move on.

## Recommended order

1. **`setup-unattended-upgrades.sh`** — installs and configures
   `unattended-upgrades` for automatic security updates.
2. **`grant-passwordless-sudo.sh`** — adds the invoking user to the `sudo`
   group and grants passwordless sudo (`/etc/sudoers.d/nopasswd_for_user`).
   Run with `sudo` as the target user, not directly as root.
3. **`install-apps.sh`** — creates `~/bin` for the invoking user, appends
   the `mkdc` helper function to their `~/.bashrc`, then installs `mpc`
   and Docker (via `install-docker.sh`). Other scripts assume these are
   present.
4. **`setup-mergerfs.sh`** — *edit `SOURCE_DIRS` and `TARGET_DIR` at the top
   of the script first.* Installs MergerFS and registers a
   `mergerfs-pool.service` systemd unit that pools multiple source
   directories into one mount point (e.g. for a merged music library).
5. **`build-mpd.sh`** — compiles and installs MPD from source (default
   version `0.24.13`, edit `MPD_VERSION` to change it) with a broad set of
   input/output/decoder plugins enabled.
6. **`generate-mpd-conf.sh`** — detects Creative/Sound Blaster USB audio
   devices and the built-in analog (PCH) output, and writes a template
   `./mpd.conf` (network binding, socket, log file, state persistence,
   auto-update on library changes, stickers, playlists, ReplayGain, HTTP
   stream output, and a local ALSA output). Does not need root. Review the
   generated file, then copy it to `/etc/mpd.conf` yourself.
7. **`install-mympd.sh`** — clones, builds, and installs myMPD (web UI for
   MPD) from source, and registers it as the `mympd` systemd service.
8. **`install-mpdris2.sh`** — run *after* `mpd.conf` is generated and
   installed. Builds and installs mpDris2 from source and writes
   `~/.config/mpDris2/mpDris2.conf` for the invoking user, using the
   `music_directory` read from `/etc/mpd.conf`.
9. **`setup-bluetooth-audio.sh`** *(optional)* — pairs a Bluetooth A2DP
   speaker/receiver and installs BlueALSA so it can be added as a local
   `audio_output` in `mpd.conf`, alongside or instead of USB/PCH.
10. **`setup-log-rotation.sh`** — run *after* `mpd.conf` is installed to
    `/etc/mpd.conf`, since that's what sets `log_file`. Installs a
    `logrotate` policy for `/var/lib/mpd/log`.
11. **`install-mpd2chromecast.sh`** *(optional)* — clones, installs, and
    runs [mpd2chromecast](https://github.com/dresdner353/mpd2chromecast)
    as a systemd service, relaying MPD playback to Chromecast/Google Home
    devices on the LAN. Its "Cast MPD Output Stream" mode uses the
    `httpd` output already in `mpd.conf`.
12. **`setup-alsa-equalizer.sh`** *(optional)* — wraps a chosen output
    device (USB/PCH/BlueALSA) with a 10-band ALSA equalizer
    (`libasound2-plugin-equal`) named `equal`, and installs an `mpd-eq`
    helper for saving/loading named EQ profiles as plain text. Point
    `mpd.conf`'s local `audio_output` at `device "equal"` afterward.
13. **`install-gpodder-cli.sh [DOWNLOAD_DIR]`** *(optional)* — installs
    `gpo`, the text-mode CLI for [gPodder](https://gpodder.org/), plus
    operation helper scripts (`gpo-login`, `gpo-update`, `gpo-download`,
    `gpo-subscribe`, `gpo-unsubscribe`, `gpo-list`, `gpo-info`,
    `gpo-search`, `gpo-toplist`) into the invoking user's `~/bin`.
    `DOWNLOAD_DIR` (arg, or prompted, or left blank for gpo's own
    default) can point episode downloads at, e.g., a path under the MPD
    music library. Unrelated to MPD itself otherwise — useful if this
    box also manages podcast downloads.

## Scripts

| Script | Root? | Purpose |
|---|---|---|
| `menu.sh` | — | Interactive menu that runs the other scripts. |
| `setup-unattended-upgrades.sh` | yes | Enable automatic security updates. |
| `grant-passwordless-sudo.sh` | yes (via sudo) | Add invoking user to `sudo` group with NOPASSWD. |
| `install-apps.sh` | yes (via sudo) | Create invoking user's `~/bin`; add `mkdc` function to their `~/.bashrc`; install `mpc`; delegates to `install-docker.sh`. |
| `install-docker.sh` | yes (via sudo) | Install Docker CE from the official apt repo; add invoking user to the `docker` group. |
| `setup-mergerfs.sh` | yes | Pool storage directories with MergerFS as a systemd service. |
| `build-mpd.sh` | yes | Compile and install MPD from source (meson/ninja). |
| `generate-mpd-conf.sh` | no | Detect audio hardware and generate `./mpd.conf`. |
| `install-mympd.sh` | yes | Build/install myMPD and register its systemd service. |
| `install-mpdris2.sh` | yes (via sudo) | Build/install mpDris2 and write its per-user config. |
| `setup-bluetooth-audio.sh` | yes | Pair a Bluetooth A2DP device and install BlueALSA for use as an MPD `audio_output`. |
| `setup-log-rotation.sh` | yes | Install a `logrotate` policy for MPD's log file. |
| `install-mpd2chromecast.sh` | yes (via sudo) | Install mpd2chromecast and register it as a systemd service for Chromecast/Google Home playback. |
| `setup-alsa-equalizer.sh` | yes | Wrap an output device with a 10-band ALSA EQ and install the `mpd-eq` save/load helper. |
| `install-gpodder-cli.sh` | yes (via sudo) | Install `gpo` (gPodder CLI) and operation helper scripts into the invoking user's `~/bin`. |

## Notes

- Scripts that need the real invoking user (not root) rely on `$SUDO_USER`,
  so they must be run with `sudo` from a regular user's shell, not while
  already logged in as root.
- `build-mpd.sh` and `install-mympd.sh` build from source and install to the
  default prefix (typically `/usr/local`); re-running `install-mympd.sh`
  pulls the latest upstream changes and rebuilds.
- `generate-mpd-conf.sh` never touches `/etc/mpd.conf` directly — it only
  writes to the current directory so you can review the result first.
- Edit the placeholder values in `setup-mergerfs.sh` (`SOURCE_DIRS`,
  `TARGET_DIR`) and `build-mpd.sh` (`MPD_VERSION`) before running them.
- `setup-bluetooth-audio.sh` never touches `mpd.conf` either — it prints the
  `audio_output {}` block to add manually, same as `generate-mpd-conf.sh`.
  Its pairing flow relies on Simple Secure Pairing (no PIN prompt); devices
  that require a PIN or on-device confirmation must be paired manually with
  `bluetoothctl`.
- `setup-log-rotation.sh` only covers MPD's own log
  (`/var/lib/mpd/log`, set via `log_file` in `mpd.conf`). myMPD and
  mpDris2 run under systemd with no dedicated log file in this setup, so
  their output goes to the journal, which journald rotates on its own.
  It uses `copytruncate` instead of a reload signal, since MPD has no
  documented signal for reopening its log file after rotation.
- `install-mpd2chromecast.sh` clones/updates `~<user>/mpd2chromecast` and
  installs Python packages via apt where available, falling back to `pip3`
  (with `--break-system-packages` only when the PEP 668
  `EXTERNALLY-MANAGED` marker is present) — a more portable check than
  upstream's own installer, which assumes an integer `VERSION_ID` from
  `/etc/os-release` and breaks on Ubuntu's `22.04`-style versioning. Its
  web control interface (device selection, cast mode) listens on port
  `8090`.
- `setup-alsa-equalizer.sh` writes/overwrites `/etc/asound.conf`,
  backing up any existing copy first (`/etc/asound.conf.bak.<timestamp>`)
  since it's a shared system-wide file. `libasound2-plugin-equal` (the
  package formerly named `alsaequal`) stores band gains in an opaque
  binary file, editable only through an ALSA mixer — `mpd-eq` works
  around that by round-tripping the same controls through `amixer` as
  plain "name:value" text profiles under
  `/var/lib/mpd/alsaequal/profiles/`.
- `install-gpodder-cli.sh` avoids Debian's `gpodder` apt package
  (bundles the GTK GUI, pulling in `gir1.2-gtk-3.0`/`python3-gi`/etc.
  even though `gpo` itself never imports them) by installing from source
  via `pipx` instead, with `GPODDER_INSTALL_UIS=cli` and `pip install
  --no-deps` to skip gpodder's declared `PyGObject`/`dbus-python`
  dependencies (GTK-only; would otherwise need GObject-Introspection/
  D-Bus build headers). The three packages `gpo` actually imports
  (`podcastparser`, `mygpoclient`, `requests`) are added afterward via
  `pipx inject`. `gpo` has no dedicated login command — `gpo-login`
  configures gpodder.net credentials via `gpo set mygpo.*` instead, the
  closest real equivalent. Similarly, the download directory isn't a
  `gpo set` key either — it's the `GPODDER_DOWNLOAD_DIR` environment
  variable (default `~/gPodder/Downloads`), which is why a custom
  `DOWNLOAD_DIR` gets baked into `gpo-update`/`gpo-download` as an
  `export` line rather than passed to `gpo` as a config setting.

## License

This project is licensed under the **GNU General Public License v3.0**.

See [LICENSE](LICENSE) for more information.
