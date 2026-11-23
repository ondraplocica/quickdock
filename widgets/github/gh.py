#!/usr/bin/env python3
"""GitHub summary for quickdock via the `gh` CLI (your existing login; no token is read or passed in argv).
Prints {"ok":true,"login","total","days":[{"date","count"}],"today","streak","best","prs":[...],"prTotal","reviewRequested"}.
"""
import json, subprocess, sys
from datetime import date

Q = """query {
  viewer { login
    contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { date contributionCount } } } }
    pullRequests(states: OPEN, first: 6, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount nodes { title url isDraft updatedAt repository { nameWithOwner } } } }
  rr: search(query: "is:pr is:open review-requested:@me", type: ISSUE, first: 1) { issueCount }
}"""

def out(o): print(json.dumps(o)); sys.exit(0)
try:
    r = subprocess.run(["gh", "api", "graphql", "-f", "query=" + Q], capture_output=True, text=True, timeout=25)
except Exception: out({"ok": False, "error": "gh-missing"})
if r.returncode != 0: out({"ok": False, "error": "auth" if "auth" in r.stderr.lower() else "gh-failed"})
try: d = json.loads(r.stdout)["data"]
except Exception: out({"ok": False, "error": "parse"})
v = d["viewer"]; cal = v["contributionsCollection"]["contributionCalendar"]
days = [{"date": x["date"], "count": x["contributionCount"]} for w in cal["weeks"] for x in w["contributionDays"]]
today = date.today().isoformat()
days = [x for x in days if x["date"] <= today]
# streaks: current (allow today to be empty so far) and best
streak, i = 0, len(days) - 1
if i >= 0 and days[i]["count"] == 0: i -= 1
while i >= 0 and days[i]["count"] > 0: streak += 1; i -= 1
best = cur = 0
for x in days:
    cur = cur + 1 if x["count"] > 0 else 0
    best = max(best, cur)
out({"ok": True, "login": v["login"], "total": cal["totalContributions"], "days": days[-182:],
     "today": days[-1]["count"] if days else 0, "streak": streak, "best": best,
     "prs": [{"title": p["title"], "url": p["url"], "draft": p["isDraft"], "repo": p["repository"]["nameWithOwner"], "updated": p["updatedAt"]} for p in v["pullRequests"]["nodes"]],
     "prTotal": v["pullRequests"]["totalCount"], "reviewRequested": d["rr"]["issueCount"]})
