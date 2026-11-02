#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_dir="$HOME/.config/omarchy/plugins/io.github.bevebkba.msi-rgb"
shell_config="$HOME/.config/omarchy/shell.json"
command -v omarchy >/dev/null
test -x /usr/bin/msi-rgb
test -x /usr/bin/python3
omarchy plugin validate "$project_dir"
if [[ -f "$shell_config" ]]; then
  backup="${shell_config}.before-ge66-rgb.$(date +%Y%m%d-%H%M%S).$$"
  cp -- "$shell_config" "$backup"
  printf 'Configuration backup: %s\n' "$backup"
fi
mkdir -p "$plugin_dir"
for plugin_file in manifest.json BarWidget.qml RgbPanel.qml CommandRunner.qml controller.py README.md LICENSE; do
  if [[ "$project_dir" != "$plugin_dir" ]]; then
    install -m644 "$project_dir/$plugin_file" "$plugin_dir/$plugin_file"
  fi
done
omarchy plugin validate "$plugin_dir"
omarchy-shell shell rescanPlugins
catalog_ready=0
for attempt in {1..50}; do
  if omarchy-shell shell listPlugins | jq -e 'any(.[]; .id == "io.github.bevebkba.msi-rgb")' >/dev/null; then
    catalog_ready=1
    break
  fi
  sleep 0.1
done
if (( ! catalog_ready )); then
  printf 'Could not refresh the Omarchy plugin catalog. Installed files were preserved.\n' >&2
  exit 1
fi
omarchy plugin enable io.github.bevebkba.msi-rgb right
printf 'MSI RGB added to the bar. Click its keyboard icon.\n'
