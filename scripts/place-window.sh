#!/bin/bash
# Place a floating dropdown window (e.g. Proton Pass, RQuickShare) next to the dock, right-aligned,
# on the dock's monitor, following config/dock.json (position, margin, scale).
# Usage: place-window.sh <window-class-regex> <width> <height>
cls="$1"; w="$2"; h="$3"
cfg="$(dirname "$(readlink -f "$0")")/../config/dock.json"
mon=$(jq -r '.monitor // ""' "$cfg")
pos=$(jq -r '.position // "bottom"' "$cfg")
margin=$(jq -r '(.margin // .marginBottom // 14)' "$cfg")
scale=$(jq -r '.scale // 1' "$cfg")
m=$(hyprctl monitors -j | jq -c --arg m "$mon" '(map(select(.name == $m)) | first) // .[0]')
read -r mx my mw mh ms <<<"$(jq -r '[.x, .y, .width, .height, .scale] | @tsv' <<<"$m")"
# logical size of the monitor and the space the dock takes (68 px tall at 1x) plus an 8 px gap
read -r lw lh dock <<<"$(awk -v w="$mw" -v h="$mh" -v s="$ms" -v sc="$scale" -v mg="$margin" 'BEGIN { printf "%d %d %d", w/s, h/s, 68*sc + mg + 8 }')"
x=$(( mx + lw - w - 8 ))
if [ "$pos" = "top" ]; then y=$(( my + dock )); else y=$(( my + lh - h - dock )); fi
hyprctl dispatch movewindowpixel "exact $x $y,class:^($cls)\$" >/dev/null
