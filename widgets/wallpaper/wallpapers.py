#!/usr/bin/env python3
"""Wallpaper helper for the quickdock wallpaper widget. Read-only.

  wallpapers.py <dirs-json>    e.g. '["~/Pictures/Wallpapers", "~/Pictures"]'

Prints {"ok": true, "files": [{"path", "name"}...], "backend": "dms|awww|swww|hyprpaper|none", "current": "<path or empty>"}.
Images are searched in each folder and one level of sub-folders; at most 500 are returned (sorted by name)."""
import json, os, shutil, subprocess, sys

EXT = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
LIMIT = 500


def listing(dirs):
    seen, out = set(), []
    for d in dirs:
        if not isinstance(d, str) or not d:
            continue
        d = os.path.realpath(os.path.expanduser(d))
        if not os.path.isdir(d):
            continue
        for root, subdirs, files in os.walk(d):
            if root[len(d):].count(os.sep) >= 1:      # one level of sub-folders
                subdirs[:] = []
            subdirs[:] = [s for s in subdirs if not s.startswith(".")]
            for f in files:
                p = os.path.join(root, f)
                if os.path.splitext(f)[1].lower() in EXT and p not in seen and os.path.isfile(p):
                    seen.add(p)
                    out.append({"path": p, "name": os.path.splitext(f)[0]})
    out.sort(key=lambda x: x["name"].lower())
    return out[:LIMIT]


def backend():
    if shutil.which("dms"):
        return "dms"
    for b in ("awww", "swww"):
        if shutil.which(b):
            return b
    if shutil.which("hyprctl") and subprocess.run(["pgrep", "-x", "hyprpaper"], capture_output=True).returncode == 0:
        return "hyprpaper"
    return "none"


def current(b):
    if b == "dms":
        try:
            r = subprocess.run(["dms", "ipc", "call", "wallpaper", "get"], capture_output=True, text=True, timeout=5)
            t = r.stdout.strip()
            return os.path.realpath(t) if t.startswith("/") and os.path.exists(t) else ""
        except Exception:
            return ""
    return ""


def main():
    try:
        dirs = json.loads(sys.argv[1]) if len(sys.argv) > 1 else []
    except Exception:
        dirs = []
    if not isinstance(dirs, list):
        dirs = []
    b = backend()
    print(json.dumps({"ok": True, "files": listing(dirs), "backend": b, "current": current(b)}))


main()
