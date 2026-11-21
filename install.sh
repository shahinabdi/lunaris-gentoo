#!/usr/bin/env bash
# install.sh — set up the Lunaris desktop on Arch Linux or Gentoo (OpenRC). See GENTOO.md for Gentoo.
#
#   ./install.sh               everything: packages, apps, configs, dwm, services
#   ./install.sh --dry-run     show what would happen, change nothing
#   ./install.sh --link        symlink configs to this repo instead of copying
#                              (edits in ~/.config then land in the repo directly)
#   ./install.sh --no-apps     skip workspace apps (Thunar, Obsidian, OBS, Brave, Code, Proton Mail)
#   ./install.sh --no-aur      skip AUR packages (and installing yay)
#                              Gentoo: skip the apps from overlays (Brave, Obsidian, Proton Mail; also --no-overlay-apps)
#   ./install.sh --configs     only deploy configs (no packages, no dwm build, no services)
#   ./install.sh --no-sddm     keep logging in with startx (no SDDM login screen)
#   ./install.sh --keyboard qwerty   QWERTY keys: Mod + 1 … 0 for workspaces, Mod + . / , for screens
#                              (default: azerty — Mod + & é " ' ( - è _ ç à, Mod + ; / ,)
#   ./install.sh --layouts us,ir     keyboard layouts, Mod+Space cycles (default fr,ir / us,ir with qwerty)
#   ./install.sh --any-profile       Gentoo: don't stop when the Portage profile is not a desktop profile
#
# Env: DWM_DIR (default: the folder saved in ~/.config/dwm-dev.conf, else ~/lunaris-dwm)
#      DWM_REPO (default https://github.com/shahinabdi/lunaris-dwm.git)
#      EMERGE_OPTS (Gentoo, default "--verbose --noreplace", plus --ask in a terminal)
#
# Existing files that differ are backed up as <file>.bak-<timestamp> before being replaced.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# existing installs keep their dwm folder (saved by a previous run), new ones use ~/lunaris-dwm
[ -n "${DWM_DIR:-}" ] || DWM_DIR=$(sed -n 's/^DWM_DIR=//p' "$HOME/.config/dwm-dev.conf" 2>/dev/null | tr -d "\"'" || true)
DWM_DIR=${DWM_DIR:-$HOME/lunaris-dwm}
DWM_REPO=${DWM_REPO:-https://github.com/shahinabdi/lunaris-dwm.git}
STAMP=$(date +%Y%m%d-%H%M%S)

DRY=0 LINK=0 APPS=1 AUR=1 ONLY_CONFIGS=0 SDDM=1 KEYBOARD="" LAYOUTS="" ANY_PROFILE=0
while (( $# )); do
	a=$1; shift
	case $a in
		--keyboard=*) KEYBOARD=${a#*=} ;;
		--keyboard)   KEYBOARD=${1:-}; shift || true ;;
		--layouts=*)  LAYOUTS=${a#*=} ;;
		--layouts)    LAYOUTS=${1:-}; shift || true ;;
		--dry-run) DRY=1 ;;
		--link)    LINK=1 ;;
		--no-apps) APPS=0 ;;
		--no-aur|--no-overlay-apps) AUR=0 ;;
		--any-profile) ANY_PROFILE=1 ;;
		--configs) ONLY_CONFIGS=1 ;;
		--no-sddm) SDDM=0 ;;
		-h|--help) sed -n '2,23p' "$0"; exit 0 ;;
		*) echo "unknown option: $a (see --help)" >&2; exit 1 ;;
	esac
done

# keyboard profile: option > existing ~/.config/dwm-btw.conf > azerty
KBD_CONF=$HOME/.config/dwm-btw.conf
KBD_GIVEN=0; [ -n "$KEYBOARD$LAYOUTS" ] && KBD_GIVEN=1
if [ -f "$KBD_CONF" ]; then
	# shellcheck disable=SC1090
	old=$( . "$KBD_CONF"; echo "${KEYBOARD:-}|${LAYOUTS:-}")
	# keep the saved layouts only when the profile is not being changed on the command line
	if [ -z "$KEYBOARD" ]; then KEYBOARD=${old%%|*}; [ -n "$LAYOUTS" ] || LAYOUTS=${old#*|}; fi
fi
KEYBOARD=${KEYBOARD:-azerty}
case $KEYBOARD in azerty|qwerty) ;; *) echo "--keyboard must be azerty or qwerty" >&2; exit 1 ;; esac
if [ -z "$LAYOUTS" ]; then [ "$KEYBOARD" = qwerty ] && LAYOUTS=us,ir || LAYOUTS=fr,ir; fi
[[ $LAYOUTS =~ ^[a-z]+(\([a-z0-9_-]+\))?(,[a-z]+(\([a-z0-9_-]+\))?)*$ ]] || { echo "bad --layouts: $LAYOUTS" >&2; exit 1; }

c_blue=$'\e[1;34m' c_yel=$'\e[1;33m' c_red=$'\e[1;31m' c_dim=$'\e[2m' c_off=$'\e[0m'
step() { printf '\n%s==> %s%s\n' "$c_blue" "$*" "$c_off"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$c_yel" "$*" "$c_off"; }
die()  { printf '%s  x %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }
run()  { if (( DRY )); then printf '    %s[dry] %s%s\n' "$c_dim" "$*" "$c_off"; else "$@"; fi; }

pkgs() { grep -vE '^\s*(#|$)' "$REPO/packages/$1" | tr -s ' \n' ' '; }

# ---------------------------------------------------------------- checks
if   [ -f /etc/arch-release ];   then DISTRO=arch
elif [ -f /etc/gentoo-release ]; then DISTRO=gentoo
else die "This installer is for Arch Linux or Gentoo."; fi
(( EUID != 0 )) || die "Run as your normal user (sudo is used when needed), not as root."
command -v sudo >/dev/null || die "sudo is required."
if [ "$DISTRO" = gentoo ]; then
	[ -d /run/systemd/system ] && die "Gentoo with systemd is not supported yet — this installer expects OpenRC + elogind (see GENTOO.md)."
	command -v rc-update >/dev/null || die "OpenRC (rc-update) not found."
	if (( ! ONLY_CONFIGS && ! ANY_PROFILE )) && ! eselect profile show 2>/dev/null | grep -q '/desktop'; then
		die "Portage profile is not a desktop profile ($(eselect profile show 2>/dev/null | tail -1 | tr -d ' ')).
    Lunaris needs X, D-Bus, PipeWire... USE flags that the desktop profile turns on:
        sudo eselect profile set default/linux/amd64/23.0/desktop
        sudo emerge -avuDN @world
    then run ./install.sh again (or pass --any-profile to continue anyway, see GENTOO.md)."
	fi
fi

# ---------------------------------------------------------------- packages
# portage_conf <package.use|package.accept_keywords|package.license>: Lunaris' file in /etc/portage/<kind>/lunaris
# (or, when <kind> is a single file, a "# BEGIN/END lunaris" block inside it)
portage_conf() {
	local kind=$1 src="$REPO/system/gentoo/etc/portage/$1/lunaris" dst="/etc/portage/$1" tmp
	if [ -f "$dst" ]; then
		tmp=$(mktemp)
		sed '/^# BEGIN lunaris$/,/^# END lunaris$/d' "$dst" > "$tmp"
		{ echo "# BEGIN lunaris"; cat "$src"; echo "# END lunaris"; } >> "$tmp"
		if cmp -s "$tmp" "$dst"; then rm -f "$tmp"; return; fi
		run sudo cp "$dst" "$dst.bak-$STAMP"
		run sudo install -m644 "$tmp" "$dst"; rm -f "$tmp"
		info "$dst (block \"lunaris\", backup $dst.bak-$STAMP)"
	else
		run sudo install -Dm644 "$src" "$dst/lunaris"
		info "$dst/lunaris"
	fi
}

# enable_overlay <name>: eselect repository enable + sync (once)
enable_overlay() {
	if [ -d "/var/db/repos/$1" ] || portageq get_repo_path / "$1" >/dev/null 2>&1; then info "overlay $1: enabled"; return; fi
	command -v eselect >/dev/null && eselect repository list >/dev/null 2>&1 ||
		die "eselect-repository is needed for the $1 overlay:  sudo emerge app-eselect/eselect-repository"
	run sudo eselect repository enable "$1"
	run sudo emaint sync -r "$1"
}

install_packages_gentoo() {
	step "Portage settings (USE flags, keywords, licenses)"
	portage_conf package.use
	portage_conf package.accept_keywords
	portage_conf package.license

	step "Overlays"
	command -v eselect >/dev/null && eselect repository list >/dev/null 2>&1 ||
		run sudo emerge --noreplace app-eselect/eselect-repository
	enable_overlay guru   # quickshell, brightnessctl, nerdfonts, adw-gtk3
	(( APPS && AUR )) && enable_overlay another-brave-overlay

	step "Packages (emerge)"
	local list opts
	list="$(pkgs gentoo/core.txt) $(pkgs gentoo/guru.txt)"
	(( APPS )) && list+=" $(pkgs gentoo/apps.txt)"
	(( APPS && AUR )) && list+=" $(pkgs gentoo/apps-overlay.txt)"
	opts=${EMERGE_OPTS:---verbose --noreplace}
	[ -t 0 ] && [ -z "${EMERGE_OPTS:-}" ] && opts+=" --ask"
	info "emerge $opts <$(wc -w <<<"$list") packages>"
	# shellcheck disable=SC2086
	run sudo emerge $opts $list ||
		die "emerge failed. If it asks for USE/keyword changes, add them to /etc/portage/package.*/lunaris (or run
    emerge with --autounmask-write, then dispatch-conf) and run ./install.sh again. See GENTOO.md → Troubleshooting."

	extras_gentoo
}

# not packaged for Gentoo: capitaine-cursors (cursor theme), Vazirmatn (Persian font), xcolor (colour picker)
extras_gentoo() {
	step "Extras that Gentoo doesn't package"
	local tmp
	if [ -f /usr/share/icons/capitaine-cursors/index.theme ]; then info "capitaine-cursors: installed"
	else
		info "capitaine-cursors -> /usr/share/icons/capitaine-cursors"
		if (( ! DRY )); then
			tmp=$(mktemp -d)
			curl -fsSL -o "$tmp/c.zip" https://github.com/sainnhe/capitaine-cursors/releases/download/r5/Linux.zip &&
			unzip -q "$tmp/c.zip" 'Capitaine Cursors/*' -d "$tmp" &&
			sed -i 's/^Name=.*/Name=capitaine-cursors/' "$tmp/Capitaine Cursors/index.theme" &&
			sudo mkdir -p /usr/share/icons/capitaine-cursors &&
			sudo cp -r "$tmp/Capitaine Cursors/." /usr/share/icons/capitaine-cursors/ &&
			sudo chmod -R a+rX /usr/share/icons/capitaine-cursors ||
				warn "could not install capitaine-cursors (cursor falls back to the default theme)"
			rm -rf "$tmp"
		fi
	fi
	if (( APPS && AUR )); then
		if fc-list 2>/dev/null | grep -qi vazirmatn; then info "Vazirmatn font: installed"
		else
			info "Vazirmatn font -> /usr/local/share/fonts/vazirmatn"
			if (( ! DRY )); then
				tmp=$(mktemp -d)
				curl -fsSL -o "$tmp/v.zip" https://github.com/rastikerdar/vazirmatn/releases/download/v33.003/vazirmatn-v33.003.zip &&
				unzip -q "$tmp/v.zip" -d "$tmp/v" &&
				sudo install -d /usr/local/share/fonts/vazirmatn &&
				find "$tmp/v/fonts/ttf" -maxdepth 1 -name 'Vazirmatn-*.ttf' -exec sudo install -m644 -t /usr/local/share/fonts/vazirmatn {} + ||
					warn "could not install the Vazirmatn font"
				rm -rf "$tmp"
			fi
		fi
	fi
	if command -v xcolor >/dev/null || [ -x "$HOME/.cargo/bin/xcolor" ]; then info "xcolor: installed"
	elif command -v cargo >/dev/null; then
		info "xcolor (colour picker, Mod+Shift+c) -> ~/.cargo/bin (cargo install)"
		run cargo install --locked xcolor || warn "cargo install xcolor failed (Mod+Shift+c won't work)"
	else
		warn "xcolor not installed (colour picker, Mod+Shift+c): emerge dev-lang/rust-bin, then: cargo install --locked xcolor"
	fi
}

install_packages() {
	[ "$DISTRO" = gentoo ] && { install_packages_gentoo; return; }
	step "Official packages"
	local list
	list=$(pkgs core.txt)
	(( APPS )) && list+=" $(pkgs apps.txt)"
	# shellcheck disable=SC2086
	run sudo pacman -S --needed --noconfirm $list

	if (( APPS && AUR )); then
		step "AUR packages"
		if ! command -v yay >/dev/null; then
			info "installing yay (AUR helper)"
			local tmp; tmp=$(mktemp -d)
			run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
			(( DRY )) || (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
			rm -rf "$tmp"
		fi
		# shellcheck disable=SC2086
		run yay -S --needed --noconfirm --answerdiff None --answerclean None $(pkgs aur.txt)
	fi
}

# ---------------------------------------------------------------- configs
# put_file <src in repo> <dest>  — copy (or symlink) with backup, @HOME@ substituted
put_file() {
	local src=$1 dst=$2
	[ -d "$(dirname "$dst")" ] || run mkdir -p "$(dirname "$dst")"
	if (( LINK )) && ! grep -q '@HOME@' "$src" 2>/dev/null; then
		if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then return; fi
		[ -e "$dst" ] || [ -L "$dst" ] && run mv "$dst" "$dst.bak-$STAMP" && info "backup: ${dst/#$HOME/\~}.bak-$STAMP"
		run ln -s "$src" "$dst"
		return
	fi
	local tmp; tmp=$(mktemp)
	sed "s|@HOME@|$HOME|g" "$src" > "$tmp"
	if [ -e "$dst" ] && ! [ -L "$dst" ] && cmp -s "$tmp" "$dst"; then rm -f "$tmp"; return; fi
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		run mv "$dst" "$dst.bak-$STAMP"; info "backup: ${dst/#$HOME/\~}.bak-$STAMP"
	fi
	if (( DRY )); then rm -f "$tmp"; printf '    %s[dry] install %s%s\n' "$c_dim" "${dst/#$HOME/\~}" "$c_off"
	else install -m "$(stat -c %a "$src")" "$tmp" "$dst"; rm -f "$tmp"; fi
}

deploy_configs() {
	step "Configs -> \$HOME $( (( LINK )) && echo '(symlinks)' || echo '(copies)')"
	local p src f
	while read -r p; do
		[[ -z $p || $p == \#* ]] && continue
		src="$REPO/home/$p"
		[ -e "$src" ] || { warn "missing in repo: $p"; continue; }
		if [ -d "$src" ]; then
			while IFS= read -r -d '' f; do
				put_file "$f" "$HOME/$p/${f#"$src"/}"
			done < <(find "$src" -type f -print0)
		else
			put_file "$src" "$HOME/$p"
		fi
		info "$p"
	done < "$REPO/manifest.txt"
	run mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers" "$HOME/.local/bin"
	# starter wallpapers (never overwrites); the dwm repo's current.jpg is added after it is cloned
	for f in "$REPO"/wallpapers/*; do
		[ -e "$HOME/Pictures/Wallpapers/$(basename "$f")" ] || run cp "$f" "$HOME/Pictures/Wallpapers/"
	done
	[ -d /run/systemd/system ] && { (( DRY )) || systemctl --user daemon-reload 2>/dev/null || true; }
	# updates: where this repo is (lunaris-update), and the weekly check (every Tuesday)
	if (( ! DRY )); then   # keep other keys (TERMINAL=…) of lunaris.conf
		touch "$HOME/.config/lunaris.conf"
		sed -i '/^LUNARIS_DIR=/d' "$HOME/.config/lunaris.conf"
		printf 'LUNARIS_DIR=%q\n' "$REPO" >> "$HOME/.config/lunaris.conf"
	fi
	# folders open in Thunar (kitty registers itself for folders too), terminal apps use the default terminal
	run xdg-mime default thunar.desktop inode/directory 2>/dev/null || true
	command -v dwm-term >/dev/null && run dwm-term setup
	info "default terminal: kitty (sidebar → ⚙ Settings → Terminal to change it)"
	if [ -d /run/systemd/system ]; then
		run systemctl --user enable --now lunaris-update.timer 2>/dev/null || warn "could not enable the weekly update check (lunaris-update timer on)"
	elif (( ! DRY )) && ! grep -q '^AUTOCHECK=' "$HOME/.config/lunaris.conf"; then
		echo "AUTOCHECK=1" >> "$HOME/.config/lunaris.conf"   # no systemd: checked by the X session (~/.xinitrc)
	fi
	info "updates: checked every Tuesday; Settings → Updates in the sidebar, or lunaris-update"
}

# noise-cancelling mic: needs the name of this machine's microphone
deploy_mic_filter() {
	step "Noise-cancelling microphone (RNNoise)"
	local dst="$HOME/.config/pipewire/pipewire.conf.d/99-input-denoising.conf" mic=""
	local LINK=0   # generated per machine: always a real file, never a symlink
	if command -v pactl >/dev/null && pactl info >/dev/null 2>&1; then
		mic=$(pactl list sources short | awk '$2 ~ /^alsa_input/ {print $2}' | grep -i -m1 'mic' ||
		      pactl list sources short | awk '$2 ~ /^alsa_input/ {print $2; exit}')
	fi
	if [ -z "$mic" ]; then
		warn "no microphone found (PipeWire not running yet?) — rerun ./install.sh --configs after logging in"
		return
	fi
	info "microphone: $mic"
	local tmp; tmp=$(mktemp)
	sed "s|@MIC_SOURCE@|$mic|g" "$REPO/templates/99-input-denoising.conf.in" > "$tmp"
	put_file "$tmp" "$dst"; rm -f "$tmp"
	if (( ! DRY )); then
		if [ -d /run/systemd/system ]; then systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null || true
		else gentoo-pipewire-launcher restart >/dev/null 2>&1 & sleep 2; fi
		for _ in 1 2 3 4 5 6 7 8 9 10; do pactl list sources short 2>/dev/null | grep -q rnnoise_source && break; sleep 0.5; done
		pactl set-default-source rnnoise_source 2>/dev/null && info "default mic: Noise Canceling Microphone" || true
	fi
}

# ---------------------------------------------------------------- dwm + scripts
build_dwm() {
	step "dwm ($DWM_DIR)"
	if [ "$DISTRO" = gentoo ] && portageq has_version / x11-wm/dwm 2>/dev/null; then
		warn "x11-wm/dwm (Portage) is installed too: SDDM would list two \"dwm\" sessions, and /usr/bin/dwm is not Lunaris."
		warn "Remove it:  sudo emerge --deselect x11-wm/dwm && sudo emerge --depclean x11-wm/dwm"
	fi
	if [ ! -d "$DWM_DIR/.git" ]; then
		[ -e "$DWM_DIR" ] && die "$DWM_DIR exists but is not a git checkout; set DWM_DIR=... to use another folder"
		run git clone "$DWM_REPO" "$DWM_DIR"
	elif [ -z "$(git -C "$DWM_DIR" status --porcelain --untracked-files=no -- . ':!dwm' ':!*.o')" ]; then
		run git -C "$DWM_DIR" pull --ff-only || warn "could not update $DWM_DIR (continuing with local copy)"
	else
		warn "$DWM_DIR has local changes — not pulling, building as is"
	fi
	info "keyboard profile: $KEYBOARD"
	if (( DRY )); then info "[dry] make clean && make KEYBOARD=$KEYBOARD && sudo make install"
	else (cd "$DWM_DIR" && make clean >/dev/null && make KEYBOARD="$KEYBOARD" && sudo make install); fi

	step "dwm helper scripts -> ~/.local/bin"
	local s
	for s in "$DWM_DIR"/scripts/*; do
		[ -f "$s" ] && [ -x "$s" ] || continue
		run ln -sfn "$s" "$HOME/.local/bin/$(basename "$s")"
		info "$(basename "$s")"
	done
	if [ -f "$DWM_DIR/scripts/xkb-group.c" ]; then
		run cc -O2 -o "$HOME/.local/bin/xkb-group" "$DWM_DIR/scripts/xkb-group.c" -lX11
		info "xkb-group (compiled)"
	fi
	(( DRY )) || printf 'DWM_DIR=%q\n' "$DWM_DIR" > "$HOME/.config/dwm-dev.conf"
	[ -f "$DWM_DIR/current.jpg" ] && [ ! -e "$HOME/Pictures/Wallpapers/mountain-lake.jpg" ] &&
		run cp "$DWM_DIR/current.jpg" "$HOME/Pictures/Wallpapers/mountain-lake.jpg"

	case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
		warn "~/.local/bin is not in PATH — add to ~/.bashrc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
	esac
}

# ---------------------------------------------------------------- system
# /etc/X11/xorg.conf.d/00-keyboard.conf (what localectl writes on systemd systems)
write_xkb_conf() {
	local tmp; tmp=$(mktemp)
	cat > "$tmp" <<-EOF
		# Written by Lunaris install.sh (--keyboard / --layouts); dwm-keyboard set only changes the session
		Section "InputClass"
		        Identifier "system-keyboard"
		        MatchIsKeyboard "on"
		        Option "XkbLayout" "$LAYOUTS"
		        Option "XkbModel" "pc105"
		EndSection
	EOF
	run sudo install -Dm644 "$tmp" /etc/X11/xorg.conf.d/00-keyboard.conf; rm -f "$tmp"
}

# rc_add <service> <runlevel> [now]: OpenRC
rc_add() {
	[ -e "/etc/init.d/$1" ] || { warn "OpenRC service $1 not found (package missing?)"; return; }
	rc-update show "$2" 2>/dev/null | grep -qE "^ *$1 \|" || run sudo rc-update add "$1" "$2"
	[ "${3:-}" = now ] || return 0
	rc-service "$1" status >/dev/null 2>&1 && return 0
	# already running outside OpenRC (e.g. elogind activated by PAM/D-Bus at login): leave it, OpenRC takes over at boot
	if [ "$1" = elogind ] && pgrep -x elogind-daemon >/dev/null 2>&1; then
		info "$1 is already running (started at login); OpenRC manages it from the next boot"
		return 0
	fi
	run sudo rc-service "$1" start || true
	return 0
}

setup_sddm_files() {
	run sudo mkdir -p /usr/share/sddm/themes
	run sudo cp -r "$REPO/sddm/sugar-candy-dwm" /usr/share/sddm/themes/
	run sudo install -Dm644 "$REPO/system/etc/sddm.conf.d/10-dwm-btw.conf" /etc/sddm.conf.d/10-dwm-btw.conf
	local xs; xs=$(mktemp)
	sed "s/^setxkbmap -layout fr,ir$/setxkbmap -layout $LAYOUTS/" "$REPO/system/etc/sddm/Xsetup-dwm-btw" > "$xs"
	run sudo install -Dm755 "$xs" /etc/sddm/Xsetup-dwm-btw
	rm -f "$xs"
	run sudo install -Dm755 "$REPO/system/usr/local/bin/dwm-session" /usr/local/bin/dwm-session
	run sudo install -Dm644 "$REPO/system/usr/local/share/xsessions/dwm.desktop" /usr/local/share/xsessions/dwm.desktop
}

setup_system_gentoo() {
	step "System settings (sudo)"
	run sudo install -Dm644 "$REPO/system/etc/X11/xorg.conf.d/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
	info "touchpad: tap-to-click, natural scrolling"
	run sudo install -Dm755 "$REPO/system/usr/local/bin/dwm-autorandr" /usr/local/bin/dwm-autorandr
	run sudo install -Dm644 "$REPO/system/gentoo/etc/udev/rules.d/90-lunaris-autorandr.rules" \
		/etc/udev/rules.d/90-lunaris-autorandr.rules
	(( DRY )) || sudo udevadm control --reload 2>/dev/null || true
	info "monitors: plug in a screen -> saved layout, or extended side by side (udev -> autorandr)"
	write_xkb_conf
	info "keyboard: $LAYOUTS (Mod+Space switches), dwm keys: $KEYBOARD"

	step "Session (OpenRC)"
	rc_add dbus default now
	rc_add elogind boot now
	info "elogind: login sessions, suspend / reboot / shut down without root"

	if (( SDDM )); then
		step "Login screen (SDDM + Sugar Candy, keyboard $LAYOUTS, dwm session = ~/.xinitrc)"
		setup_sddm_files
		# Gentoo wiki: the greeter needs the video group for GPU access
		id -nG sddm 2>/dev/null | grep -qw video || run sudo usermod -aG video sddm
		if [ -f /etc/conf.d/display-manager ]; then
			grep -q '^DISPLAYMANAGER="sddm"' /etc/conf.d/display-manager ||
				run sudo sed -i 's/^DISPLAYMANAGER=.*/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager
			grep -q '^DISPLAYMANAGER=' /etc/conf.d/display-manager ||
				{ (( DRY )) || echo 'DISPLAYMANAGER="sddm"' | sudo tee -a /etc/conf.d/display-manager >/dev/null; }
		else
			warn "/etc/conf.d/display-manager missing (gui-libs/display-manager-init not installed?)"
		fi
		rc_add display-manager default
		info "SDDM starts at the next boot (pick the dwm session), or now: sudo rc-service display-manager start"
	fi

	step "Services"
	rc_add NetworkManager default now
	rc_add bluetooth default now
	local other
	other=$(rc-update show default 2>/dev/null | awk '$1 ~ /^net\./ {print $1}' | grep -v '^net\.lo$' | tr '\n' ' ')
	[ -n "$other" ] && warn "also in the default runlevel: $other— it fights NetworkManager over the interface;
    remove it if NetworkManager should manage the network:  sudo rc-update del <name> default"
	info "PipeWire (gentoo-pipewire-launcher), picom and clipmenud are started by ~/.xinitrc at login (lunaris-svc)"
	id -nG "$USER" | grep -qw video || warn "you are not in the video group (brightness keys): sudo usermod -aG video $USER"

	step "Theme"
	(( DRY )) || gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
	(( DRY )) || gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null || true
	run fc-cache -f
}

setup_system() {
	[ "$DISTRO" = gentoo ] && { setup_system_gentoo; return; }
	step "System settings (sudo)"
	run sudo install -Dm644 "$REPO/system/etc/X11/xorg.conf.d/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
	info "touchpad: tap-to-click, natural scrolling"
	run sudo install -Dm755 "$REPO/system/usr/local/bin/dwm-autorandr" /usr/local/bin/dwm-autorandr
	run sudo install -Dm644 "$REPO/system/etc/systemd/system/autorandr.service.d/override.conf" \
		/etc/systemd/system/autorandr.service.d/override.conf
	run sudo systemctl daemon-reload
	info "monitors: plug in a screen -> saved layout, or extended side by side (autorandr); screens asleep are left alone"
	# brightness of external monitors (DDC/CI, dwm-bright): i2c-dev at boot, /dev/i2c-* for this user
	echo i2c-dev | run sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
	run sudo modprobe i2c-dev
	getent group i2c >/dev/null || run sudo groupadd --system i2c
	run sudo usermod -aG i2c "$USER"
	run sudo install -Dm644 "$REPO/system/etc/udev/rules.d/60-lunaris-i2c.rules" /etc/udev/rules.d/60-lunaris-i2c.rules
	run sudo udevadm control --reload
	run sudo udevadm trigger --subsystem-match=i2c-dev
	info "monitor brightness: ddcutil + i2c-dev (log in again for the i2c group; check with: dwm-bright doctor)"
	run sudo localectl set-x11-keymap "$LAYOUTS" pc105 "" ""
	info "keyboard: $LAYOUTS (Mod+Space switches), dwm keys: $KEYBOARD"

	if (( SDDM )); then
		step "Login screen (SDDM + Sugar Candy, keyboard $LAYOUTS, dwm session = ~/.xinitrc)"
		setup_sddm_files
		run sudo systemctl enable sddm.service
		info "SDDM starts at the next boot (pick the dwm session)"
	fi

	step "Services"
	run sudo systemctl enable --now NetworkManager.service
	run sudo systemctl enable --now bluetooth.service
	run systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service
	info "picom, clipmenud and xsettingsd are started by ~/.xinitrc at login"

	step "Theme"
	(( DRY )) || gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
	(( DRY )) || gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark 2>/dev/null || true
	run fc-cache -f
}

# ---------------------------------------------------------------- keyboard profile
save_keyboard() {
	step "Keyboard profile: $KEYBOARD  (layouts $LAYOUTS)"
	if [ "$KEYBOARD" = qwerty ]; then info "workspaces: Mod + 1 … 9 0   screens: Mod + . / ,"
	else info "workspaces: Mod + & é \" ' ( - è _ ç à   screens: Mod + ; / ,"; fi
	if (( KBD_GIVEN )) || [ ! -f "$KBD_CONF" ]; then
		if (( DRY )); then info "[dry] write $KBD_CONF"
		else mkdir -p "$(dirname "$KBD_CONF")"
			printf '# Lunaris keyboard profile (dwm-keyboard / install.sh --keyboard)\nKEYBOARD=%s\nLAYOUTS=%s\n' \
				"$KEYBOARD" "$LAYOUTS" > "$KBD_CONF"; fi
	fi
	info "change later: dwm-keyboard set azerty|qwerty [layouts]"
}

# ---------------------------------------------------------------- main
printf '%sLunaris installer%s  (%s, repo: %s)\n' "$c_blue" "$c_off" "$DISTRO" "$REPO"
(( DRY )) && warn "dry run — nothing will be changed"

save_keyboard
if (( ONLY_CONFIGS )); then
	deploy_configs
	deploy_mic_filter
else
	install_packages
	deploy_configs
	build_dwm
	setup_system
	deploy_mic_filter
fi

step "Done"
info "Log in on a TTY and run:  startx"
info "Already in dwm? Restart it in place with Mod+Ctrl+Shift+q (or log out once)."
info "Keys cheat sheet: Mod+Shift+h    Sidebar: Mod+a"
