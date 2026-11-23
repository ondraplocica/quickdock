#!/usr/bin/env python3
"""Antigravity quota for the dock widget. Read-only.

The running Antigravity/agy process exposes a local language server (random port, no credentials). Its
RetrieveUserQuotaSummary method returns the 5-hour and weekly buckets. We look for the process's listening
ports, ask each, and cache the last good answer so the widget can still show something when Antigravity is
not running. Prints one JSON object: {"ok", "stale", "ts", "groups": [...]}."""
import json, os, re, ssl, subprocess, sys, time, urllib.request

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "quickdock", "agy-quota.json")
PATH = "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"


def ports():
    try:
        out = subprocess.run(["ss", "-ltnpH"], capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    found = []
    for line in out.splitlines():
        if re.search(r'\("(antigravity|agy)[^"]*"', line):
            m = re.search(r"127\.0\.0\.1:(\d+)", line)
            if m:
                found.append(int(m.group(1)))
    return found


def ask(port):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    for scheme in ("https", "http"):
        try:
            req = urllib.request.Request(f"{scheme}://127.0.0.1:{port}{PATH}", data=b"{}", method="POST",
                                         headers={"Content-Type": "application/json", "Connect-Protocol-Version": "1"})
            with urllib.request.urlopen(req, timeout=5, context=ctx if scheme == "https" else None) as r:
                j = json.loads(r.read().decode())
            groups = (j.get("response") or {}).get("groups")
            if groups:
                return groups
        except Exception:
            continue
    return None


def main():
    groups = None
    for p in ports():
        groups = ask(p)
        if groups:
            break
    if groups:
        res = {"ok": True, "stale": False, "ts": int(time.time()), "groups": groups}
        try:
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w") as f:
                json.dump(res, f)
        except Exception:
            pass
    else:
        try:
            res = json.load(open(CACHE))
            res["stale"] = True
        except Exception:
            res = {"ok": False, "stale": True, "ts": 0, "groups": []}
    print(json.dumps(res))


main()
