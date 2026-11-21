# Qt theme: qt5ct where it is installed (Arch); Gentoo only packages qt6ct
if command -v qt5ct >/dev/null 2>&1; then export QT_QPA_PLATFORMTHEME=qt5ct; else export QT_QPA_PLATFORMTHEME=qt6ct; fi
# default terminal for apps that honour $TERMINAL: dwm-term opens the one chosen in Settings → Terminal
export TERMINAL=dwm-term

# no systemd (Gentoo + OpenRC): there is no user session bus yet — start one for this X session
# (notifications, the sidebar, PipeWire, Bluetooth and NetworkManager applets all need it)
if [ ! -d /run/systemd/system ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-launch >/dev/null 2>&1; then
	eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi

xrdb -merge "$HOME/.Xresources"
xsettingsd &   # live GTK settings (theme, font size)
xsetroot -cursor_name left_ptr

# keyboard: the system-wide layout lives in /etc/X11/xorg.conf.d/00-keyboard.conf
# (written by install.sh) so hot-plugged / reconnected keyboards get it too.
# This line is only a fallback: layouts from ~/.config/dwm-btw.conf (dwm-keyboard), default fr,ir.
"$HOME/.local/bin/dwm-keyboard" apply 2>/dev/null || setxkbmap -layout fr,ir
xset r rate 250 40

# session services: compositor (picom, vsync), clipboard history (Mod+v), audio (PipeWire)
#   systemd: user units (logs: journalctl --user -u picom)
#   OpenRC:  supervised by lunaris-svc (logs: $XDG_RUNTIME_DIR/lunaris/*.log)
if [ -d /run/systemd/system ]; then
	# let user services (pipewire, etc.) see the X display
	systemctl --user import-environment DISPLAY XAUTHORITY TERMINAL
fi
if command -v lunaris-svc >/dev/null 2>&1; then
	lunaris-svc start-all
else   # older lunaris-dwm without lunaris-svc
	systemctl --user restart clipmenud
	systemctl --user reset-failed picom 2>/dev/null; systemctl --user restart picom
fi
# weekly update check (Tuesday): a systemd timer on Arch, this loop elsewhere
[ -d /run/systemd/system ] || lunaris-update autocheck --loop >/dev/null 2>&1 &

dwm-display apply   # saved resolution (Mod+Shift+d)
dwm-wall restore   # wallpaper + slideshow (Mod+w)
dunst &
dwm-status &
qs -c arch-sidebar &   # quickshell sidebar (Mod+a)

exec dwm
