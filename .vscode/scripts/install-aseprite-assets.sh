#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; printf "ERROR: Aseprite asset installation failed at line %s (exit %s).\n" "$LINENO" "$status" >&2; exit "$status"' ERR

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <languages|tools> <manifest>\n' "$0" >&2
  exit 2
fi

mode=$1
manifest=$2

if [[ "$mode" != "languages" && "$mode" != "tools" ]]; then
  printf 'ERROR: Unsupported Aseprite asset type: %s\n' "$mode" >&2
  exit 2
fi

if [[ ! -f "$manifest" ]]; then
  printf 'ERROR: Aseprite manifest not found: %s\n' "$manifest" >&2
  exit 1
fi

extensions_dir="$HOME/.config/aseprite/extensions"
scripts_dir="$HOME/.config/aseprite/scripts"
mkdir -p "$extensions_dir" "$scripts_dir"
staging_dir=$(mktemp -d "$extensions_dir/.install.XXXXXX")
trap 'rm -rf -- "$staging_dir"' EXIT

installed=0
skipped=0

while IFS='|' read -r enabled name url type || [[ -n "${enabled}${name}${url}${type}" ]]; do
  enabled=${enabled%$'\r'}
  name=${name%$'\r'}
  url=${url%$'\r'}
  type=${type%$'\r'}

  [[ -z "$enabled" || "$enabled" == \#* ]] && continue
  [[ "$enabled" == "true" ]] || continue
  if [[ -z "$name" || "$url" != https://* ]]; then
    printf 'ERROR: Invalid enabled entry in %s: %s|%s|%s|%s\n' "$manifest" "$enabled" "$name" "$url" "$type" >&2
    exit 1
  fi

  filename=$(basename "${url%%\?*}")
  if [[ "$mode" == "languages" ]]; then
    if [[ "$filename" != *.aseprite-extension ]]; then
      printf 'ERROR: Language package URL must end in .aseprite-extension: %s\n' "$url" >&2
      exit 1
    fi
    target="$extensions_dir/${filename%.aseprite-extension}"
    if [[ -d "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -print -quit)" ]]; then
      printf 'Already installed, skipping %s.\n' "$name"
      ((skipped += 1))
      continue
    elif [[ -e "$target" ]]; then
      printf 'ERROR: Existing language installation is incomplete: %s\n' "$target" >&2
      exit 1
    fi

    download="$staging_dir/$filename"
    curl --fail --location --silent --show-error --output "$download" "$url"
    extracted="$staging_dir/extracted"
    mkdir "$extracted"
    unzip -q "$download" -d "$extracted"
    mv -- "$extracted" "$target"
  else
    case "$type" in
      script)
        target="$scripts_dir/$filename"
        ;;
      extension)
        if [[ "$filename" != *.aseprite-extension ]]; then
          printf 'ERROR: Extension package URL must end in .aseprite-extension: %s\n' "$url" >&2
          exit 1
        fi
        target="$extensions_dir/${filename%.aseprite-extension}"
        ;;
      *)
        printf 'ERROR: Unsupported Aseprite tool type "%s" for %s.\n' "$type" "$name" >&2
        exit 1
        ;;
    esac

    if [[ "$type" == "script" && -s "$target" ]] || { [[ "$type" == "extension" ]] && [[ -d "$target" ]] && [[ -n "$(find "$target" -mindepth 1 -print -quit)" ]]; }; then
      printf 'Already installed, skipping %s.\n' "$name"
      ((skipped += 1))
      continue
    elif [[ -e "$target" ]]; then
      printf 'ERROR: Existing Aseprite tool installation is incomplete: %s\n' "$target" >&2
      exit 1
    fi

    download="$staging_dir/$filename"
    curl --fail --location --silent --show-error --output "$download" "$url"
    if [[ "$type" == "script" ]]; then
      install -m 0644 "$download" "$target"
    else
      extracted="$staging_dir/extracted"
      mkdir "$extracted"
      unzip -q "$download" -d "$extracted"
      mv -- "$extracted" "$target"
    fi
  fi

  printf 'Installed %s.\n' "$name"
  ((installed += 1))
done < "$manifest"

printf 'Aseprite %s installation complete: %s installed, %s already present.\n' "$mode" "$installed" "$skipped"
