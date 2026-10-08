#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: Godot export template installation failed at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR

workspace=${1:?Usage: install-godot-export-templates.sh <workspace-root>}
versions_file="$workspace/versions.env"
if [[ ! -f "$versions_file" ]]; then
  printf 'ERROR: Version inventory not found: %s\n' "$versions_file" >&2
  exit 1
fi

# versions.env is the repository's trusted, shell-compatible version inventory.
# shellcheck disable=SC1090
source "$versions_file"
if [[ -z "${GODOT_VERSION:-}" ]]; then
  printf 'ERROR: GODOT_VERSION is missing from %s\n' "$versions_file" >&2
  exit 1
fi

version_dir="${GODOT_VERSION}.stable.mono"
templates_root="$HOME/.local/share/godot/export_templates"
destination="$templates_root/$version_dir"
if [[ -d "$destination" ]]; then
  if [[ -n "$(find "$destination" -mindepth 1 -print -quit)" ]]; then
    printf 'Godot export templates already exist for %s; leaving them unchanged.\n' "$GODOT_VERSION"
    exit 0
  fi
  rmdir "$destination"
fi

mkdir -p "$templates_root"
staging_dir=$(mktemp -d "$templates_root/.${version_dir}.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT

archive="$staging_dir/templates.tpz"
url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_mono_export_templates.tpz"
printf 'Downloading Godot %s Mono export templates (this may take a while)...\n' "$GODOT_VERSION"
curl --fail --location --silent --show-error --output "$archive" "$url"
mkdir "$staging_dir/unpacked"
unzip -q "$archive" -d "$staging_dir/unpacked"

if [[ ! -d "$staging_dir/unpacked/templates" ]] || [[ -z "$(find "$staging_dir/unpacked/templates" -mindepth 1 -print -quit)" ]]; then
  printf 'ERROR: The downloaded archive does not contain export templates.\n' >&2
  exit 1
fi

mv -- "$staging_dir/unpacked/templates" "$destination"
printf 'Installed Godot %s Mono export templates at %s.\n' "$GODOT_VERSION" "$destination"
