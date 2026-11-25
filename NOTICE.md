# Third-party notes

quickdock is MIT licensed (see LICENSE). One third-party script is bundled: `widgets/claude/get-claude-usage`, from the
claudeCodeUsage plugin by Nicolas Bellamy (MIT, licence text in `widgets/claude/LICENSE.claudeCodeUsage`). No third-party
fonts or images are bundled. quickdock relies on, but does not include:

* **Quickshell** (LGPL-3.0) and **Hyprland** (BSD-3-Clause), the runtime it runs on.
* **Material Symbols Rounded** (Apache-2.0, Google): the icon font, installed from your distro or DankMaterialShell.
* **DankMaterialShell** (optional): its generated colour palette is read from `~/.cache/DankMaterialShell/dms-colors.json`
  if present, and the Focus tile talks to its `dms ipc`.

Online services used by individual widgets, each only when that widget is on the dock:

* `weather`: [Open-Meteo](https://open-meteo.com) (free, no key; see their terms for non-commercial use).
* `quickconvert`: European Central Bank reference rates.
* `tasks` / `clock` calendar: your own Google OAuth client (`widgets/tasks/README.md`) or secret iCal address.
* `github`: the GitHub API through your own `gh` login.
* `claude`: your Claude Code login (`~/.claude/.credentials.json`) is used only to ask `api.anthropic.com` for your usage
  (an unofficial OAuth endpoint that may change); it is passed via stdin, never on a command line. For cost figures the
  script also downloads two public files without credentials: LiteLLM's model price table (raw.githubusercontent.com) and
  a USD to EUR rate (frankfurter.app).
* `codex`: nothing is sent anywhere; it only reads the rate-limit numbers the Codex CLI writes to its own session files under `~/.codex/sessions` (never `auth.json`).
* `antigravity`: the local server of your own running Antigravity / `agy` process (nothing is sent anywhere).
* `home`: your own Home Assistant instance, with a long-lived token you create.

Product names (Hyprland, Tailscale, Syncthing, KDE Connect, Solaar, Logitech, Keychron, GitHub, Google, Claude,
Anthropic, Antigravity, OpenAI, Codex, Home Assistant, Proton Pass) belong to their owners; quickdock is not affiliated with or endorsed by
any of them. The `claude`, `antigravity` and `codex` widget icons are simple original glyphs, not the vendors' logos.
