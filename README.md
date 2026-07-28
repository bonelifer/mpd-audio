# mpd-audio

Scripts to set up a headless Debian/Ubuntu box as a Music Player Daemon (MPD)
audio server, with myMPD (web UI), mpDris2 (MPRIS2/D-Bus bridge), MergerFS
pooled storage, Docker, and automatic security updates.

Run everything interactively via `menu.sh`, or run individual scripts
directly. Most scripts must be run as root (`sudo ./script.sh`); each checks
for this itself and exits with an error if not.

## Configuration

`build-mpd.sh`, `setup-mergerfs.sh`, `generate-mpd-conf.sh`, and
`setup-log-rotation.sh` read shared settings (MPD version, MergerFS
source/target directories, and `mpd.conf` paths/ports) from
`mpd-audio.conf` instead of hardcoded values. Copy the template and edit
it before running any of them:

```bash
cp mpd-audio.conf.example mpd-audio.conf
$EDITOR mpd-audio.conf
```

`mpd-audio.conf` is gitignored, so local edits won't conflict with a
future update to the scripts. `MERGERFS_SOURCE_DIRS`/`MERGERFS_TARGET_DIR`
must be changed from their placeholder values; everything else has a
working default.

`install-docker.sh`'s `HOMELAB_ROOT` (used by the `mkdc` helper it sets
up) works differently: you don't need to copy anything in advance - the
script prompts for it on first run and writes `install-docker.conf`
itself, so later runs don't ask again. Copy
`install-docker.conf.example` yourself only if you want to skip the
prompt entirely (e.g. for unattended provisioning).

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
3. **`install-apps.sh`** — creates `~/bin` for the invoking user and
   installs `mpc`, then prompts (30 second timeout, defaults to No)
   whether to also install Docker via `install-docker.sh` (which itself
   sets up the `mkdc` Compose-project helper, prompting for its root
   directory on first run and remembering it in `install-docker.conf`
   afterward). Other scripts assume `~/bin` and `mpc` are present; only
   proceed with Docker-dependent scripts if you accepted the Docker
   install.
4. **`setup-mergerfs.sh`** — reads `MERGERFS_SOURCE_DIRS`/`MERGERFS_TARGET_DIR`
   from `mpd-audio.conf` (see Configuration above; refuses to run if
   they're still the placeholder values). Installs MergerFS and
   registers a `mergerfs-pool.service` systemd unit that pools multiple
   source directories into one mount point (e.g. for a merged music
   library).
5. **`build-mpd.sh`** — compiles and installs MPD from source (version
   from `MPD_VERSION` in `mpd-audio.conf`, default `0.24.13`) with a
   broad set of input/output/decoder plugins enabled.
6. **`setup-bluetooth-audio.sh [MAC_ADDRESS]`** *(optional)* — pairs a
   Bluetooth A2DP speaker/receiver and installs BlueALSA so it can be
   added as a local `audio_output` in `mpd.conf`, alongside or instead of
   USB/PCH. If `MAC_ADDRESS` is omitted, it scans for nearby devices (15
   seconds) and prompts for one (15 second timeout). If `/etc/mpd.conf`
   already exists, it backs it up and appends a new `audio_output` block
   for the device directly (skipped if one for that MAC is already
   there, so it's safe to re-run); otherwise it just prints the block,
   since `generate-mpd-conf.sh` (next) will detect this now-paired device
   and offer to include it in the `mpd.conf` it generates. On first
   setup, run this *before* `generate-mpd-conf.sh` either way: that
   script only offers Bluetooth devices that are already paired.
7. **`generate-mpd-conf.sh`** — detects Creative/Sound Blaster USB audio
   devices, the built-in analog (PCH) output, and Bluetooth A2DP speakers
   already paired via the previous step (or manually with `bluetoothctl`;
   skipped with a note if `bluetoothctl` isn't installed), and writes a
   template `./mpd.conf` (network binding, socket, zeroconf/mDNS
   advertisement, log file, state persistence, auto-update on library
   changes, stickers, playlists, ReplayGain, symlink-following for
   MergerFS pools, HTTP stream output, and local ALSA output(s)) using
   the paths/ports from `mpd-audio.conf`. Prompts once whether to enable
   software mixing (`mixer_type "software"`) across all local ALSA
   outputs for a consistent volume curve, and, per Bluetooth device
   found, whether to include it. Each prompt times out (defaulting to
   No) if left unanswered. Does not need root (only the final copy step
   does, if `/etc/mpd.conf` isn't already writable by you). Finally
   prompts whether to copy the result to `/etc/mpd.conf` now; if it
   already exists there, it's backed up first, since
   `setup-bluetooth-audio.sh`/`setup-alsa-equalizer.sh` may have edited
   it directly since the last time you ran this script. Declining (or
   the timeout) leaves it for you to review and copy yourself, same as
   before.
8. **`install-mympd.sh`** — clones, builds, and installs myMPD (web UI for
   MPD) from source, and registers it as the `mympd` systemd service.
9. **`install-mpdris2.sh`** — run *after* `mpd.conf` is generated and
   installed. Builds and installs mpDris2 from source and writes
   `~/.config/mpDris2/mpDris2.conf` for the invoking user, using the
   `music_directory` read from `/etc/mpd.conf`.
10. **`setup-log-rotation.sh`** — run *after* `mpd.conf` is installed to
    `/etc/mpd.conf`, since that's what sets `log_file`. Installs a
    `logrotate` policy for `MPD_LOG_FILE` (from `mpd-audio.conf`, the
    same value `generate-mpd-conf.sh` used).
11. **`install-mpd2chromecast.sh`** *(optional)* — clones, installs, and
    runs [mpd2chromecast](https://github.com/dresdner353/mpd2chromecast)
    as a systemd service, relaying MPD playback to Chromecast/Google Home
    devices on the LAN. Its "Cast MPD Output Stream" mode uses the
    `httpd` output already in `mpd.conf`.
12. **`setup-alsa-equalizer.sh [SLAVE_DEVICE]`** *(optional)* — run
    *after* `mpd.conf` is installed to `/etc/mpd.conf`. Wraps output
    device(s) with a 10-band ALSA equalizer (`libasound2-plugin-equal`),
    and installs an `mpd-eq` helper for saving/loading named EQ profiles
    as plain text, plus built-in presets (`mpd-eq load rock`, `mpd-eq
    presets` to list them all) matching
    [alsaequal-web-api](https://github.com/bonelifer/alsaequal-web-api)'s
    browser/HTTP presets exactly. With no argument, it reads every local
    `alsa` `audio_output` already in `/etc/mpd.conf` (PCH/USB/BlueALSA -
    whichever `generate-mpd-conf.sh` configured), wraps *all* of them
    (sharing one EQ so `mpd-eq`/`eqctl` control every output at once),
    and rewrites each block's `device` in `/etc/mpd.conf` to point at its
    new wrapped PCM (backing up `/etc/mpd.conf` first; already-wrapped
    devices are skipped, so it's safe to re-run). Passing `SLAVE_DEVICE`
    explicitly wraps only that one device as plain `equal`, and leaves
    `mpd.conf` for you to update yourself, same as before.
13. **`install-alsaequal-web-api.sh`** *(optional)* — run *after*
    `setup-alsa-equalizer.sh`. Clones (or updates)
    [alsaequal-web-api](https://github.com/bonelifer/alsaequal-web-api)
    to `~/alsaequal-web-api` and runs its own installer, which sets up a
    browser/HTTP front-end (port 5000) for applying the same named EQ
    presets as `mpd-eq`, as a systemd service (`eqctl`). Interactive: on
    first install it prompts for the HTTP Basic Auth username/password
    the service will require (rejecting blank values or the placeholder
    `changeme`), so have those ready.
14. **`install-gpodder-cli.sh [DOWNLOAD_DIR]`** *(optional)* — installs
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
| `install-apps.sh` | yes (via sudo) | Create invoking user's `~/bin`; install `mpc`; prompts whether to delegate to `install-docker.sh`. |
| `install-docker.sh` | yes (via sudo) | Install Docker CE from the official apt repo; add invoking user to the `docker` group; add the `mkdc` helper to their `~/.bashrc`. |
| `setup-mergerfs.sh` | yes | Pool storage directories with MergerFS as a systemd service. |
| `build-mpd.sh` | yes | Compile and install MPD from source (meson/ninja). |
| `setup-bluetooth-audio.sh` | yes | Pair a Bluetooth A2DP device, install BlueALSA, and add/update its `audio_output` in `mpd.conf` if the file exists. |
| `generate-mpd-conf.sh` | no* | Detect audio hardware, generate `./mpd.conf`, and optionally copy it to `/etc/mpd.conf` (*needs root for that step if not already writable). |
| `install-mympd.sh` | yes | Build/install myMPD and register its systemd service. |
| `install-mpdris2.sh` | yes (via sudo) | Build/install mpDris2 and write its per-user config. |
| `setup-log-rotation.sh` | yes | Install a `logrotate` policy for MPD's log file. |
| `install-mpd2chromecast.sh` | yes (via sudo) | Install mpd2chromecast and register it as a systemd service for Chromecast/Google Home playback. |
| `setup-alsa-equalizer.sh` | yes | Wrap all (or one, if given) output device(s) with a 10-band ALSA EQ, updating `mpd.conf` to match, and install the `mpd-eq` save/load helper. |
| `install-alsaequal-web-api.sh` | yes (via sudo) | Clone/update and install [alsaequal-web-api](https://github.com/bonelifer/alsaequal-web-api) as the `eqctl` systemd service. |
| `install-gpodder-cli.sh` | yes (via sudo) | Install `gpo` (gPodder CLI) and operation helper scripts into the invoking user's `~/bin`. |

## Notes

- Scripts that need the real invoking user (not root) rely on `$SUDO_USER`,
  so they must be run with `sudo` from a regular user's shell, not while
  already logged in as root.
- `build-mpd.sh` and `install-mympd.sh` build from source and install to the
  default prefix (typically `/usr/local`); re-running `install-mympd.sh`
  pulls the latest upstream changes and rebuilds.
- `generate-mpd-conf.sh` always writes to `./mpd.conf` in the current
  directory first, so you can review it either way. Copying it to
  `/etc/mpd.conf` is opt-in (a y/n prompt, 30 second timeout, defaults
  to No) rather than automatic.
- `generate-mpd-conf.sh` only offers Bluetooth devices already paired
  (e.g. via `setup-bluetooth-audio.sh` or manually with `bluetoothctl`)
  that advertise the A2DP "Audio Sink" service — it doesn't pair new
  devices itself.
- Edit `mpd-audio.conf` (see Configuration above) before running
  `setup-mergerfs.sh`, `build-mpd.sh`, `generate-mpd-conf.sh`, or
  `setup-log-rotation.sh` — all four read their settings from there
  instead of hardcoded values in the scripts.
- `setup-bluetooth-audio.sh` only edits `mpd.conf` if `/etc/mpd.conf`
  already exists (backing it up first, like `setup-alsa-equalizer.sh`);
  otherwise it prints the `audio_output {}` block instead, since there's
  nothing yet to append to. Its pairing flow relies on Simple Secure
  Pairing (no PIN prompt); devices that require a PIN or on-device
  confirmation must be paired manually with `bluetoothctl`.
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
  since it's a shared system-wide file. In auto-detect mode (no
  argument) it also backs up and rewrites `/etc/mpd.conf`
  (`/etc/mpd.conf.bak.<timestamp>`) — the only script in this project
  that touches `mpd.conf` directly, everywhere else prints instructions
  for you to apply by hand. Every wrapped output shares one `ctl.equal`
  control surface, so `mpd-eq`/`alsaequal-web-api` apply one EQ curve to
  all of them at once rather than each having independent settings.
  `libasound2-plugin-equal` (the package formerly named `alsaequal`)
  stores band gains in an opaque binary file, editable only through an
  ALSA mixer — `mpd-eq` works around that by round-tripping the same
  controls through `amixer` as plain "name:value" text profiles under
  `/var/lib/mpd/alsaequal/profiles/`.
- `install-alsaequal-web-api.sh` is a thin wrapper: it only clones/updates
  the repo and delegates to that project's own `install.sh`, rather than
  duplicating its apt/systemd setup here. It doesn't wire the ALSA
  `equal` device itself — that's `setup-alsa-equalizer.sh`'s job, and
  must run first.
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

## Contributing

Contributions are welcome!

- **Bug reports**: [Open an issue](https://github.com/bonelifer/mpd-audio/issues).
- **Everything else** (questions, feature requests, ideas, general discussion): [Use Discussions](https://github.com/bonelifer/mpd-audio/discussions).
- Pull requests are welcome for bug fixes or discussed features.
