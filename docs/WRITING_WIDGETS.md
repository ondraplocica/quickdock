# Writing your own widget

A widget is a folder with two files. The dock finds it by its folder name, so there is no registry to edit.

```
widgets/mywidget/
  manifest.json     # name + description, shown in the bar builder
  Widget.qml        # the tile (root type: Tile)
```

The fastest start is to copy the working template and change it (to keep it out of the repo, see the section below):

```bash
cp -r widgets/example widgets/mywidget
# edit widgets/mywidget/manifest.json  -> set "id": "mywidget"
```

Then add `"mywidget"` to `"widgets"` in `config/dock.json`, or open the bar builder and drag it onto the bar:

```bash
quickshell ipc -p . call dock builder      # while the dock runs
scripts/open-builder.sh                    # standalone window, works even if the line above does not
```

Hot reload is **off** on purpose (a reload while a dropdown is open can crash Hyprland), so restart the dock to see
changes: `systemctl --user restart quickdock`, or stop it and run `quickshell -p .` in a terminal, which also prints
errors and `console.log` output. Close open dropdowns first.

## Keep your own widgets outside the repo

Widgets for your own setup (a work VPN, a smart-home panel, anything private) do not belong in a clone of this repo.
quickdock also loads widgets from your config folder:

```bash
scripts/new-widget.sh mywidget "My Widget"      # creates ~/.config/quickdock/widgets/mywidget/ from the template
```

```
~/.config/quickdock/widgets/mywidget/
  manifest.json
  Widget.qml
  Settings.qml        # optional
```

Add `"mywidget"` to `"widgets"` in `config/dock.json` (or drag it in the bar builder) and restart the dock. They show up
in the builder next to the built-in ones, and `git pull` never touches them. Two differences from a built-in widget:

* import the shared types with **`import "root:/core"`** instead of `import "../../core"` (`root:/` is the dock's own folder;
  the scaffolder already does this for you);
* a user widget with the same id as a built-in one **replaces** it, which is handy for patching one locally.

`$XDG_CONFIG_HOME` is honoured. Helper files next to your `Widget.qml` work as usual
(`Qt.resolvedUrl("helper.py")`), and a `qmldir` there lets you split a widget into several QML files.

## manifest.json

```json
{ "id": "mywidget", "name": "My Widget", "description": "One line", "version": "0.1.0" }
```

| field | meaning |
|---|---|
| `id` | must equal the folder name |
| `name`, `description` | shown in the builder |
| `settings` | optional `true`: the builder then shows `widgets/mywidget/Settings.qml` when the widget is selected |

## Widget.qml

The root element is a `Tile`: a rounded card with hover lift and a `clicked()` signal. You decide its `implicitWidth`;
the dock fixes the height.

```qml
import QtQuick
import Quickshell.Io
import "../../core"

Tile {
    id: w
    implicitWidth: 120
    onClicked: pop.open = !pop.open

    Text { anchors.centerIn: parent; text: "hello"; color: Theme.text; font.family: Theme.font }

    Popover {                       // the dropdown that opens next to the tile
        id: pop
        target: w
        panelWidth: 260; panelHeight: 120
        // ...content, laid out at 1x...
    }
}
```

### What you get for free

| | |
|---|---|
| `Theme.*` | colours (`text`, `textDim`, `accent`, `good`, `warn`, `bad`, `tileFill`, `hairline`), sizes, the font. Never hard-code them: the dock re-themes from these. |
| `Tile` | `config` (your widget's block), `instanceId`, `active` (accent tint), `interactive`, `clicked()`. |
| `Popover` | dropdown with the shared Material surface. It follows the user's *Dropdown opacity*, *Dropdown scale* and the blur-behind rule automatically. |
| `Icon` | Material Symbols by name: `Icon { name: "schedule"; size: 20 }`. Add `filled: true` for the solid glyph. |
| `Ring` | circular progress: `Ring { size: 28; value: 0.4 }`. |
| `Stepper`, `Segmented`, `Slider`, `MacSlider`, `IconButton` | the controls the settings page uses. |
| `QsStyle.*` | the quick-settings palette (`panel`, `card`, `accent`, `text`) if you draw your own panel-like surface. |

### Running commands and reading data

Use Quickshell's `Process`; the output is data, never build a command from text you did not write.

```qml
Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: proc.running = true }
Process {
    id: proc
    command: ["sh", "-c", "uptime -p"]
    stdout: StdioCollector { onStreamFinished: w.text = text.trim() }
}
```

For anything longer than a one-liner, put a script next to the widget (`widgets/mywidget/helper.py`) and call it with
`String(Qt.resolvedUrl("helper.py")).replace("file://", "")`. Keep helpers read-only and have them print JSON.
Several bundled widgets (`clock`, `syncthing`, `tasks`) do exactly this and are good references.

## Settings

Each widget owns one block in `config/dock.json`:

```json
{ "widgetConfig": { "mywidget": { "label": "Hello", "count": 3 } } }
```

* `config` on the Tile is that block, handed over **once when the widget loads**.
* For values the user changes while the dock runs, read live: `(Dock.cfg.widgetConfig || {})[w.instanceId]`.
* Save with `Dock.saveWidget(w.instanceId, { count: 4 })`; it merges into your block and writes the file.

### Several copies of one widget

An id with a suffix (`"mywidget:work"`) loads the same `Widget.qml` again with `instanceId = "mywidget:work"` and its
own `widgetConfig` block. Always use `instanceId`, never a hard-coded id, when you read or save settings.

## Multiple QML files in one widget

Add a `qmldir` next to `Widget.qml` so the other files can be used as types:

```
# widgets/mywidget/qmldir
MyList 1.0 MyList.qml
```

Without it, helper components in the widget folder are not found when the widget is loaded.

## Quick tiles

The toggles in the quick-settings panel (Night, Dark, VPN...) are defined in `core/Quick.qml`. Tiles for *your* setup do
not need a code change: list them in `~/.config/quickdock/quick-tiles.json` (`$XDG_CONFIG_HOME` honoured). Commands are
argv arrays (never run through a shell) and a leading `~/` is your home folder.

```json
[
  { "id": "vpn2", "label": "Work VPN", "icon": "vpn_lock",
    "widget": "myvpn",                                    // optional: the dock widget that represents this tile
    "toggle": ["~/bin/vpn", "work", "toggle"],            // run on click (shown as "Working..." while it runs)
    "state":  ["~/bin/vpn", "work", "status"],            // optional, polled every 8 s
    "on": "connected",                                    // the tile is lit while `state` prints this (default "true")
    "place": { "class": "SomeApp", "w": 640, "h": 480 },  // optional: put that window next to the dock afterwards
    "hook": ["~/bin/app", "--focus-changed"] }            // optional: run on every focus change, new window address appended
]
```

`id` is lowercase letters, digits and `_`, and cannot reuse a built-in id. Entries that do not validate are ignored.
You can also add plain *custom shortcut tiles* (a label, an icon and a shell command) from the quick-settings builder.

## Etiquette

* Do not poll faster than you need to; timers keep running while the dock is hidden.
* Treat everything from the network, a clipboard or another program as untrusted text: show it as `Text.PlainText`
  and never run it.
* Do not store secrets in `dock.json`; use `~/.config/quickdock/` with mode `0600` like the `tasks` widget does.
* Keep it small. A widget that needs ten files probably wants to be its own project.

If you made something other people might use, open a pull request.
