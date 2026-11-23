"""Shared Google OAuth helpers for quickdock (stdlib only). Used by widgets/tasks and widgets/clock.

Files in ~/.config/quickdock/: google-client.json (your OAuth Desktop client), google-token.json (mode 0600).
Every helper prints one JSON object and exits: {"ok": true, ...} or {"ok": false, "error": "..."}.
"""
import json, os, sys, time, secrets, urllib.parse, urllib.request, urllib.error, webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

D = os.path.expanduser("~/.config/quickdock")
CLIENT, TOKEN = os.path.join(D, "google-client.json"), os.path.join(D, "google-token.json")
# Tasks (read/write) + Calendar (read-only). A token created before calendar was added only covers Tasks:
# the calendar widget then reports "scope" and offers a one-click reconnect.
SCOPE = "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/calendar.readonly"

def out(o): print(json.dumps(o)); sys.exit(0)
def fail(e): out({"ok": False, "error": e})

def client():
    try:
        c = json.load(open(CLIENT))
        return c.get("installed") or c.get("web") or c
    except Exception:
        fail("no-client")

def post(url, data):
    req = urllib.request.Request(url, urllib.parse.urlencode(data).encode())
    with urllib.request.urlopen(req, timeout=15) as r: return json.load(r)

def save(t):
    os.makedirs(D, exist_ok=True)
    fd = os.open(TOKEN, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f: json.dump(t, f)

def auth():
    c = client(); state = secrets.token_urlsafe(16); box = {}
    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [""])[0] == state and "code" in q: box["code"] = q["code"][0]
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
            self.wfile.write(b"<h3>quickdock connected. You can close this tab.</h3>")
        def log_message(self, *a): pass
    srv = HTTPServer(("127.0.0.1", 0), H); port = srv.server_address[1]
    redirect = f"http://127.0.0.1:{port}"
    url = c["auth_uri"] + "?" + urllib.parse.urlencode({"client_id": c["client_id"], "redirect_uri": redirect,
        "response_type": "code", "scope": SCOPE, "access_type": "offline", "prompt": "consent", "state": state})
    webbrowser.open(url)
    srv.timeout = 180
    t0 = time.time()
    while "code" not in box and time.time() - t0 < 180: srv.handle_request()
    if "code" not in box: fail("auth-timeout")
    try:
        tok = post(c["token_uri"], {"client_id": c["client_id"], "client_secret": c["client_secret"],
            "code": box["code"], "redirect_uri": redirect, "grant_type": "authorization_code"})
    except urllib.error.HTTPError as e: fail("token-exchange-%d" % e.code)
    save({"refresh_token": tok["refresh_token"], "access_token": tok["access_token"], "exp": time.time() + tok["expires_in"] - 60})
    out({"ok": True})

def access():
    try: t = json.load(open(TOKEN))
    except Exception:
        client()          # reports "no-client" if the OAuth client file is missing
        fail("auth")
    if t.get("exp", 0) > time.time(): return t["access_token"]
    c = client()
    try:
        r = post(c["token_uri"], {"client_id": c["client_id"], "client_secret": c["client_secret"],
            "refresh_token": t["refresh_token"], "grant_type": "refresh_token"})
    except urllib.error.HTTPError: fail("auth")
    t.update(access_token=r["access_token"], exp=time.time() + r["expires_in"] - 60); save(t)
    return t["access_token"]

def call(method, url, body=None):
    req = urllib.request.Request(url, json.dumps(body).encode() if body is not None else None, method=method,
        headers={"Authorization": "Bearer " + access(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try: detail = e.read().decode()
        except Exception: detail = ""
        if e.code == 403 and "accessNotConfigured" in detail: fail("api-disabled")     # API not enabled in the Cloud project
        if e.code == 403 and ("insufficient" in detail.lower() or "ACCESS_TOKEN_SCOPE_INSUFFICIENT" in detail): fail("scope")
        fail("api-%d" % e.code)
    except Exception: fail("network")
