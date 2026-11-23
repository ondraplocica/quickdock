#!/usr/bin/env python3
"""Tailscale helper for the quickdock `tailscale` widget. Prints one JSON object.

  ts.py status             -> summary of `tailscale status --json` (read only)
  ts.py exit <ip|none>     -> `tailscale set --exit-node=...`
  ts.py up | down          -> `tailscale up` / `tailscale down`
The mutating commands need operator rights (`sudo tailscale set --operator=$USER`, once); without them
the error comes back as {"ok": false, "error": "operator"} so the widget can show the fix.
"""
import getpass, ipaddress, json, subprocess, sys

def run(args, timeout=8):
    try:
        p = subprocess.run(["tailscale"] + args, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", "tailscale not installed"
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"

def out(o):
    print(json.dumps(o))

def operator_ok():
    rc, so, _ = run(["debug", "prefs"], 5)
    if rc != 0:
        return False
    try:
        return json.loads(so).get("OperatorUser") == getpass.getuser()
    except Exception:
        return False

def ip4(ips):
    for i in ips or []:
        if "." in i:
            return i
    return (ips or [""])[0]

def status():
    rc, so, se = run(["status", "--json"])
    if rc == 127:
        return out({"ok": False, "error": "missing"})
    try:
        d = json.loads(so)
    except Exception:
        return out({"ok": False, "error": "down", "detail": (se or "")[:120]})
    state = d.get("BackendState", "")
    me = d.get("Self") or {}
    peers = []
    for p in (d.get("Peer") or {}).values():
        peers.append({
            "name": p.get("HostName") or p.get("DNSName", "").split(".")[0],
            "ip": ip4(p.get("TailscaleIPs")),
            "online": bool(p.get("Online")),
            "os": p.get("OS", ""),
            "exitOption": bool(p.get("ExitNodeOption")),
            "isExit": bool(p.get("ExitNode")),
            "lastSeen": p.get("LastSeen", ""),
        })
    peers.sort(key=lambda p: (not p["online"], p["name"].lower()))
    cur = ""
    for p in peers:
        if p["isExit"]:
            cur = p["name"]
    out({
        "ok": True,
        "state": state,                                  # Running | Stopped | NeedsLogin | Starting ...
        "tailnet": (d.get("CurrentTailnet") or {}).get("Name", ""),
        "self": {"name": me.get("HostName", ""), "ip": ip4(me.get("TailscaleIPs")), "online": bool(me.get("Online"))},
        "peers": peers,
        "online": sum(1 for p in peers if p["online"]),
        "total": len(peers),
        "exitNode": cur,
        "operator": operator_ok(),
        "user": getpass.getuser(),
    })

def mutate(args):
    rc, so, se = run(args, 20)
    if rc == 0:
        return out({"ok": True})
    msg = (se or so or "").strip()
    low = msg.lower()
    if "access denied" in low or "operator" in low or "permission" in low or "sudo" in low:
        return out({"ok": False, "error": "operator", "detail": msg[:200]})
    out({"ok": False, "error": "failed", "detail": msg[:200]})

def main():
    a = sys.argv[1:] or ["status"]
    if a[0] == "status":
        return status()
    if a[0] == "exit" and len(a) == 2:
        if a[1] != "none":
            try:
                ipaddress.ip_address(a[1])
            except ValueError:
                return out({"ok": False, "error": "failed", "detail": "bad ip"})
        return mutate(["set", "--exit-node=" + ("" if a[1] == "none" else a[1])])
    if a[0] == "up":
        return mutate(["up"])
    if a[0] == "down":
        return mutate(["down"])
    out({"ok": False, "error": "failed", "detail": "bad command"})

main()
