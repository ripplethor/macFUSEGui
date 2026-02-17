#!/usr/bin/env bash
set -euo pipefail

# scripts/release.sh
# Run from repo root: ./scripts/release.sh
#
# Flow:
# - require clean git working tree
# - optional dry-run mode (--dry-run / -n): print actions only, no release side effects
# - resolve base version from max(VERSION, latest vX.Y.Z tag)
# - bump patch version
# - build app bundle (Release by default)
# - create DMG from build/macfuseGui.app
# - write VERSION and commit only VERSION
# - create/push git tag and push commit+tag atomically
# - create/update GitHub Release and upload DMG
# - remove local DMG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$REPO_ROOT/VERSION"
APP_BUNDLE_PATH="$REPO_ROOT/build/macfuseGui.app"
VOLNAME="macfuseGui"

CONFIGURATION="${CONFIGURATION:-Release}"
ARCH_OVERRIDE="${ARCH_OVERRIDE:-arm64}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
DRY_RUN=0

DMG_PATH=""
CREATED_DMG=0

RELEASE_NOTES=$'Unsigned macOS build (NOT code signed / NOT notarized)\n\nmacOS will likely block it on first launch.\n\nHow to open:\n1) Download the DMG, drag the app to Applications.\n2) In Finder, right-click the app -> Open -> Open.\nOr: System Settings -> Privacy & Security -> Open Anyway (after the first block).'

die() {
  echo "ERROR: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

cleanup() {
  if [[ "$CREATED_DMG" == "1" && -n "$DMG_PATH" && -f "$DMG_PATH" ]]; then
    rm -f "$DMG_PATH"
  fi
}
trap cleanup EXIT

print_usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [--dry-run|-n]

Options:
  --dry-run, -n   Print release actions without changing git state or publishing to GitHub.
  --help, -h      Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run|-n)
        DRY_RUN=1
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

is_valid_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

bump_patch() {
  local ver="$1"
  local major minor patch
  major="${ver%%.*}"
  minor="${ver#*.}"; minor="${minor%%.*}"
  patch="${ver##*.}"
  patch=$((patch + 1))
  echo "${major}.${minor}.${patch}"
}

latest_tag_version() {
  git tag -l 'v[0-9]*.[0-9]*.[0-9]*' \
    | sed 's/^v//' \
    | awk 'NF' \
    | sort -V \
    | tail -n 1
}

max_version() {
  local a="$1"
  local b="$2"
  if [[ -z "$a" ]]; then
    echo "$b"
    return
  fi
  if [[ -z "$b" ]]; then
    echo "$a"
    return
  fi
  printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1
}

require_clean_tree() {
  local status
  status="$(git status --porcelain --untracked-files=normal)"
  [[ -z "$status" ]] || die "Working tree is not clean. Commit/stash changes before releasing."
}

bundle_newest_mtime() {
  local bundle_path="$1"
  local newest=""

  newest="$(find "$bundle_path" -type f -print0 2>/dev/null \
    | xargs -0 stat -f %m 2>/dev/null \
    | sort -nr \
    | head -n 1 || true)"

  if [[ -n "$newest" ]]; then
    echo "$newest"
    return
  fi

  # Fallback for unexpected empty bundles.
  stat -f %m "$bundle_path"
}

main() {
  require_cmd git
  require_cmd sed
  require_cmd awk
  require_cmd hdiutil
  if [[ "$DRY_RUN" != "1" ]]; then
    require_cmd gh
  fi

  cd "$REPO_ROOT"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git repo"
  git remote get-url origin >/dev/null 2>&1 || die "Missing git remote 'origin'"
  [[ -x "$REPO_ROOT/scripts/build.sh" ]] || die "Build script not found: scripts/build.sh"

  local branch
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "Detached HEAD is not supported for release."

  require_clean_tree
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] Would run: git fetch --tags origin"
    echo "[dry-run] Would run: git merge --ff-only origin/$branch"
  else
    git fetch --tags origin >/dev/null 2>&1 || die "Failed to fetch from origin."
    git merge --ff-only "origin/$branch" >/dev/null 2>&1 || die "Local branch is behind origin. Run: git pull"
  fi

  if [[ "$DRY_RUN" != "1" ]]; then
    if ! gh auth status >/dev/null 2>&1; then
      die "GitHub CLI not authenticated. Run: gh auth login"
    fi
  fi

  local version_from_file=""
  if [[ -f "$VERSION_FILE" ]]; then
    version_from_file="$(tr -d '[:space:]' < "$VERSION_FILE" || true)"
    if [[ -n "$version_from_file" ]] && ! is_valid_version "$version_from_file"; then
      die "Invalid VERSION file value: '$version_from_file' (expected X.Y.Z)"
    fi
  fi

  local version_from_tag
  version_from_tag="$(latest_tag_version)"
  if [[ -n "$version_from_tag" ]] && ! is_valid_version "$version_from_tag"; then
    die "Invalid tag version discovered: '$version_from_tag'"
  fi

  local base_version
  base_version="$(max_version "$version_from_file" "$version_from_tag")"
  if [[ -z "$base_version" ]]; then
    base_version="0.1.0"
  fi

  local new_version
  if [[ -n "$RELEASE_VERSION" ]]; then
    is_valid_version "$RELEASE_VERSION" || die "Invalid RELEASE_VERSION: '$RELEASE_VERSION' (expected X.Y.Z)"
    new_version="$RELEASE_VERSION"
  else
    new_version="$(bump_patch "$base_version")"
  fi
  local tag="v${new_version}"
  DMG_PATH="$REPO_ROOT/macfuseGui-${tag}-macos.dmg"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
    die "Tag already exists locally: $tag"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
    die "Tag already exists on origin: $tag"
  fi

  echo "Repo root:        $REPO_ROOT"
  echo "Git branch:       $branch"
  echo "Base version:     $base_version"
  echo "New version:      $new_version"
  echo "Tag:              $tag"
  echo "Configuration:    $CONFIGURATION"
  echo "Arch override:    $ARCH_OVERRIDE"
  echo "Build skipped:    $SKIP_BUILD"
  echo "DMG path:         $DMG_PATH"
  echo "Dry run:          $DRY_RUN"

  local resolved_app_bundle_path="$APP_BUNDLE_PATH"
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$SKIP_BUILD" != "1" ]]; then
      echo "[dry-run] Would run build: CONFIGURATION=$CONFIGURATION ARCH_OVERRIDE=$ARCH_OVERRIDE CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED $REPO_ROOT/scripts/build.sh"
    else
      echo "[dry-run] Build step skipped (SKIP_BUILD=1)."
    fi
    echo "[dry-run] Would use app bundle path: $resolved_app_bundle_path"
  elif [[ "$SKIP_BUILD" != "1" ]]; then
    local build_log
    build_log="$(mktemp -t macfusegui-release-build.XXXXXX)"

    if ! CONFIGURATION="$CONFIGURATION" \
      ARCH_OVERRIDE="$ARCH_OVERRIDE" \
      CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
      "$REPO_ROOT/scripts/build.sh" 2>&1 | tee "$build_log"; then
      rm -f "$build_log"
      die "Build failed."
    fi

    # Prefer the explicit path reported by build.sh ("Built: <path>") when available.
    local reported_app_path
    reported_app_path="$(awk '
      /^Built: / {
        sub(/^Built: /, "", $0)
        if ($0 ~ /\.app$/) path = $0
      }
      END { if (path != "") print path }
    ' "$build_log")"
    rm -f "$build_log"

    if [[ -n "$reported_app_path" && -d "$reported_app_path" ]]; then
      resolved_app_bundle_path="$reported_app_path"
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] Using app bundle: $resolved_app_bundle_path"
    echo "[dry-run] Would validate app bundle exists: $resolved_app_bundle_path"
    echo "[dry-run] Would create DMG: hdiutil create -volname \"$VOLNAME\" -srcfolder \"$resolved_app_bundle_path\" -ov -format UDZO \"$DMG_PATH\""
    echo "[dry-run] Would write VERSION=$new_version and commit: Release ${tag}"
    echo "[dry-run] Would create tag: $tag"
    echo "[dry-run] Would push atomically: git push --atomic origin \"$branch\" \"$tag\""
    echo "[dry-run] Would create/update GitHub release and upload: $DMG_PATH"
  else
    [[ -d "$resolved_app_bundle_path" ]] || die "App bundle not found at: $resolved_app_bundle_path"
    # Staleness guard is only meaningful when reusing an existing build.
    if [[ "$SKIP_BUILD" == "1" ]]; then
      local app_mtime
      local head_time
      app_mtime="$(bundle_newest_mtime "$resolved_app_bundle_path")"
      head_time="$(git log -1 --format=%ct)"
      if [[ "$app_mtime" -lt "$head_time" ]]; then
        die "App bundle payload looks older than HEAD commit. Rebuild or set SKIP_BUILD=0."
      fi
    fi

    echo "Using app bundle: $resolved_app_bundle_path"
    rm -f "$DMG_PATH"
    hdiutil create -volname "$VOLNAME" -srcfolder "$resolved_app_bundle_path" -ov -format UDZO "$DMG_PATH"
    if ! hdiutil verify "$DMG_PATH" >/dev/null 2>&1; then
      die "DMG verification failed: $DMG_PATH"
    fi
    CREATED_DMG=1

    printf '%s\n' "$new_version" > "$VERSION_FILE"
    git add -- "$VERSION_FILE"
    if git diff --cached --quiet; then
      echo "VERSION unchanged; skipping release commit."
    else
      git commit -m "Release ${tag}"
    fi

    git tag -a "$tag" -m "$tag"
    git push --atomic origin "$branch" "$tag"

    if gh release view "$tag" >/dev/null 2>&1; then
      gh release upload "$tag" "$DMG_PATH" --clobber
      gh release edit "$tag" --title "$tag" --notes "$RELEASE_NOTES"
    else
      gh release create "$tag" "$DMG_PATH" --verify-tag --title "$tag" --notes "$RELEASE_NOTES"
    fi

    rm -f "$DMG_PATH"
    DMG_PATH=""
    CREATED_DMG=0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete. No git push, no tag push, and no GitHub release was created."
  else
    echo "Done. Released ${tag}."
  fi
}

parse_args "$@"
main
