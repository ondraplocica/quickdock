#!/usr/bin/env python3
"""Syncthing helper for the quickdock `syncthing` widget. Prints one JSON object (read only).

Finds the GUI address + API key in Syncthing's config.xml at runtime. The key is only used for the
loopback request header; it is never printed, logged or passed on a command line.
"""
import json, os, sys, urllib.request, xml.etree.ElementTree as ET

CANDIDATES = ["~/.local/state/syncthing/config.xml", "~/.config/syncthing/config.xml"]

def out(o):
    print(json.dumps(o))

def main():
    cfgp = next((os.path.expanduser(p) for p in CANDIDATES if os.path.exists(os.path.expanduser(p))), None)
    if not cfgp:
        return out({"ok": False, "error": "noconfig"})
    gui = ET.parse(cfgp).getroot().find("gui")
    key = gui.findtext("apikey") if gui is not None else None
    addr = gui.findtext("address") if gui is not None else None
    if not key or not addr:
        return out({"ok": False, "error": "noconfig"})
    base = ("https" if gui.get("tls") == "true" else "http") + "://" + addr
    if base.startswith("https"):
        return out({"ok": False, "error": "tls"})      # self-signed GUI cert: not supported, keep it simple

    def get(path):
        req = urllib.request.Request(base + path, headers={"X-API-Key": key})
        with urllib.request.urlopen(req, timeout=4) as f:
            return json.load(f)

    try:
        cfg = get("/rest/config")
        me = get("/rest/system/status").get("myID", "")
        conns = get("/rest/system/connections").get("connections", {})
        stats = get("/rest/stats/device")
        folders = []
        for f in cfg.get("folders", []):
            try:
                s = get("/rest/db/status?folder=" + f["id"])
            except Exception:
                s = {}
            gb, need = s.get("globalBytes", 0) or 0, s.get("needBytes", 0) or 0
            pct = 100 if gb <= 0 else max(0, min(100, round(100 * (gb - need) / gb)))
            folders.append({
                "id": f["id"], "label": f.get("label") or f["id"], "paused": bool(f.get("paused")),
                "state": s.get("state", "unknown"),            # idle | scanning | syncing | sync-preparing | error ...
                "pct": pct, "needBytes": need,
                "errors": (s.get("errors", 0) or 0) + (s.get("pullErrors", 0) or 0),
            })
        devices = []
        for d in cfg.get("devices", []):
            if d["deviceID"] == me:
                continue
            c = conns.get(d["deviceID"], {})
            devices.append({
                "name": d.get("name") or d["deviceID"][:7], "connected": bool(c.get("connected")),
                "paused": bool(d.get("paused")), "lastSeen": (stats.get(d["deviceID"]) or {}).get("lastSeen", ""),
            })
        devices.sort(key=lambda d: (not d["connected"], d["name"].lower()))
    except Exception as e:
        return out({"ok": False, "error": "down", "detail": type(e).__name__})

    active = [f for f in folders if not f["paused"]]
    if any(f["state"] == "error" or f["errors"] > 0 for f in active):
        overall = "error"
    elif any(f["state"].startswith("sync") for f in active):
        overall = "syncing"
    elif any(f["state"].startswith("scan") for f in active):
        overall = "scanning"
    elif any(f["needBytes"] > 0 for f in active):
        overall = "outofsync"
    else:
        overall = "idle"
    total = sum(f["pct"] for f in active)
    out({
        "ok": True, "overall": overall, "gui": base,
        "pct": round(total / len(active)) if active else 100,
        "folders": folders, "devices": devices,
        "offline": sum(1 for d in devices if not d["connected"] and not d["paused"]),
    })

main()
