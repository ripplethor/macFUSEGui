#!/usr/bin/env bash
set -euo pipefail

# scripts/build.sh
# Run from repo root: ./scripts/build.sh
#
# ARCH_OVERRIDE supports arm64|x86_64|both|universal.
# Build both arch apps: ARCH_OVERRIDE=both CONFIGURATION=Release ./scripts/build.sh
# Build x86_64 app only: ARCH_OVERRIDE=x86_64 CONFIGURATION=Debug ./scripts/build.sh
# Dry-run dual-arch release: ARCH_OVERRIDE=both ./scripts/release.sh --dry-run

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/macfuseGui.xcodeproj"
SCHEME="macfuseGui"
CONFIGURATION="${CONFIGURATION:-Debug}"
ARCH_OVERRIDE="${ARCH_OVERRIDE:-arm64}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
STRIP_RELEASE_BINARY="${STRIP_RELEASE_BINARY:-1}"
OUTPUT_DIR="$ROOT_DIR/build"
DEFAULT_OUTPUT_APP="$OUTPUT_DIR/macfuseGui.app"

normalize_arch() {
  case "$1" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64) echo "x86_64" ;;
    all|universal) echo "universal" ;;
    both) echo "both" ;;
    *)
      echo "Unsupported ARCH_OVERRIDE value: $1 (expected arm64, x86_64, both, or universal)" >&2
      exit 1
      ;;
  esac
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

verify_app_executable_arch() {
  local app_bundle="$1"
  local expected_arch="$2"
  local executable_name executable_path lipo_info

  executable_name="$(resolve_bundle_executable_name "$app_bundle")"
  executable_path="$app_bundle/Contents/MacOS/$executable_name"

  [[ -f "$executable_path" ]] || {
    echo "App executable not found for arch verification: $executable_path" >&2
    exit 1
  }

  lipo_info="$(lipo -info "$executable_path" 2>&1 || true)"
  if [[ -z "$lipo_info" ]]; then
    lipo_info="$(file "$executable_path" 2>&1 || true)"
  fi

  case "$expected_arch" in
    arm64)
      if [[ "$lipo_info" != *"arm64"* || "$lipo_info" == *"x86_64"* ]]; then
        echo "Arch verification failed for $app_bundle. Expected arm64-only executable, got: $lipo_info" >&2
        exit 1
      fi
      ;;
    x86_64)
      if [[ "$lipo_info" != *"x86_64"* || "$lipo_info" == *"arm64"* ]]; then
        echo "Arch verification failed for $app_bundle. Expected x86_64-only executable, got: $lipo_info" >&2
        exit 1
      fi
      ;;
    universal)
      if [[ "$lipo_info" != *"arm64"* || "$lipo_info" != *"x86_64"* ]]; then
        echo "Arch verification failed for $app_bundle. Expected universal executable with arm64 and x86_64, got: $lipo_info" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unsupported arch verification target: $expected_arch" >&2
      exit 1
      ;;
  esac
}

strip_app_executable_if_enabled() {
  local app_bundle="$1"
  local executable_name executable_path

  if [[ "$CONFIGURATION" != "Release" || "$STRIP_RELEASE_BINARY" != "1" ]]; then
    return
  fi
  if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    echo "Skipping release strip for signed build: $app_bundle"
    return
  fi

  executable_name="$(resolve_bundle_executable_name "$app_bundle")"
  executable_path="$app_bundle/Contents/MacOS/$executable_name"
  [[ -f "$executable_path" ]] || {
    echo "App executable not found for strip step: $executable_path" >&2
    exit 1
  }

  strip -Sx "$executable_path"
}

ad_hoc_sign_app_if_needed() {
  local app_bundle="$1"

  if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
    return
  fi

  codesign --force --deep --sign - "$app_bundle"
  if ! codesign --verify --deep --strict --verbose=2 "$app_bundle" >/dev/null 2>&1; then
    echo "Ad-hoc signing verification failed: $app_bundle" >&2
    exit 1
  fi
}

run_xcodebuild_for_arch() {
  local arch="$1"
  shift

  if [[ "$arch" == "x86_64" && "$(uname -m)" == "arm64" ]]; then
    arch -x86_64 xcodebuild "$@"
  else
    xcodebuild "$@"
  fi
}

sync_legacy_third_party_paths() {
  local third_party_suffix="$1"
  local openssl_arch_root="$ROOT_DIR/build/third_party/openssl-$third_party_suffix"
  local libssh2_arch_root="$ROOT_DIR/build/third_party/libssh2-$third_party_suffix"
  local openssl_legacy_root="$ROOT_DIR/build/third_party/openssl"
  local libssh2_legacy_root="$ROOT_DIR/build/third_party/libssh2"

  if [[ ! -d "$openssl_arch_root" || ! -d "$libssh2_arch_root" ]]; then
    echo "Expected arch-specific third-party roots were not found: $openssl_arch_root and $libssh2_arch_root" >&2
    exit 1
  fi

  rm -rf "$openssl_legacy_root" "$libssh2_legacy_root"
  ln -s "$openssl_arch_root" "$openssl_legacy_root"
  ln -s "$libssh2_arch_root" "$libssh2_legacy_root"
}

build_single_variant() {
  local build_arch="$1"
  local output_app="$2"
  local derived_data="$3"
  local third_party_suffix="$4"
  local product_app
  local openssl_include openssl_lib libssh2_include libssh2_lib

  openssl_include="$ROOT_DIR/build/third_party/openssl-$third_party_suffix/include"
  openssl_lib="$ROOT_DIR/build/third_party/openssl-$third_party_suffix/lib"
  libssh2_include="$ROOT_DIR/build/third_party/libssh2-$third_party_suffix/include"
  libssh2_lib="$ROOT_DIR/build/third_party/libssh2-$third_party_suffix/lib"

  ARCH_OVERRIDE="$build_arch" "$ROOT_DIR/scripts/build_libssh2.sh"
  sync_legacy_third_party_paths "$third_party_suffix"

  local xcodebuild_args=(
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$derived_data"
    HEADER_SEARCH_PATHS="\$(inherited) $openssl_include $libssh2_include"
    LIBRARY_SEARCH_PATHS="\$(inherited) $openssl_lib $libssh2_lib"
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED"
    build
  )

  case "$build_arch" in
    arm64|x86_64)
      xcodebuild_args+=( ARCHS="$build_arch" ONLY_ACTIVE_ARCH=YES )
      xcodebuild_args+=( -destination "platform=macOS,arch=$build_arch" )
      ;;
    universal)
      xcodebuild_args+=( ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO )
      xcodebuild_args+=( -destination "generic/platform=macOS" )
      ;;
    *)
      echo "Unsupported build arch: $build_arch" >&2
      exit 1
      ;;
  esac

  run_xcodebuild_for_arch "$build_arch" "${xcodebuild_args[@]}"

  product_app="$derived_data/Build/Products/$CONFIGURATION/macfuseGui.app"
  if [[ ! -d "$product_app" ]]; then
    echo "Build succeeded but app bundle not found at: $product_app" >&2
    exit 1
  fi

  rm -rf "$output_app"
  ditto "$product_app" "$output_app"
  strip_app_executable_if_enabled "$output_app"
  ad_hoc_sign_app_if_needed "$output_app"
  verify_app_executable_arch "$output_app" "$build_arch"
  echo "Built: $output_app"
}

ARCH_OVERRIDE="$(normalize_arch "$ARCH_OVERRIDE")"

mkdir -p "$OUTPUT_DIR"

case "$ARCH_OVERRIDE" in
  arm64)
    build_single_variant "arm64" "$DEFAULT_OUTPUT_APP" "$ROOT_DIR/build/DerivedData-arm64" "arm64"
    ;;
  x86_64)
    build_single_variant "x86_64" "$DEFAULT_OUTPUT_APP" "$ROOT_DIR/build/DerivedData-x86_64" "x86_64"
    ;;
  universal)
    build_single_variant "universal" "$DEFAULT_OUTPUT_APP" "$ROOT_DIR/build/DerivedData-universal" "universal"
    ;;
  both)
    build_single_variant "arm64" "$OUTPUT_DIR/macfuseGui-arm64.app" "$ROOT_DIR/build/DerivedData-arm64" "arm64"
    build_single_variant "x86_64" "$OUTPUT_DIR/macfuseGui-x86_64.app" "$ROOT_DIR/build/DerivedData-x86_64" "x86_64"
    ;;
  *)
    echo "Unsupported ARCH_OVERRIDE value: $ARCH_OVERRIDE" >&2
    exit 1
    ;;
esac
