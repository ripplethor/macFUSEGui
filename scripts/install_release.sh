#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-ripplethor/macFUSEGui}"
APP_NAME="macFUSEGui.app"
TARGET_APP="/Applications/$APP_NAME"

usage() {
  cat <<'EOF'
Usage: scripts/install_release.sh [--tag vX.Y.Z]

Options:
  --tag vX.Y.Z   Install a specific release tag. Defaults to latest release.
  --help, -h     Show this help.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

detect_arch() {
  case "$(uname -m)" in
    arm64) echo "arm64" ;;
    x86_64) echo "x86_64" ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      shift
      [[ $# -gt 0 ]] || { echo "--tag requires a value" >&2; exit 1; }
      TAG="$1"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

require_cmd curl
require_cmd python3
require_cmd hdiutil
require_cmd ditto
require_cmd xattr
require_cmd open

ARCH="$(detect_arch)"
if [[ -n "$TAG" ]]; then
  RELEASE_API_URL="https://api.github.com/repos/$REPO_SLUG/releases/tags/$TAG"
else
  RELEASE_API_URL="https://api.github.com/repos/$REPO_SLUG/releases/latest"
fi

echo "Resolving release asset for $ARCH from $REPO_SLUG..."
release_json="$(curl -fsSL "$RELEASE_API_URL")"

asset_url="$(
  printf '%s' "$release_json" | python3 - "$ARCH" <<'PY'
import json
import sys

arch = sys.argv[1]
data = json.load(sys.stdin)
suffix = f"-macos-{arch}.dmg"
for asset in data.get("assets", []):
    name = asset.get("name", "")
    if name.endswith(suffix):
        print(asset.get("browser_download_url", ""))
        sys.exit(0)
sys.exit(1)
PY
)" || {
  echo "Could not find a DMG asset matching arch '$ARCH' in the selected release." >&2
  exit 1
}

tmp_dir="$(mktemp -d -t macfusegui-install.XXXXXX)"
mount_point=""
cleanup() {
  if [[ -n "$mount_point" ]]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

dmg_path="$tmp_dir/macfuseGui-$ARCH.dmg"
echo "Downloading: $asset_url"
curl -fL --retry 3 --retry-delay 1 "$asset_url" -o "$dmg_path"

attach_output="$(hdiutil attach -nobrowse -readonly "$dmg_path")"
mount_point="$(printf '%s\n' "$attach_output" | awk '/\/Volumes\// {for (i=1; i<=NF; i++) if ($i ~ /^\/Volumes\//) {print $i; exit}}')"
[[ -n "$mount_point" ]] || {
  echo "Failed to detect mounted DMG volume." >&2
  exit 1
}

source_app="$mount_point/$APP_NAME"
[[ -d "$source_app" ]] || {
  echo "App not found in mounted DMG: $source_app" >&2
  exit 1
}

echo "Installing $APP_NAME to /Applications..."
if [[ -w "/Applications" ]]; then
  rm -rf "$TARGET_APP"
  ditto "$source_app" "$TARGET_APP"
  xattr -dr com.apple.quarantine "$TARGET_APP" || true
else
  sudo rm -rf "$TARGET_APP"
  sudo ditto "$source_app" "$TARGET_APP"
  sudo xattr -dr com.apple.quarantine "$TARGET_APP" || true
fi

echo "Opening app..."
open "$TARGET_APP"
echo "Installed: $TARGET_APP"
