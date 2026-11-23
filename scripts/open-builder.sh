#!/bin/sh
# Open a quickdock builder window as its own process: open-builder.sh [bar|qs]   (default: bar)
# Works even if the running dock's own `ipc call dock builder` does not.
which="${1:-bar}"
case "$which" in bar|qs) ;; *) echo "usage: $0 [bar|qs]" >&2; exit 2;; esac
dir="$(cd "$(dirname "$0")/.." && pwd)"
BUILDER="$which" setsid -f quickshell -p "$dir/builders.qml" >/dev/null 2>&1
