#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: Godot profiler task failed at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <game-project-directory>\n' "$0" >&2
  exit 2
fi

project_dir=$1
traces_dir="$project_dir/.traces"
pid_file="$traces_dir/dotnet-trace.pid"
diagnostic_port="/tmp/godot-diag"

if ! command -v dotnet-trace >/dev/null 2>&1; then
  export PATH="$PATH:$HOME/.dotnet/tools"
fi
if ! command -v dotnet-trace >/dev/null 2>&1; then
  printf 'ERROR: dotnet-trace is not installed or is not on PATH. Run ".NET: Install Profiler" first.\n' >&2
  exit 1
fi

mkdir -p "$traces_dir"
if [[ -e "$pid_file" ]]; then
  IFS= read -r existing_pid < "$pid_file" || true
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    existing_args=""
    if [[ -r "/proc/$existing_pid/cmdline" ]]; then
      existing_args=$(tr '\0' ' ' < "/proc/$existing_pid/cmdline")
    fi
    if [[ "$existing_args" == *"dotnet-trace collect --diagnostic-port $diagnostic_port"* ]]; then
      printf 'ERROR: A profiler task is already running with PID %s.\n' "$existing_pid" >&2
      exit 1
    fi
  fi
  rm -f -- "$pid_file"
fi

latest=$(find "$traces_dir" -maxdepth 1 -type f -name 'profile-*.nettrace' -printf '%f\n' |
  sed -n 's/^profile-\([0-9][0-9]*\)\.nettrace$/\1/p' | sort -n | tail -n 1)
next=$(printf '%03d' "$((10#${latest:-0} + 1))")
output="$traces_dir/profile-${next}.nettrace"

printf '%s\n%s\n' "$BASHPID" "$output" > "$pid_file"
exec dotnet-trace collect --diagnostic-port "$diagnostic_port" --output "$output"
