# Lunaris on Gentoo

Lunaris (dwm + Quickshell sidebar + SDDM *Sugar Candy* login screen, Tokyo Night) was born on Arch Linux.
This guide covers installing and using it on **Gentoo Linux with OpenRC + elogind**. The same `install.sh`
detects Gentoo (`/etc/gentoo-release`) and takes the Gentoo path; nothing in the Arch path changed.
This repo (**lunaris-gentoo**) is the Gentoo edition; Arch users: <https://github.com/shahinabdi/lunaris>.

- [What is different on Gentoo](#what-is-different-on-gentoo)
- [Before you start](#before-you-start)
- [Install](#install)
- [What the installer does](#what-the-installer-does-on-gentoo)
- [Packages: Arch → Gentoo](#packages-arch--gentoo)
- [Login screen: SDDM + Sugar Candy](#login-screen-sddm--sugar-candy)
- [User guide](#user-guide)
- [Troubleshooting](#troubleshooting)
- [Uninstall / go back](#uninstall--go-back)
- [For maintainers: what was changed for Gentoo](#for-maintainers-what-was-changed-for-gentoo)

---

## What is different on Gentoo

| | Arch | Gentoo (OpenRC) |
|---|---|---|
| packages | `pacman` + AUR (`yay`) | `emerge` from `::gentoo` + the **GURU** overlay (+ `another-brave-overlay` for Brave) |
| package lists | `packages/core.txt`, `apps.txt`, `aur.txt` | `packages/gentoo/core.txt`, `guru.txt`, `apps.txt`, `apps-overlay.txt` |
| USE flags / keywords / licenses | — | `system/gentoo/etc/portage/package.{use,accept_keywords,license}/lunaris` |
| services | `systemctl enable` | `rc-update add` (dbus, elogind, NetworkManager, bluetooth, display-manager) |
| user services (picom, clipmenud, PipeWire) | systemd user units | started by `~/.xinitrc` through **`lunaris-svc`** (supervised, restart on crash) |
| session D-Bus | systemd user bus | `dbus-launch` in `~/.xinitrc` |
| suspend / reboot / shut down | `systemctl` | `loginctl` (elogind) — done by `dwm-power` automatically |
| weekly update check | `lunaris-update.timer` | `lunaris-update autocheck --loop` started by `~/.xinitrc` (`AUTOCHECK=1` in `~/.config/lunaris.conf`) |
| keyboard layout (system) | `localectl set-x11-keymap` | `/etc/X11/xorg.conf.d/00-keyboard.conf` written directly |
| monitor hotplug | `autorandr.service` + override | udev rule `/etc/udev/rules.d/90-lunaris-autorandr.rules` → `dwm-autorandr` |
| SDDM start | `systemctl enable sddm` | `DISPLAYMANAGER="sddm"` in `/etc/conf.d/display-manager` + `rc-update add display-manager default` |
| Qt theme | qt5ct | qt6ct (Gentoo has no qt5ct; `~/.xinitrc` picks whichever exists) |
| not packaged | — | capitaine-cursors, Vazirmatn font, xcolor → downloaded / `cargo install` by the installer |

Gentoo with **systemd** is not supported yet (the installer stops); the Arch code path would be the starting point.

## Before you start

1. **A desktop profile.** Lunaris needs the USE flags a desktop profile enables (`X`, `dbus`, `elogind`,
   `pulseaudio`/PipeWire, GTK, …). Check with `eselect profile show`. If it says `default/linux/amd64/23.0`:

   ```sh
   sudo eselect profile set default/linux/amd64/23.0/desktop
   sudo emerge -avuDN @world
   ```

   (The installer refuses to run on a non-desktop profile unless you pass `--any-profile`; then expect emerge to
   ask for many extra USE changes.) Keep `USE="-systemd -kde -gnome"` in `make.conf` if you have it.

2. **sudo**, and your user in the right groups:

   ```sh
   sudo emerge --noreplace app-admin/sudo app-eselect/eselect-repository dev-vcs/git
   sudo usermod -aG wheel,video,audio,input $USER     # video = brightness keys without root
   ```

3. **Optional but recommended: binary packages.** Qt 6, ffmpeg, kitty, OBS… are long builds. With the Gentoo
   binhost set up (`/etc/portage/binrepos.conf`), use them:

   ```sh
   EMERGE_OPTS="--getbinpkg --verbose --noreplace --ask" ./install.sh
   ```

4. **Rust (for the colour picker).** `xcolor` isn't packaged; the installer runs `cargo install --locked xcolor`
   if `cargo` exists (`sudo emerge dev-lang/rust-bin`). Without it everything else works; only `Mod+Shift+c` doesn't.

5. **Remove Portage's dwm** if you installed it (`x11-wm/dwm`): Lunaris builds its own patched dwm into
   `/usr/local/bin`. Two installed dwms means two "dwm" entries on the login screen.

   ```sh
   sudo emerge --deselect x11-wm/dwm && sudo emerge --depclean x11-wm/dwm
   ```

## Install

```sh
git clone https://github.com/shahinabdi/lunaris-gentoo.git ~/lunaris-gentoo
cd ~/lunaris-gentoo
./install.sh --dry-run             # see every step, change nothing
./install.sh                       # French AZERTY (default)
./install.sh --keyboard qwerty     # QWERTY (US / UK / most others)
```

Then **reboot** (SDDM starts and shows the dwm session), or without rebooting:
`sudo rc-service display-manager start`. With `--no-sddm`: log in on a TTY and run `startx`.

After the first login, run `./install.sh --configs` once more: it creates the noise-cancelling microphone, which
needs PipeWire running.

All options of the Arch installer work the same. Gentoo specifics:

| Option / variable | Effect on Gentoo |
|---|---|
| `--no-apps` | skip VS Code, Thunar, OBS, Brave, Obsidian, Proton Mail (and the Vazirmatn font) |
| `--no-aur` / `--no-overlay-apps` | skip only the overlay apps (Brave, Obsidian, Proton Mail) and Vazirmatn |
| `--any-profile` | don't stop when the profile isn't a desktop profile |
| `EMERGE_OPTS=…` | emerge options (default `--verbose --noreplace`, plus `--ask` in a terminal) |

## What the installer does on Gentoo

1. **Portage settings** — installs `/etc/portage/package.use/lunaris`, `package.accept_keywords/lunaris` and
   `package.license/lunaris`. If one of those is a single file instead of a directory, a block between
   `# BEGIN lunaris` / `# END lunaris` is added to it instead (a backup `*.bak-<date>` is kept). Re-running
   replaces only that block.
2. **Overlays** — `eselect repository enable guru` (+ `another-brave-overlay` with apps), then `emaint sync -r …`.
3. **Packages** — one `emerge` with all lists in `packages/gentoo/`.
4. **Extras** — capitaine-cursors (prebuilt release) → `/usr/share/icons/capitaine-cursors`; Vazirmatn →
   `/usr/local/share/fonts/vazirmatn`; `xcolor` → `~/.cargo/bin`. These are not owned by Portage.
5. **Configs** — same as Arch: every path of `manifest.txt` → `$HOME` (backups of files that differ).
   The systemd user units are copied too but unused on OpenRC.
6. **dwm** — clones/builds `~/lunaris-dwm` (`make KEYBOARD=… && sudo make install` → `/usr/local/bin/dwm`),
   links its scripts into `~/.local/bin`, compiles `xkb-group`.
7. **System** — touchpad (libinput), `dwm-autorandr` + its udev rule, keyboard layouts in
   `/etc/X11/xorg.conf.d/00-keyboard.conf`; `rc-update add dbus default`, `elogind boot`; SDDM (below);
   `NetworkManager` and `bluetooth` in the default runlevel. It warns when a `net.*` service is also in the default
   runlevel (it fights NetworkManager) and when you aren't in the `video` group.
8. **Microphone** — the RNNoise filter for your mic (only when PipeWire is running).

Re-running is safe: identical files are skipped, `emerge --noreplace` skips what is installed.

## Packages: Arch → Gentoo

| Purpose | Arch | Gentoo | Repo |
|---|---|---|---|
| sidebar | quickshell | `gui-apps/quickshell` (USE: X only, no Wayland/Hyprland) | GURU, `~amd64` |
| brightness | brightnessctl | `app-misc/brightnessctl[udev]` | GURU, `~amd64` |
| Nerd Fonts | ttf-jetbrains-mono-nerd, ttf-go-nerd | `media-fonts/nerdfonts[jetbrainsmono,gomono]` | GURU, `~amd64` |
| GTK theme | adw-gtk-theme | `x11-themes/adw-gtk3` | GURU, `~amd64` |
| dark Adwaita (GTK 2/3) | gnome-themes-extra | `x11-themes/gnome-themes-standard` | gentoo |
| audio | pipewire, pipewire-pulse, pipewire-alsa | `media-video/pipewire[sound-server,pipewire-alsa,bluetooth]` + `media-libs/libpulse` (pactl) | gentoo |
| noise-cancelling mic | noise-suppression-for-voice | `media-libs/noise-suppression-for-voice` | gentoo, `~amd64` |
| clipboard | clipmenu | `x11-misc/clipmenu[rofi,-dmenu]` | gentoo |
| monitors | autorandr | `x11-misc/autorandr[-udev,-systemd]` + Lunaris udev rule | gentoo |
| login screen | sddm, qt6-5compat, qt6-svg | `gui-apps/sddm[elogind]`, `gui-apps/sddm-gentoo-config`, `gui-libs/display-manager-init`, `dev-qt/qt5compat`, `dev-qt/qtsvg` | gentoo |
| Qt theme | qt5ct, qt6ct | `gui-apps/qt6ct` | gentoo |
| lock screen blur | (ffmpeg via deps) | `media-video/ffmpeg` | gentoo |
| VS Code | visual-studio-code-bin (AUR) | `app-editors/vscode` (license `Microsoft-vscode`) | gentoo |
| OBS | obs-studio | `media-video/obs-studio` | gentoo, `~amd64` |
| Obsidian | obsidian | `app-office/obsidian` (license `Obsidian-EULA`) | GURU, `~amd64` |
| Proton Mail | proton-mail-bin (AUR) | `mail-client/proton-mail-bin` | GURU, `~amd64` |
| Brave | brave-bin (AUR) | `www-client/brave-browser` | another-brave-overlay |
| cursors | capitaine-cursors | *not packaged* → downloaded (sainnhe/capitaine-cursors r5, dark) | — |
| Persian font | vazirmatn-fonts (AUR) | *not packaged* → downloaded (rastikerdar/vazirmatn v33.003) | — |
| colour picker | xcolor | *not packaged* → `cargo install --locked xcolor` | crates.io |

Everything else (kitty, rofi, picom, dunst, feh, maim, xclip, xdotool, flameshot, i3lock, fastfetch, htop,
NetworkManager, bluez, papirus, JetBrains Mono, DejaVu, xorg apps) has the same name under its Gentoo category,
see `packages/gentoo/core.txt`.

## Login screen: SDDM + Sugar Candy

The theme is in this repo: **`sddm/sugar-candy-dwm`** — Marian Arlt's *Sugar Candy* ported to Qt 6 (Gentoo's SDDM
0.21 greeter is Qt 6), Tokyo Night colours, keyboard layout on the login screen. The installer puts:

| File | Role |
|---|---|
| `/usr/share/sddm/themes/sugar-candy-dwm/` | the theme |
| `/etc/sddm.conf.d/10-dwm-btw.conf` | `Current=sugar-candy-dwm`, cursor, font, no on-screen keyboard, remember user/session |
| `/etc/sddm/Xsetup-dwm-btw` | runs SDDM's default Xsetup, then `setxkbmap -layout <your layouts>` |
| `/usr/local/bin/dwm-session` + `/usr/local/share/xsessions/dwm.desktop` | the "dwm" session = your `~/.xinitrc` |
| `/etc/conf.d/display-manager` | `DISPLAYMANAGER="sddm"` |
| runlevel `default` | `display-manager` |

and adds the `sddm` user to the `video` group (needed for GPU access, see the Gentoo wiki).
`gui-apps/sddm-gentoo-config` provides `/etc/sddm.conf.d/01gentoo.conf` (X11 display server).

Useful:

```sh
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sugar-candy-dwm   # preview inside your session
sudo rc-service display-manager restart                                       # restart the login screen
cat /var/log/sddm.log                                                          # why it failed
```

Your profile picture (sidebar → user card, `dwm-profile`) is copied to `/usr/share/sddm/faces/$USER.face.icon`
when sudo needs no password; otherwise copy it once by hand:
`sudo install -Dm644 ~/.face /usr/share/sddm/faces/$USER.face.icon`.

The login wallpaper: replace `sddm/sugar-candy-dwm/Backgrounds/wallpaper.jpg` (or edit `theme.conf`) and re-run
`./install.sh` (or copy the theme folder again).

## User guide

Everything in the main [README](README.md) applies (keys, workspaces, sidebar, bar, terminal, updates). The Gentoo
differences you notice day to day:

### Logging in
Pick **dwm** in the session menu of SDDM (it is remembered). `dwm-session` puts `~/.local/bin` and `~/.cargo/bin`
on `PATH` and runs `~/.xinitrc`.
If you use `startx` instead, add this to `~/.bash_profile` so the Lunaris commands are found:

```sh
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
```

### Keys and sidebar
`Mod+Shift+h` shows every keybinding, `Mod+a` opens the sidebar, `Mod+Return` a terminal, `Mod+d` the
launcher (rofi). Identical to Arch.

### Session services (`lunaris-svc`)
`~/.xinitrc` starts PipeWire (`gentoo-pipewire-launcher`), picom and clipmenud. They run as long as the X session
and picom/clipmenud are restarted if they crash (up to 5 times a minute).

```sh
lunaris-svc status picom          # running / stopped
lunaris-svc restart picom         # e.g. after editing ~/.config/picom/picom.conf
lunaris-svc restart pipewire      # audio stuck
ls $XDG_RUNTIME_DIR/lunaris/      # logs: picom.log, clipmenud.log, pipewire.log
```

### Power
Sidebar → Power, or `Mod+Escape`. Suspend, reboot and shut down go through **elogind** (`loginctl`), no password
needed for the active local session. Needs `elogind` running (`rc-service elogind status`).

### Updating
Two separate things:

- **Gentoo itself**: `sudo emaint sync -a && sudo emerge -avuDN @world` (GURU is synced with the rest).
- **Lunaris** (both repos): sidebar → ⚙ Settings → **Updates**, or `lunaris-update apply`. Checked every Tuesday
  10:00 by the session itself (at login, then hourly while logged in, if the week's check is due).
  `lunaris-update timer off` / `on` toggles it (writes `AUTOCHECK=0|1` in `~/.config/lunaris.conf`).
  When an update changes system files or package lists, `lunaris-update` offers to run `./install.sh --no-apps`.

### Keyboard layouts
`Mod+Space` cycles the layouts. To change them permanently: `./install.sh --layouts us,ir` (rewrites
`/etc/X11/xorg.conf.d/00-keyboard.conf` and the login screen's layout), and `dwm-keyboard set qwerty|azerty
[layouts]` for the dwm workspace keys. There's no `localectl` on OpenRC; editing `00-keyboard.conf` by hand is fine.

### Monitors
Plugging a screen in or out triggers udev → `dwm-autorandr` → `autorandr --change --default horizontal`: a saved
profile if there is one (`autorandr --save <name>`), else extended side by side. Sleeping monitors are left alone.
`Mod+Shift+d` / sidebar → Display for resolution and scaling.

### Brightness, audio, Bluetooth, Wi-Fi
- brightness keys / bar scroll: `brightnessctl`, needs you in the `video` group (log out and in after `usermod`).
- audio: PipeWire with the pulse server; `pavucontrol` on right-click of the volume block; the noise-cancelling
  mic appears as *Noise Canceling Microphone*.
- Bluetooth: sidebar → Bluetooth (`bluetoothctl` underneath), service `bluetooth` in the default runlevel.
- Wi-Fi: bar → network block (rofi menu), right click `nmtui`. NetworkManager must own the interface (see
  Troubleshooting).

### Colour picker, screenshots, clipboard
`Mod+Shift+c` (xcolor in `~/.cargo/bin`), `Print` / sidebar → Screenshot (maim, flameshot), `Mod+v` clipboard
history, `Mod+Shift+v` clears it. Same as Arch.

## Troubleshooting

**emerge stops with "The following USE changes are necessary" / "keyword changes"**
Your profile or existing USE flags differ from what was tested. Either add the lines emerge prints to your own
`/etc/portage/package.use/…` (or to `…/lunaris`), or let Portage write them:
`sudo emerge --autounmask-write <the atoms>` then `sudo dispatch-conf`, and run `./install.sh` again.
If you answered **Yes** at emerge's "add these changes?" prompt, the change is only *staged* as
`/etc/portage/package.use/._cfg0000_<file>` ("config file … needs updating") and emerge still stops: merge it with
`sudo dispatch-conf` (or delete the `._cfg*` file if the flag is already in `…/lunaris`) before re-running.

**`ERROR: elogind failed to start` … "already running"** — harmless. elogind was started at login by PAM/D-Bus,
outside OpenRC, so `rc-service elogind status` says *stopped* while the daemon runs. It is in the `boot` runlevel
now; from the next boot OpenRC starts and tracks it. (The installer now skips the start in that case.)

**"is not a desktop profile"** — see [Before you start](#before-you-start), or `--any-profile`.

**`media-sound/pulseaudio-daemon` blocks pipewire** — PipeWire is the sound server:
`sudo emerge --deselect media-sound/pulseaudio-daemon && sudo emerge --depclean pulseaudio-daemon`, then re-run.

**No network after reboot / NetworkManager doesn't see the cable**
A classic `net.<iface>` service (netifrc) and NetworkManager both manage the interface. Pick NetworkManager:
`sudo rc-update del net.enp… default` (the installer prints the name).

**Two "dwm" sessions on the login screen / old dwm starts** — `x11-wm/dwm` from Portage is installed, see
[Before you start](#before-you-start) (5).

**Black screen or no theme on the login screen**
`cat /var/log/sddm.log`. Check `dev-qt/qt5compat` and `dev-qt/qtsvg` are installed (the theme imports
`Qt5Compat.GraphicalEffects`), the `sddm` user is in `video`, and the preview command above. Low entropy can make
SDDM hang: enable `CONFIG_RANDOM_TRUST_CPU` or `rc-update add haveged boot`. NVIDIA: see the Gentoo wiki's SDDM page.

**Sidebar (Mod+a) doesn't open** — run `qs -c arch-sidebar` in a terminal to see the error. Usually
`gui-apps/quickshell` missing or `dev-qt/qtbase` without `dbus`/`vulkan`.

**No notifications / sidebar can't talk to dunst** — no session bus: `echo $DBUS_SESSION_BUS_ADDRESS` must not be
empty inside dwm. `~/.xinitrc` starts one with `dbus-launch` (from `sys-apps/dbus`) when systemd is absent; make sure
`dbus` is running (`rc-service dbus status`).

**No sound** — `lunaris-svc restart pipewire`, then `wpctl status`. Look at `$XDG_RUNTIME_DIR/lunaris/pipewire.log`.
`XDG_RUNTIME_DIR` must be set (elogind does it at login; if it's empty, elogind isn't running or `sys-auth/pambase`
lacks USE `elogind`).

**Suspend / reboot from the sidebar does nothing** — `loginctl reboot` in a terminal shows the error; usually elogind
isn't running: `sudo rc-update add elogind boot && sudo rc-service elogind start`.

**Brightness keys do nothing** — `brightnessctl set 10%-` in a terminal; "Permission denied" → `video` group, log out/in.

**Colour picker (Mod+Shift+c) does nothing** — `ls ~/.cargo/bin/xcolor`; install with `cargo install --locked xcolor`.

## Uninstall / go back

- back to `startx`: `sudo rc-update del display-manager default` (configs stay)
- remove the Portage settings: `sudo rm /etc/portage/package.{use,accept_keywords,license}/lunaris` (or delete the
  `# BEGIN/END lunaris` blocks), then `sudo emerge --depclean`
- dwm: `cd ~/lunaris-dwm && sudo make uninstall`
- the downloaded extras: `/usr/share/icons/capitaine-cursors`, `/usr/local/share/fonts/vazirmatn`,
  `cargo uninstall xcolor`
- system files: `/etc/udev/rules.d/90-lunaris-autorandr.rules`, `/usr/local/bin/dwm-autorandr`,
  `/etc/X11/xorg.conf.d/{00-keyboard,30-touchpad}.conf`, `/etc/sddm.conf.d/10-dwm-btw.conf`, `/etc/sddm/Xsetup-dwm-btw`,
  `/usr/share/sddm/themes/sugar-candy-dwm`, `/usr/local/bin/dwm-session`, `/usr/local/share/xsessions/dwm.desktop`
- your old configs are next to the new ones as `*.bak-<date>`

## For maintainers: what was changed for Gentoo

**lunaris** (this repo)

| File | Change |
|---|---|
| `install.sh` | detects Arch / Gentoo; Gentoo: Portage settings, overlays, emerge, extras, OpenRC services, SDDM via display-manager, keyboard file, udev rule; profile check. Fixed: a fresh install (no `~/.config/dwm-dev.conf`) made the script exit silently |
| `packages/gentoo/*.txt` | Gentoo package lists |
| `system/gentoo/etc/portage/package.{use,accept_keywords,license}/lunaris` | USE flags, `~amd64` keywords, licenses |
| `system/gentoo/etc/udev/rules.d/90-lunaris-autorandr.rules` | monitor hotplug without systemd |
| `home/.xinitrc` | works without systemd: session D-Bus, `lunaris-svc start-all`, update loop, qt5ct → qt6ct fallback |
| `home/.config/quickshell/arch-sidebar/modules/NotifStore.qml` | update icon also for emerge/portage notifications |
| `GENTOO.md` | this guide |

**lunaris-dwm**

| File | Change |
|---|---|
| `scripts/lunaris-svc` (new) | session services on any init: `systemctl --user` with systemd, supervised processes otherwise |
| `scripts/dwm-power` | `loginctl` (elogind) when there is no systemd |
| `scripts/dwm-clip` | starts clipmenud through `lunaris-svc` |
| `scripts/lunaris-update` | weekly check without systemd (`autocheck [--loop]`, `AUTOCHECK=` in `lunaris.conf`, `timer` reports `next=` the same way); `daemon-reload` only on systemd |

Tested on Gentoo amd64 (OpenRC 0.64, elogind 255): `install.sh --dry-run`, dwm + xkb-group build,
`lunaris-svc` supervisor (start / restart / stop / crash give-up), `lunaris-update timer status`, xcolor build with
Rust 1.98, package atoms resolved against `::gentoo` and GURU (Nov 2026).
