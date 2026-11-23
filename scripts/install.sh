#!/usr/bin/env bash
# quickdock installer. Safe by default: it checks dependencies, writes a systemd *user* unit and prints the Hyprland
# rules to add. It never edits your Hyprland config and never touches anything outside ~/.config/systemd/user.
#
#   scripts/install.sh              check + install the user service (not started)
#   scripts/install.sh --start      ... and start it now
#   scripts/install.sh --enable     ... and start it at every graphical login
#   scripts/install.sh --uninstall  remove the service (your config/dock.json is kept)
#   scripts/install.sh --dry-run    only print what would happen
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT="$UNIT_DIR/quickdock.service"
START=0; ENABLE=0; UNINSTALL=0; DRY=0
for a in "$@"; do
  case "$a" in
    --start) START=1;;
    --enable) ENABLE=1; START=1;;
    --uninstall) UNINSTALL=1;;
    --dry-run) DRY=1;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown option: $a (try --help)" >&2; exit 2;;
  esac
done
run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

if [ "$UNINSTALL" = 1 ]; then
  run systemctl --user disable --now quickdock.service 2>/dev/null || true
  run rm -f "$UNIT"
  run systemctl --user daemon-reload
  echo "Removed the quickdock service. $DIR and your config/dock.json were left alone."
  exit 0
fi

MISSING=0
ok()  { printf '  ok      %s\n' "$1"; }
bad() { printf '  MISSING %s - %s\n' "$1" "$2"; MISSING=1; }
opt() { if command -v "$1" >/dev/null 2>&1; then ok "$1"; else printf '  skip    %s - %s\n' "$1" "$2"; fi; }

echo "Required:"
if command -v quickshell >/dev/null 2>&1; then ok "quickshell ($(quickshell --version 2>/dev/null | head -1))"; else bad quickshell "https://quickshell.org (0.3 or newer)"; fi
if command -v hyprctl >/dev/null 2>&1; then ok "hyprctl (Hyprland)"; else bad hyprctl "quickdock currently targets Hyprland"; fi
if command -v python3 >/dev/null 2>&1; then ok python3; else bad python3 "used by several widgets"; fi
if [ -e /usr/share/quickshell/dms/assets/fonts/material-design-icons ] || fc-list 2>/dev/null | grep -qi "Material Symbols"; then
  ok "Material Symbols font (icons)"
else
  printf '  WARNING Material Symbols Rounded font not found - icons will be blank. Install your distro'"'"'s "material-symbols" font package.\n'
fi
echo "Optional (each one enables a widget or feature):"
opt cliphist "clipboard history"
opt wl-copy "clipboard (wl-clipboard)"
opt playerctl "now playing"
opt upower "peripheral batteries"
opt tailscale "tailscale widget / VPN tile"
opt kdeconnect-cli "kdeconnect widget"
opt solaar "Logitech batteries"
opt nvidia-smi "gpu widget (NVIDIA)"
opt gh "github widget"
opt grim "screenshot widget"
opt slurp "screenshot widget"
opt hyprsunset "Night tile"
opt dms "Focus / notification tiles (DankMaterialShell)"
opt jq "VPN tile"
if [ "$MISSING" != 0 ]; then
  echo
  echo "Install the missing required tools and run this again."
  exit 1
fi

echo
echo "Installing the user service -> $UNIT"
run mkdir -p "$UNIT_DIR"
if [ "$DRY" = 1 ]; then
  echo "[dry-run] write $UNIT (ExecStart=$(command -v quickshell) -p $DIR)"
else
  {
    echo "[Unit]"
    echo "Description=quickdock (Quickshell dock)"
    echo "PartOf=graphical-session.target"
    echo "After=graphical-session.target"
    echo "Requisite=graphical-session.target"
    echo
    echo "[Service]"
    echo "ExecStart=$(command -v quickshell) -p $DIR"
    echo "Restart=on-failure"
    echo "RestartSec=2"
    echo
    echo "[Install]"
    echo "WantedBy=graphical-session.target"
  } > "$UNIT"
fi
run systemctl --user daemon-reload
if [ "$ENABLE" = 1 ]; then run systemctl --user enable quickdock.service; fi
if [ "$START" = 1 ]; then run systemctl --user restart quickdock.service; fi

echo
echo "Next, add these to your Hyprland config so the dock and its dropdowns get the blur-behind look,"
echo "then reload Hyprland (this is the Hyprland 0.55 layerrule syntax; see README.md for other versions):"
echo
echo '  layerrule = blur on, match:namespace ^quickdock$'
echo '  layerrule = ignore_alpha 0.1, match:namespace ^quickdock$'
echo '  layerrule = blur_popups on, match:namespace ^quickdock$'
echo
echo "Your settings live in config/dock.json (created the first time you change something in the dock)."
echo "Start it any time with:  systemctl --user start quickdock    (or: quickshell -p $DIR)"
