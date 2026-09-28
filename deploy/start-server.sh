#!/usr/bin/env bash
set -euo pipefail

port="${PORT:-10000}"
if [[ ! "$port" =~ ^[0-9]+$ ]]; then
  echo "PORT must be numeric" >&2
  exit 1
fi

sed "s/__PORT__/$port/" /etc/nginx/conf.d/qack.conf.template > /etc/nginx/conf.d/qack.conf

godot --headless --path /app --script scripts/server_main.gd -- --bind=127.0.0.1 --port=9080 &
godot_pid=$!
nginx -g 'daemon off;' &
nginx_pid=$!

trap 'kill "$godot_pid" "$nginx_pid" 2>/dev/null || true' EXIT
wait -n "$godot_pid" "$nginx_pid"
