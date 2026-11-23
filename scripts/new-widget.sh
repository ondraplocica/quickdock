#!/usr/bin/env bash
# Create a new widget of your own OUTSIDE the repo, from the example template:
#
#   scripts/new-widget.sh <id> ["Display name"]
#
# It lands in ~/.config/quickdock/widgets/<id>/ (honours $XDG_CONFIG_HOME), so it survives `git pull` and never ends up
# in the public repo. Add "<id>" to "widgets" in config/dock.json (or use the bar builder) and restart the dock.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="${1:-}"
NAME="${2:-$ID}"
if ! [[ "$ID" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "usage: $0 <id> [\"Display name\"]   (id: lowercase letters, digits, - and _, starting with a letter)" >&2
  exit 2
fi
if [[ "$NAME" == *'"'* || "$NAME" == *'\'* || "$NAME" == *$'\n'* ]]; then
  echo "the display name may not contain quotes, backslashes or newlines" >&2
  exit 2
fi
if [ -d "$DIR/widgets/$ID" ]; then
  echo "'$ID' is already a built-in widget. A user widget with that id would replace it; pick another id, or create the folder by hand if you really want that." >&2
  exit 1
fi
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/quickdock/widgets/$ID"
if [ -e "$DEST" ]; then
  echo "$DEST already exists" >&2
  exit 1
fi
mkdir -p "$DEST"
# the template imports "../../core" (built-in widgets); outside the repo that is "root:/core"
sed 's|import "../../core"|import "root:/core"|; s|"example"|"'"$ID"'"|g' "$DIR/widgets/example/Widget.qml" > "$DEST/Widget.qml"
printf '{ "id": "%s", "name": "%s", "description": "My widget", "version": "0.1.0" }\n' "$ID" "$NAME" > "$DEST/manifest.json"
echo "Created $DEST"
echo "Next: add \"$ID\" to \"widgets\" in config/dock.json (or use the bar builder), then restart the dock."
