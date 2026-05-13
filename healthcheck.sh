#!/usr/bin/env bash
set -euo pipefail

state_file="${DDNS_STATE_FILE:-/tmp/ddns-yandex-last-success}"
interval="${CHECK_INTERVAL_SECONDS:-900}"

if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -le 0 ]; then
  echo "Invalid CHECK_INTERVAL_SECONDS" >&2
  exit 1
fi

if [ ! -f "$state_file" ]; then
  echo "State file does not exist: $state_file" >&2
  exit 1
fi

now="$(date +%s)"
updated="$(stat -c %Y "$state_file")"
max_age="$((interval * 2 + 60))"
age="$((now - updated))"

if [ "$age" -gt "$max_age" ]; then
  echo "Last successful DDNS check is too old: ${age}s > ${max_age}s" >&2
  exit 1
fi

exit 0
