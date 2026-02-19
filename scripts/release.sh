#!/usr/bin/env bash
set -euo pipefail

# scripts/release.sh
# Run from repo root: ./scripts/release.sh
#
# ARCH_OVERRIDE supports arm64|x86_64|both|universal.
# Build both arch apps: ARCH_OVERRIDE=both CONFIGURATION=Release ./scripts/build.sh
# Dry-run dual-arch release: ARCH_OVERRIDE=both ./scripts/release.sh --dry-run
#
# Flow:
# - require clean git working tree
# - optional dry-run mode (--dry-run / -n): print actions only, no release side effects
# - use origin release tags as source of truth and realign local release tags
# - resolve base version from latest origin vX.Y.Z tag (fallback to VERSION when no tags exist)
# - bump patch version
# - build app bundle (Release by default)
# - create DMG(s) from build output app bundle(s)
# - write VERSION and commit only VERSION
# - create/push git tag and push commit+tag atomically
# - create/update GitHub Release and upload DMG asset(s)
# - remove local DMG(s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION_FILE="$REPO_ROOT/VERSION"
APP_BUNDLE_PATH="$REPO_ROOT/build/macfuseGui.app"
APP_BUNDLE_ARM64_PATH="$REPO_ROOT/build/macfuseGui-arm64.app"
APP_BUNDLE_X86_64_PATH="$REPO_ROOT/build/macfuseGui-x86_64.app"
VOLNAME="macfuseGui"
DMG_APP_BUNDLE_NAME="macFUSEGui.app"
DMG_APPLICATIONS_LINK_NAME="Applications"
DMG_INSTALLER_SCRIPT_NAME="Install macFUSEGui.command"
DMG_TERMINAL_HELP_NAME="INSTALL_IN_TERMINAL.txt"
DMG_ZLIB_LEVEL="${DMG_ZLIB_LEVEL:-9}"
STRIP_DMG_PAYLOAD="${STRIP_DMG_PAYLOAD:-1}"

CONFIGURATION="${CONFIGURATION:-Release}"
ARCH_OVERRIDE="${ARCH_OVERRIDE:-both}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
DRY_RUN=0

ARCH_OVERRIDE_NORMALIZED=""
DMG_PATHS=()
CREATED_DMG_PATHS=()
CREATED_STAGE_DIRS=()
CREATED_NOTES_FILE=""

RELEASE_NOTES=$'Unsigned macOS build (NOT code signed / NOT notarized)\n\nmacOS may block first launch.\n\nRecommended install path (Terminal installer):\n/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ripplethor/macfuseGUI/main/scripts/install_release.sh)"\n\nDMG fallback:\n1) Open the DMG.\n2) Open Terminal.\n3) Run: /bin/bash "/Volumes/macfuseGui/Install macFUSEGui.command"\n4) The installer copies the app to /Applications, clears quarantine, and opens it.\n\nIf Finder blocks the app anyway, use the direct command shown in INSTALL_IN_TERMINAL.txt inside the DMG.'

generate_changelog() {
  local previous_tag="$1"
  local range_ref=""

  if [[ -n "$previous_tag" ]]; then
    range_ref="${previous_tag}..HEAD"
  else
    range_ref="HEAD"
  fi

  # Generate deterministic changelog entries from commit subjects.
  # Exclude:
  # - auto release commits
  # - docs:* style commits
  # - any commit that touches docs/, *.html, scripts/*.sh, or test files
  git log --no-merges --pretty=format:'%H%x1f%s' "$range_ref" | while IFS=$'\x1f' read -r commit_hash subject; do
    [[ -n "$commit_hash" ]] || continue

    if printf '%s\n' "$subject" | grep -Eq '^Release[[:space:]]v[0-9]+\.[0-9]+\.[0-9]+$'; then
      continue
    fi

    if printf '%s\n' "$subject" | grep -Eq '^[Dd]ocs(\([^)]*\))?:[[:space:]]'; then
      continue
    fi

    if git diff-tree --no-commit-id --name-only -r "$commit_hash" | grep -Eq '^(docs/|.*\.html$|scripts/.*\.sh$|macfuseGuiTests/|macfuseguitest/)'; then
      continue
    fi

    printf -- '- %s (%s)\n' "$subject" "${commit_hash:0:7}"
  done
}

write_release_notes_file() {
  local output_path="$1"
  local previous_tag="$2"
  local changelog

  changelog="$(generate_changelog "$previous_tag")"

  {
    printf '%s\n\n' "$RELEASE_NOTES"
    printf '## Changes\n\n'
    if [[ -n "$previous_tag" ]]; then
      printf 'Since %s:\n\n' "$previous_tag"
    fi
    if [[ -n "$changelog" ]]; then
      printf '%s\n' "$changelog"
    else
      printf '%s\n' "- No changes listed."
    fi
  } > "$output_path"
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

cleanup() {
  local dmg
  for dmg in "${CREATED_DMG_PATHS[@]}"; do
    if [[ -n "$dmg" && -f "$dmg" ]]; then
      rm -f "$dmg"
    fi
  done
  local stage_dir
  for stage_dir in "${CREATED_STAGE_DIRS[@]}"; do
    if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
      rm -rf "$stage_dir"
    fi
  done
  if [[ -n "$CREATED_NOTES_FILE" && -f "$CREATED_NOTES_FILE" ]]; then
    rm -f "$CREATED_NOTES_FILE"
  fi
}
trap cleanup EXIT

print_usage() {
  cat <<'EOF2'
Usage: ./scripts/release.sh [--dry-run|-n]

Options:
  --dry-run, -n   Print release actions without changing git state or publishing to GitHub.
  --help, -h      Show this help.
EOF2
}

normalize_arch() {
  case "$1" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64) echo "x86_64" ;;
    all|universal) echo "universal" ;;
    both) echo "both" ;;
    *) echo "$1" ;;
  esac
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

list_remote_release_tags() {
  git ls-remote --tags --refs origin 'refs/tags/v[0-9]*.[0-9]*.[0-9]*' \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | awk 'NF'
}

latest_remote_tag_version() {
  local remote_tags="$1"
  printf '%s\n' "$remote_tags" \
    | sed 's/^v//' \
    | awk 'NF' \
    | sort -V \
    | tail -n 1
}

sync_local_release_tags_with_origin() {
  local remote_tags="$1"
  local local_tag

  while IFS= read -r local_tag; do
    [[ -n "$local_tag" ]] || continue
    if ! printf '%s\n' "$remote_tags" | grep -Fxq "$local_tag"; then
      git tag -d "$local_tag" >/dev/null
      echo "Pruned local tag not on origin: $local_tag"
    fi
  done < <(git tag -l 'v[0-9]*.[0-9]*.[0-9]*')
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

resolve_bundle_executable_name() {
  local app_bundle="$1"
  local info_plist="$app_bundle/Contents/Info.plist"
  local executable_name=""

  if [[ -f "$info_plist" ]]; then
    executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist" 2>/dev/null || true)"
  fi
  if [[ -z "$executable_name" ]]; then
    executable_name="$(basename "$app_bundle" .app)"
  fi
  echo "$executable_name"
}

strip_staged_app_if_enabled() {
  local staged_app_path="$1"
  local executable_name executable_path

  if [[ "$STRIP_DMG_PAYLOAD" != "1" || "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    return
  fi

  executable_name="$(resolve_bundle_executable_name "$staged_app_path")"
  executable_path="$staged_app_path/Contents/MacOS/$executable_name"
  [[ -f "$executable_path" ]] || die "App executable not found in staged payload: $executable_path"
  strip -Sx "$executable_path"
}

write_dmg_installer_script() {
  local stage_dir="$1"
  local script_path="$stage_dir/$DMG_INSTALLER_SCRIPT_NAME"

  cat > "$script_path" <<'EOF_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="macFUSEGui.app"
SRC_APP="$SCRIPT_DIR/$APP_NAME"
DST_APP="/Applications/$APP_NAME"

if [[ ! -d "$SRC_APP" ]]; then
  echo "App bundle not found next to installer script: $SRC_APP" >&2
  exit 1
fi

echo "Installing $APP_NAME to /Applications..."
if [[ -w "/Applications" ]]; then
  rm -rf "$DST_APP"
  ditto "$SRC_APP" "$DST_APP"
else
  sudo rm -rf "$DST_APP"
  sudo ditto "$SRC_APP" "$DST_APP"
fi

echo "Clearing quarantine attribute..."
if [[ -w "$DST_APP" ]]; then
  xattr -dr com.apple.quarantine "$DST_APP" || true
else
  sudo xattr -dr com.apple.quarantine "$DST_APP" || true
fi

echo "Opening app..."
open "$DST_APP"
echo "Done."
EOF_INSTALLER

  chmod +x "$script_path"
}

write_dmg_terminal_install_help() {
  local stage_dir="$1"
  local help_path="$stage_dir/$DMG_TERMINAL_HELP_NAME"
  local direct_install_cmd
  direct_install_cmd="sudo rm -rf \"/Applications/$DMG_APP_BUNDLE_NAME\" && sudo ditto \"/Volumes/$VOLNAME/$DMG_APP_BUNDLE_NAME\" \"/Applications/$DMG_APP_BUNDLE_NAME\" && sudo xattr -dr com.apple.quarantine \"/Applications/$DMG_APP_BUNDLE_NAME\" && open \"/Applications/$DMG_APP_BUNDLE_NAME\""

  cat > "$help_path" <<EOF_HELP
If Finder blocks double-click launch, install from Terminal:

1) Open Terminal
2) Run:
/bin/bash "/Volumes/$VOLNAME/$DMG_INSTALLER_SCRIPT_NAME"

If that is also blocked, run this direct fallback command:
$direct_install_cmd
EOF_HELP
}

ad_hoc_sign_staged_app_if_needed() {
  local staged_app_path="$1"

  if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    return
  fi

  codesign --force --deep --sign - "$staged_app_path"
  if ! codesign --verify --deep --strict --verbose=2 "$staged_app_path" >/dev/null 2>&1; then
    die "Ad-hoc signing verification failed for staged payload: $staged_app_path"
  fi
}

main() {
  require_cmd git
  require_cmd sed
  require_cmd awk
  require_cmd ditto
  require_cmd hdiutil
  require_cmd codesign
  if [[ "$DRY_RUN" != "1" ]]; then
    require_cmd gh
  fi

  ARCH_OVERRIDE_NORMALIZED="$(normalize_arch "$ARCH_OVERRIDE")"
  case "$ARCH_OVERRIDE_NORMALIZED" in
    arm64|x86_64|both|universal)
      ;;
    *)
      die "Unsupported ARCH_OVERRIDE value: $ARCH_OVERRIDE (expected arm64, x86_64, both, or universal)"
      ;;
  esac

  cd "$REPO_ROOT"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not in a git repo"
  git remote get-url origin >/dev/null 2>&1 || die "Missing git remote 'origin'"
  [[ -x "$REPO_ROOT/scripts/build.sh" ]] || die "Build script not found: scripts/build.sh"

  local branch
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "Detached HEAD is not supported for release."

  require_clean_tree
  local remote_release_tags=""
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] Would run: git fetch --tags origin"
    echo "[dry-run] Would run: git merge --ff-only origin/$branch"
    remote_release_tags="$(list_remote_release_tags)" || die "Failed to list origin tags."
    local local_tag
    while IFS= read -r local_tag; do
      [[ -n "$local_tag" ]] || continue
      if ! printf '%s\n' "$remote_release_tags" | grep -Fxq "$local_tag"; then
        echo "[dry-run] Would delete local tag not on origin: $local_tag"
      fi
    done < <(git tag -l 'v[0-9]*.[0-9]*.[0-9]*')
  else
    git fetch --tags origin >/dev/null 2>&1 || die "Failed to fetch from origin."
    git merge --ff-only "origin/$branch" >/dev/null 2>&1 || die "Local branch is behind origin. Run: git pull"
    remote_release_tags="$(list_remote_release_tags)" || die "Failed to list origin tags."
    sync_local_release_tags_with_origin "$remote_release_tags"
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
  version_from_tag="$(latest_remote_tag_version "$remote_release_tags")"
  if [[ -n "$version_from_tag" ]] && ! is_valid_version "$version_from_tag"; then
    die "Invalid tag version discovered: '$version_from_tag'"
  fi
  local previous_tag=""
  if [[ -n "$version_from_tag" ]]; then
    previous_tag="v${version_from_tag}"
  fi

  local base_version
  if [[ -n "$version_from_tag" ]]; then
    base_version="$version_from_tag"
  elif [[ -n "$version_from_file" ]]; then
    base_version="$version_from_file"
  else
    base_version="0.1.0"
  fi
  if [[ -n "$version_from_tag" && -n "$version_from_file" && "$version_from_file" != "$version_from_tag" ]]; then
    echo "Using origin tag version as baseline: $version_from_tag (local VERSION is $version_from_file)"
  fi

  local new_version
  if [[ -n "$RELEASE_VERSION" ]]; then
    is_valid_version "$RELEASE_VERSION" || die "Invalid RELEASE_VERSION: '$RELEASE_VERSION' (expected X.Y.Z)"
    new_version="$RELEASE_VERSION"
  else
    new_version="$(bump_patch "$base_version")"
  fi
  local tag="v${new_version}"
  CREATED_NOTES_FILE="$(mktemp -t macfusegui-release-notes.XXXXXX)"
  write_release_notes_file "$CREATED_NOTES_FILE" "$previous_tag"

  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null 2>&1; then
    die "Tag already exists locally: $tag"
  fi
  if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
    die "Tag already exists on origin: $tag"
  fi

  local app_bundle_paths=()
  local resolved_app_bundle_paths=()

  if [[ "$ARCH_OVERRIDE_NORMALIZED" == "both" ]]; then
    app_bundle_paths=(
      "$APP_BUNDLE_ARM64_PATH"
      "$APP_BUNDLE_X86_64_PATH"
    )
    DMG_PATHS=(
      "$REPO_ROOT/macfuseGui-${tag}-macos-arm64.dmg"
      "$REPO_ROOT/macfuseGui-${tag}-macos-x86_64.dmg"
    )
  else
    app_bundle_paths=("$APP_BUNDLE_PATH")
    DMG_PATHS=("$REPO_ROOT/macfuseGui-${tag}-macos.dmg")
  fi

  resolved_app_bundle_paths=("${app_bundle_paths[@]}")

  echo "Repo root:        $REPO_ROOT"
  echo "Git branch:       $branch"
  echo "Base version:     $base_version"
  echo "New version:      $new_version"
  echo "Tag:              $tag"
  echo "Configuration:    $CONFIGURATION"
  echo "Arch override:    $ARCH_OVERRIDE_NORMALIZED"
  echo "Build skipped:    $SKIP_BUILD"
  echo "DMG zlib level:   $DMG_ZLIB_LEVEL"
  echo "Strip DMG app:    $STRIP_DMG_PAYLOAD"
  local dmg_path
  for dmg_path in "${DMG_PATHS[@]}"; do
    echo "DMG path:         $dmg_path"
  done
  echo "Dry run:          $DRY_RUN"

  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "$SKIP_BUILD" != "1" ]]; then
      echo "[dry-run] Would run build: CONFIGURATION=$CONFIGURATION ARCH_OVERRIDE=$ARCH_OVERRIDE_NORMALIZED CODE_SIGNING_ALLOWED=$CODE_SIGNING_ALLOWED $REPO_ROOT/scripts/build.sh"
    else
      echo "[dry-run] Build step skipped (SKIP_BUILD=1)."
    fi
    local app_path
    for app_path in "${resolved_app_bundle_paths[@]}"; do
      echo "[dry-run] Would use app bundle path: $app_path"
      echo "[dry-run] Would validate app bundle exists: $app_path"
    done
  elif [[ "$SKIP_BUILD" != "1" ]]; then
    local build_log
    build_log="$(mktemp -t macfusegui-release-build.XXXXXX)"

    if ! CONFIGURATION="$CONFIGURATION" \
      ARCH_OVERRIDE="$ARCH_OVERRIDE_NORMALIZED" \
      CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
      "$REPO_ROOT/scripts/build.sh" 2>&1 | tee "$build_log"; then
      rm -f "$build_log"
      die "Build failed."
    fi

    local reported_app_path
    reported_app_path="$(awk '
      /^Built: / {
        sub(/^Built: /, "", $0)
        if ($0 ~ /\.app$/) path = $0
      }
      END { if (path != "") print path }
    ' "$build_log")"
    rm -f "$build_log"

    if [[ "$ARCH_OVERRIDE_NORMALIZED" == "both" ]]; then
      local required_path
      for required_path in "${app_bundle_paths[@]}"; do
        if [[ ! -d "$required_path" ]]; then
          die "Expected app bundle not found after dual-arch build: $required_path"
        fi
      done
      resolved_app_bundle_paths=("${app_bundle_paths[@]}")
    elif [[ -n "$reported_app_path" && -d "$reported_app_path" ]]; then
      resolved_app_bundle_paths=("$reported_app_path")
    fi
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    local i
    for i in "${!resolved_app_bundle_paths[@]}"; do
      echo "[dry-run] Would stage app bundle as \"$DMG_APP_BUNDLE_NAME\" for DMG payload."
      echo "[dry-run] Would create /Applications symlink in DMG payload."
      echo "[dry-run] Would add installer helper script: $DMG_INSTALLER_SCRIPT_NAME"
      echo "[dry-run] Would add Terminal install help file: $DMG_TERMINAL_HELP_NAME"
      if [[ "$STRIP_DMG_PAYLOAD" == "1" && "$CODE_SIGNING_ALLOWED" != "YES" ]]; then
        echo "[dry-run] Would strip staged app executable symbols before DMG create."
      fi
      if [[ "$CODE_SIGNING_ALLOWED" != "YES" ]]; then
        echo "[dry-run] Would ad-hoc sign staged app bundle before DMG create."
      fi
      echo "[dry-run] Would create DMG: hdiutil create -volname \"$VOLNAME\" -srcfolder \"<staging>\" -ov -format UDZO -imagekey zlib-level=$DMG_ZLIB_LEVEL \"${DMG_PATHS[$i]}\""
    done
    echo "[dry-run] Would write VERSION=$new_version and commit: Release ${tag}"
    echo "[dry-run] Would create tag: $tag"
    echo "[dry-run] Would push atomically: git push --atomic origin \"$branch\" \"$tag\""
    echo "[dry-run] Would create/update GitHub release and upload: ${DMG_PATHS[*]}"
    echo "[dry-run] Would set GitHub release notes from commits since: ${previous_tag:-<no previous tag>}"
  else
    local app_path
    for app_path in "${resolved_app_bundle_paths[@]}"; do
      [[ -d "$app_path" ]] || die "App bundle not found at: $app_path"
    done

    # Staleness guard is only meaningful when reusing an existing build.
    if [[ "$SKIP_BUILD" == "1" ]]; then
      local head_time
      head_time="$(git log -1 --format=%ct)"
      for app_path in "${resolved_app_bundle_paths[@]}"; do
        local app_mtime
        app_mtime="$(bundle_newest_mtime "$app_path")"
        if [[ "$app_mtime" -lt "$head_time" ]]; then
          die "App bundle payload looks older than HEAD commit. Rebuild or set SKIP_BUILD=0."
        fi
      done
    fi

    local i
    for i in "${!resolved_app_bundle_paths[@]}"; do
      local current_app_path current_dmg_path stage_dir staged_app_path
      current_app_path="${resolved_app_bundle_paths[$i]}"
      current_dmg_path="${DMG_PATHS[$i]}"
      stage_dir="$(mktemp -d -t macfusegui-release-stage.XXXXXX)"
      staged_app_path="$stage_dir/$DMG_APP_BUNDLE_NAME"

      echo "Using app bundle: $current_app_path"
      echo "Staging app bundle for DMG payload: $staged_app_path"
      ditto "$current_app_path" "$staged_app_path"
      ln -s /Applications "$stage_dir/$DMG_APPLICATIONS_LINK_NAME"
      write_dmg_installer_script "$stage_dir"
      write_dmg_terminal_install_help "$stage_dir"
      strip_staged_app_if_enabled "$staged_app_path"
      ad_hoc_sign_staged_app_if_needed "$staged_app_path"
      CREATED_STAGE_DIRS+=("$stage_dir")
      rm -f "$current_dmg_path"
      hdiutil create -volname "$VOLNAME" -srcfolder "$stage_dir" -ov -format UDZO -imagekey "zlib-level=$DMG_ZLIB_LEVEL" "$current_dmg_path"
      if ! hdiutil verify "$current_dmg_path" >/dev/null 2>&1; then
        die "DMG verification failed: $current_dmg_path"
      fi
      CREATED_DMG_PATHS+=("$current_dmg_path")
    done

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
      gh release upload "$tag" "${DMG_PATHS[@]}" --clobber
      gh release edit "$tag" --title "$tag" --notes-file "$CREATED_NOTES_FILE"
    else
      gh release create "$tag" "${DMG_PATHS[@]}" --verify-tag --title "$tag" --notes-file "$CREATED_NOTES_FILE"
    fi
    rm -f "$CREATED_NOTES_FILE"
    CREATED_NOTES_FILE=""

    for dmg_path in "${DMG_PATHS[@]}"; do
      rm -f "$dmg_path"
    done
    CREATED_DMG_PATHS=()
    for stage_dir in "${CREATED_STAGE_DIRS[@]}"; do
      rm -rf "$stage_dir"
    done
    CREATED_STAGE_DIRS=()
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete. No git push, no tag push, and no GitHub release was created."
  else
    echo "Done. Released ${tag}."
  fi
}

parse_args "$@"
main
