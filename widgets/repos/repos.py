#!/usr/bin/env python3
"""Git repositories overview for the quickdock repos widget.

  repos.py status <config-json>   config: {"roots": ["~"], "repos": [], "exclude": [], "worktrees": false}
  repos.py fetch  <config-json>   `git fetch` in every repo (the only network access; run on request)

Read-only: `git --no-optional-locks status` never writes to a repository. `roots` are searched one level deep for
folders containing .git, `repos` are added as given, `exclude` are folder names (not paths) to skip;
linked worktrees (a .git file) are skipped unless "worktrees" is true.
Prints {"ok": true, "repos": [{"path","name","branch","ahead","behind","changed","untracked","upstream"}]}."""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor


def cfg():
    try:
        c = json.loads(sys.argv[2])
    except Exception:
        c = {}
    c = c if isinstance(c, dict) else {}

    def strs(key, default):
        v = c.get(key)
        v = v if isinstance(v, list) else default
        return [x for x in v if isinstance(x, str) and x]

    return strs("roots", ["~"]), strs("repos", []), set(strs("exclude", [])), c.get("worktrees") is True


def find(roots, extra, exclude, worktrees):
    found = {}
    for r in roots:
        r = os.path.realpath(os.path.expanduser(r))
        try:
            names = sorted(os.listdir(r))
        except OSError:
            continue
        for n in names:
            p = os.path.join(r, n)
            if n in exclude or n.startswith(".") or not os.path.isdir(p):
                continue
            g = os.path.join(p, ".git")
            # a .git FILE is a linked worktree / submodule: skipped unless "worktrees": true (it shares its repository)
            if os.path.isdir(g) or (worktrees and os.path.exists(g)):
                found[os.path.realpath(p)] = n
    for p in extra:
        p = os.path.realpath(os.path.expanduser(p))
        if os.path.isdir(p) and os.path.exists(os.path.join(p, ".git")):
            found.setdefault(p, os.path.basename(p))
    return found


def git(path, *args, timeout=25):
    return subprocess.run(["git", "--no-optional-locks", "-C", path] + list(args), capture_output=True, text=True, timeout=timeout)


def one(item):
    path, name = item
    try:
        r = git(path, "status", "--porcelain=v2", "--branch")
        if r.returncode != 0:
            return {"path": path, "name": name, "error": (r.stderr.strip().splitlines() or ["git failed"])[-1][:120]}
    except Exception as e:
        return {"path": path, "name": name, "error": type(e).__name__}
    d = {"path": path, "name": name, "branch": "", "ahead": 0, "behind": 0, "changed": 0, "untracked": 0, "upstream": False}
    for line in r.stdout.splitlines():
        if line.startswith("# branch.head "):
            d["branch"] = line[14:]
        elif line.startswith("# branch.upstream "):
            d["upstream"] = True
        elif line.startswith("# branch.ab "):
            a, b = line[12:].split()
            d["ahead"], d["behind"] = int(a[1:]), int(b[1:])
        elif line[:2] in ("1 ", "2 ", "u "):
            d["changed"] += 1
        elif line.startswith("? "):
            d["untracked"] += 1
    return d


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("status", "fetch"):
        sys.exit("usage: repos.py status|fetch <config-json>")
    roots, extra, exclude, worktrees = cfg()
    repos = find(roots, extra, exclude, worktrees)
    with ThreadPoolExecutor(6) as pool:
        if sys.argv[1] == "fetch":
            def f(item):
                try:
                    git(item[0], "fetch", "--quiet", timeout=40)
                except Exception:
                    pass
            list(pool.map(f, repos.items()))
        res = list(pool.map(one, repos.items()))
    print(json.dumps({"ok": True, "repos": res}))


main()
