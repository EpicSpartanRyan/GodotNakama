
#!/usr/bin/env bash
set -Eeuo pipefail

workspace=${1:?Usage: install-godot-export-templates.sh <workspace-root>}
staging_dir=""

cleanup() {
  if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
    rm -rf -- "$staging_dir"
  fi
}
trap cleanup EXIT

on_error() {
  local status=$?
  printf '\n[ERROR] Installation failed at line %s (exit code %s).\n' \
    "$LINENO" "$status" >&2
  exit "$status"
}
trap on_error ERR

step() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$1"
}

success() {
  printf '\033[1;32m[OK]\033[0m %s\n' "$1"
}

step "Checking configuration"

versions_file="$workspace/versions.env"

if [[ ! -f "$versions_file" ]]; then
  printf '[ERROR] Version inventory not found: %s\n' "$versions_file" >&2
  exit 1
fi

# versions.env is the repository's trusted, shell-compatible version inventory.
# shellcheck disable=SC1090
source "$versions_file"

if [[ -z "${GODOT_VERSION:-}" ]]; then
  printf '[ERROR] GODOT_VERSION is not defined in %s\n' "$versions_file" >&2
  exit 1
fi

version_dir="${GODOT_VERSION}.stable.mono"
templates_root="$HOME/.local/share/godot/export_templates"
destination="$templates_root/$version_dir"

printf 'Godot version: %s (Mono/.NET)\n' "$GODOT_VERSION"
printf 'Installation directory: %s\n' "$destination"

step "Checking for existing export templates"

if [[ -d "$destination" ]]; then
  if [[ -n "$(find "$destination" -mindepth 1 -print -quit)" ]]; then
    success "Export templates already exist. The existing installation will be left unchanged."
    exit 0
  fi

  printf 'An empty destination directory was found. Preparing a fresh installation.\n'
  rmdir "$destination"
fi

mkdir -p "$templates_root"
staging_dir=$(mktemp -d "$templates_root/.${version_dir}.XXXXXX")

archive="$staging_dir/templates.tpz"
url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_mono_export_templates.tpz"

step "Downloading export templates from GitHub"

printf 'This download may take several minutes.\n'
printf 'URL: %s\n\n' "$url"

curl \
  --fail \
  --location \
  --show-error \
  --progress-bar \
  --output "$archive" \
  "$url"

success "Download completed."

printf 'Downloaded archive size: '
du -h "$archive" | cut -f1

step "Extracting export templates"

mkdir -p "$staging_dir/unpacked"

printf 'Extracting files (file names will appear below):\n\n'
unzip -o "$archive" -d "$staging_dir/unpacked"

step "Validating extracted templates"

if [[ ! -d "$staging_dir/unpacked/templates" ]] ||
   [[ -z "$(find "$staging_dir/unpacked/templates" -mindepth 1 -print -quit)" ]]; then
  printf '[ERROR] The downloaded archive does not contain valid export templates.\n' >&2
  exit 1
fi

success "The templates directory exists and contains files."

step "Installing export templates"

mv -- "$staging_dir/unpacked/templates" "$destination"

success "Export templates installed successfully."

printf 'Godot version: %s\n' "$GODOT_VERSION"
printf 'Installation directory: %s\n' "$destination"
