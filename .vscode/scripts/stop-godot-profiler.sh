#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: Stopping the Godot profiler failed at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <game-project-directory> <trace-format>\n' "$0" >&2
  exit 2
fi

project_dir=$1
format=$2
pid_file="$project_dir/.traces/dotnet-trace.pid"

if ! command -v dotnet-trace >/dev/null 2>&1; then
  export PATH="$PATH:$HOME/.dotnet/tools"
fi
if ! command -v dotnet-trace >/dev/null 2>&1; then
  printf 'ERROR: dotnet-trace is not installed or is not on PATH. Run ".NET: Install Profiler" first.\n' >&2
  exit 1
fi

if [[ ! -f "$pid_file" ]]; then
  printf 'ERROR: No profiler task is running for this project (PID file not found).\n' >&2
  exit 1
fi

mapfile -t session < "$pid_file"
if [[ ${#session[@]} -lt 2 || ! "${session[0]}" =~ ^[0-9]+$ ]]; then
  printf 'ERROR: Profiler session file is incomplete: %s\n' "$pid_file" >&2
  exit 1
fi
profiler_pid=${session[0]}
trace_file=${session[1]}
expected_prefix="$project_dir/.traces/"
if [[ "$trace_file" != "$expected_prefix"profile-*.nettrace ]]; then
  printf 'ERROR: Profiler session contains an unexpected trace path: %s\n' "$trace_file" >&2
  exit 1
fi

read_process_args() {
  [[ -r "/proc/$profiler_pid/cmdline" ]] || return 0
  tr '\0' ' ' < "/proc/$profiler_pid/cmdline" 2>/dev/null || true
}

process_args=$(read_process_args)
if [[ -n "$process_args" && "$process_args" != *"dotnet-trace collect --diagnostic-port /tmp/godot-diag"* ]]; then
  printf 'ERROR: PID %s does not match the profiler instance started for this project; refusing to signal it.\n' "$profiler_pid" >&2
  exit 1
fi

if [[ -n "$process_args" ]]; then
  kill -INT "$profiler_pid"
  for _ in {1..600}; do
    process_args=$(read_process_args)
    [[ -z "$process_args" ]] && break
    sleep 0.1
  done
  if [[ -n "$process_args" ]]; then
    printf 'ERROR: Profiler process %s did not stop within 60 seconds.\n' "$profiler_pid" >&2
    exit 1
  fi
fi

current_pid=""
IFS= read -r current_pid < "$pid_file" || true
if [[ "$current_pid" != "$profiler_pid" ]]; then
  printf 'ERROR: Profiler session changed while stopping; refusing to remove %s.\n' "$pid_file" >&2
  exit 1
fi
rm -f -- "$pid_file"
if [[ ! -s "$trace_file" ]]; then
  printf 'ERROR: Profiler did not produce a trace at %s\n' "$trace_file" >&2
  exit 1
fi

case "$format" in
  none)
    printf 'Trace kept in raw format: %s\n' "$trace_file"
    ;;
  Chromium|Speedscope|NetTrace)
    dotnet-trace convert --format "$format" "$trace_file"
    printf 'Trace successfully converted to %s format.\n' "$format"
    ;;
  *)
    printf 'ERROR: Unsupported trace format: %s\n' "$format" >&2
    exit 2
    ;;
esac
