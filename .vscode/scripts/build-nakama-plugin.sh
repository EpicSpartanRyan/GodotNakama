#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: Nakama plugin build failed at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <plugin-name> <workspace-root>\n' "$0" >&2
  exit 2
fi

plugin_name=$1
workspace=$2
if [[ ! "$plugin_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
  printf 'ERROR: Plugin name may contain only letters, digits, underscores, and hyphens.\n' >&2
  exit 2
fi

backend="$workspace/backend"
output_dir="$workspace/nakama/modules"
if [[ ! -f "$backend/go.mod" ]]; then
  printf 'ERROR: Go backend module not found: %s\n' "$backend/go.mod" >&2
  exit 1
fi

mkdir -p "$output_dir"
temporary_output="$output_dir/.${plugin_name}.$$.so"
trap 'rm -f -- "$temporary_output"' EXIT
go -C "$backend" build --trimpath --mod=vendor -buildvcs=false --buildmode=plugin -o "$temporary_output"
mv -- "$temporary_output" "$output_dir/${plugin_name}.so"
trap - EXIT
printf 'Built Nakama plugin: %s/%s.so\n' "$output_dir" "$plugin_name"
