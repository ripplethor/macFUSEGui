#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/macfuseGui.xcodeproj"
SCHEME="macfuseGui"
CONFIGURATION="${CONFIGURATION:-Debug}"
ARCH_OVERRIDE="${ARCH_OVERRIDE:-arm64}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
OUTPUT_DIR="$ROOT_DIR/build"
OUTPUT_APP="$OUTPUT_DIR/macfuseGui.app"

normalize_arch() {
  case "$1" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64) echo "x86_64" ;;
    all|universal) echo "universal" ;;
    *)
      echo "Unsupported ARCH_OVERRIDE value: $1 (expected arm64, x86_64, or universal)" >&2
      exit 1
      ;;
  esac
}

ARCH_OVERRIDE="$(normalize_arch "$ARCH_OVERRIDE")"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_APP"

# Keep libssh2/OpenSSL build target in lock-step with the Xcode build arch.
ARCH_OVERRIDE="$ARCH_OVERRIDE" "$ROOT_DIR/scripts/build_libssh2.sh"

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED"
  build
)

case "$ARCH_OVERRIDE" in
  arm64|x86_64)
    XCODEBUILD_ARGS+=( ARCHS="$ARCH_OVERRIDE" ONLY_ACTIVE_ARCH=YES )
    XCODEBUILD_ARGS+=( -destination "platform=macOS,arch=$ARCH_OVERRIDE" )
    ;;
  universal)
    XCODEBUILD_ARGS+=( ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO )
    XCODEBUILD_ARGS+=( -destination "generic/platform=macOS" )
    ;;
esac

xcodebuild "${XCODEBUILD_ARGS[@]}"

PRODUCT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/macfuseGui.app"
if [[ ! -d "$PRODUCT_APP" ]]; then
  echo "Build succeeded but app bundle not found at: $PRODUCT_APP" >&2
  exit 1
fi

ditto "$PRODUCT_APP" "$OUTPUT_APP"
echo "Built: $OUTPUT_APP"
