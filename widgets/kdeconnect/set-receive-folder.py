#!/usr/bin/env python3
"""Point KDE Connect's "receive files" folder for one device at a folder, and make the daemon re-read it.

  set-receive-folder.py <device id (32 hex)> <absolute folder>

Writes incoming_path into ~/.config/kdeconnect/<id>/kdeconnect_share/config (keeping a one-time .bak-quickdock copy and
every other key) and calls the device's reloadPlugins over D-Bus. Prints "ok" on success."""
import os, re, subprocess, sys

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: set-receive-folder.py <device id> <absolute folder>")
    dev, folder = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"[0-9a-f]{32}", dev):
        sys.exit("bad device id")
    if not os.path.isabs(folder) or "\n" in folder or "\r" in folder:
        sys.exit("folder must be an absolute path")
    os.makedirs(folder, exist_ok=True)
    cfgdir = os.path.expanduser("~/.config/kdeconnect/%s/kdeconnect_share" % dev)
    os.makedirs(cfgdir, exist_ok=True)
    path = os.path.join(cfgdir, "config")
    lines = []
    if os.path.exists(path):
        with open(path) as f:
            lines = f.read().splitlines()
        bak = path + ".bak-quickdock"
        if not os.path.exists(bak):
            with open(bak, "w") as f:
                f.write("\n".join(lines) + "\n")
    kv = "incoming_path=" + folder
    out, in_general, set_ = [], False, False
    for ln in lines:
        s = ln.strip()
        if s.startswith("[") and s.endswith("]"):
            if in_general and not set_:
                out.append(kv); set_ = True
            in_general = (s == "[General]")
        elif in_general and re.match(r"incoming_path\s*=", s):
            ln = kv; set_ = True
        out.append(ln)
    if not set_:
        if not any(l.strip() == "[General]" for l in lines):
            out.append("[General]")
            out.append(kv)
        elif in_general:
            out.append(kv)
        else:   # [General] exists but is not the last section: insert right after its header
            i = next(k for k, l in enumerate(out) if l.strip() == "[General]")
            out.insert(i + 1, kv)
    with open(path, "w") as f:
        f.write("\n".join(out) + "\n")
    subprocess.run(["busctl", "--user", "call", "org.kde.kdeconnect", "/modules/kdeconnect/devices/" + dev,
                    "org.kde.kdeconnect.device", "reloadPlugins"], capture_output=True, timeout=10)
    print("ok")

main()
