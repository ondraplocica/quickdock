#!/usr/bin/env python3
"""Google Tasks helper for quickdock. Stdlib only; auth lives in scripts/gauth.py.

Usage: tasks.py auth | list | add <title> | done <id> | undo <id>
"""
import os, sys, urllib.parse
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
from gauth import auth, call, out, fail

API = "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks"
a = sys.argv[1:] or ["list"]
if a[0] == "auth": auth()
elif a[0] == "list":
    r = call("GET", API + "?showCompleted=false&showHidden=false&maxResults=50")
    out({"ok": True, "tasks": [{"id": t["id"], "title": t.get("title", ""), "due": t.get("due", "")[:10]} for t in r.get("items", []) if t.get("title")]})
elif a[0] == "add" and len(a) > 1: call("POST", API, {"title": a[1]}); out({"ok": True})
elif a[0] == "done" and len(a) > 1: call("PATCH", API + "/" + urllib.parse.quote(a[1]), {"status": "completed"}); out({"ok": True})
elif a[0] == "undo" and len(a) > 1: call("PATCH", API + "/" + urllib.parse.quote(a[1]), {"status": "needsAction", "completed": None}); out({"ok": True})
else: fail("usage")
