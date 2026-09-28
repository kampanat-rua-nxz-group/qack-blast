#!/usr/bin/env bash
set -euo pipefail

if [[ ! "${QACK_SERVER_HOST:-}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "QACK_SERVER_HOST must be a hostname" >&2
  exit 1
fi

godot_url='https://downloads.godotengine.org/?version=4.7.2&flavor=stable&platform=linux.64&slug=linux.x86_64.zip'
templates_url='https://downloads.godotengine.org/?version=4.7.2&flavor=stable&platform=templates&slug=export_templates.tpz'
build_tools="$(mktemp -d)"
trap 'rm -rf "$build_tools"' EXIT

curl -fL "$godot_url" -o "$build_tools/godot.zip"
unzip -q "$build_tools/godot.zip" -d "$build_tools"
chmod +x "$build_tools/Godot_v4.7.2-stable_linux.x86_64"

curl -fL "$templates_url" -o "$build_tools/templates.tpz"
unzip -q "$build_tools/templates.tpz" 'templates/web_nothreads*' -d "$build_tools"
template_dir="$HOME/.local/share/godot/export_templates/4.7.2.stable"
mkdir -p "$template_dir"
cp "$build_tools"/templates/web_nothreads* "$template_dir/"

sed -i "s|public_server_url=\"\"|public_server_url=\"wss://$QACK_SERVER_HOST\"|" project.godot
"$build_tools/Godot_v4.7.2-stable_linux.x86_64" --headless --path . --export-release Web build/web/index.html
