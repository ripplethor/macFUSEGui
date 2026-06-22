#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBSSH2_VERSION="${LIBSSH2_VERSION:-1.11.1}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.0.17}"
MACOS_MIN_VERSION="${MACOS_MIN_VERSION:-13.0}"
ARCH_OVERRIDE_VALUE="${ARCH_OVERRIDE:-arm64}"

# Keep SSH compatibility ciphers/hashes intact, but strip TLS-only and
# dynamic engine features that libssh2 does not use.
OPENSSL_SAFE_MINIMIZE_FLAGS=(
  no-ssl3
  no-tls1
  no-tls1_1
  no-comp
  no-engine
  no-dso
  no-psk
  no-srp
)

LIBSSH2_URL="https://www.libssh2.org/download/libssh2-${LIBSSH2_VERSION}.tar.gz"
OPENSSL_URL="https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"

# Pinned SHA-256 checksums for the source tarballs (supply-chain integrity).
# These are the upstream-published hashes for the default versions above and MUST
# be updated whenever LIBSSH2_VERSION / OPENSSL_VERSION change. They can be
# overridden via the environment when intentionally building a different version.
LIBSSH2_SHA256="${LIBSSH2_SHA256:-d9ec76cbe34db98eec3539fe2c899d26b0c837cb3eb466a56b0f109cabf658f7}"
OPENSSL_SHA256="${OPENSSL_SHA256:-dfdd77e4ea1b57ff3a6dbde6b0bdc3f31db5ac99e7fdd4eaf9e1fbb6ec2db8ce}"

SOURCE_ROOT="$ROOT_DIR/third_party/src"
LIBSSH2_TARBALL="$SOURCE_ROOT/libssh2-${LIBSSH2_VERSION}.tar.gz"
OPENSSL_TARBALL="$SOURCE_ROOT/openssl-${OPENSSL_VERSION}.tar.gz"

normalize_arch() {
  case "$1" in
    arm64|aarch64) echo "arm64" ;;
    x86_64|amd64) echo "x86_64" ;;
    all|universal) echo "universal" ;;
    *) echo "$1" ;;
  esac
}

ARCH_OVERRIDE_VALUE="$(normalize_arch "$ARCH_OVERRIDE_VALUE")"
case "$ARCH_OVERRIDE_VALUE" in
  universal)
    ARCHES=(arm64 x86_64)
    ;;
  arm64|x86_64)
    ARCHES=("$ARCH_OVERRIDE_VALUE")
    ;;
  *)
    echo "Unsupported ARCH_OVERRIDE value: $ARCH_OVERRIDE_VALUE (expected arm64, x86_64, or universal)" >&2
    exit 1
    ;;
esac

OUTPUT_SUFFIX="$ARCH_OVERRIDE_VALUE"
LIBSSH2_OUTPUT_ROOT="$ROOT_DIR/build/third_party/libssh2-$OUTPUT_SUFFIX"
LIBSSH2_OUTPUT_INCLUDE="$LIBSSH2_OUTPUT_ROOT/include"
LIBSSH2_OUTPUT_LIB="$LIBSSH2_OUTPUT_ROOT/lib"

OPENSSL_OUTPUT_ROOT="$ROOT_DIR/build/third_party/openssl-$OUTPUT_SUFFIX"
OPENSSL_OUTPUT_INCLUDE="$OPENSSL_OUTPUT_ROOT/include"
OPENSSL_OUTPUT_LIB="$OPENSSL_OUTPUT_ROOT/lib"

BUILD_ROOT="$ROOT_DIR/build/third_party/source-build-$OUTPUT_SUFFIX"
BUILD_INFO_FILE="$LIBSSH2_OUTPUT_ROOT/BUILD-INFO.txt"

USE_ROSETTA_FOR_X86=0
if [[ "$ARCH_OVERRIDE_VALUE" == "x86_64" && "$(uname -m)" == "arm64" ]]; then
  USE_ROSETTA_FOR_X86=1
fi

mkdir -p "$SOURCE_ROOT" "$LIBSSH2_OUTPUT_INCLUDE" "$LIBSSH2_OUTPUT_LIB" "$OPENSSL_OUTPUT_INCLUDE" "$OPENSSL_OUTPUT_LIB"

ARCH_FINGERPRINT="$(IFS=,; echo "${ARCHES[*]}")"
OPENSSL_FLAGS_FINGERPRINT="$(IFS=,; echo "${OPENSSL_SAFE_MINIMIZE_FLAGS[*]}")"
EXPECTED_FINGERPRINT="libssh2=${LIBSSH2_VERSION};openssl=${OPENSSL_VERSION};min=${MACOS_MIN_VERSION};archs=${ARCH_FINGERPRINT};openssl_flags=${OPENSSL_FLAGS_FINGERPRINT}"

have_cached_outputs() {
  [[ -f "$BUILD_INFO_FILE" ]] &&
    grep -Fq "fingerprint=$EXPECTED_FINGERPRINT" "$BUILD_INFO_FILE" &&
    [[ -f "$LIBSSH2_OUTPUT_LIB/libssh2.a" ]] &&
    [[ -f "$OPENSSL_OUTPUT_LIB/libcrypto.a" ]] &&
    [[ -f "$OPENSSL_OUTPUT_LIB/libssl.a" ]] &&
    [[ -d "$LIBSSH2_OUTPUT_INCLUDE" ]] &&
    [[ -d "$OPENSSL_OUTPUT_INCLUDE" ]]
}

verify_checksum() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "Checksum verification FAILED for $(basename "$file")." >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    echo "Refusing to build with an unverified source tarball." >&2
    # Drop the bad file so a later run can re-fetch a clean copy.
    rm -f "$file"
    exit 1
  fi
}

download_if_missing() {
  local tarball="$1"
  local url="$2"
  local expected_sha="$3"
  if [[ -f "$tarball" ]]; then
    # Verify the cached tarball too: it may have been truncated or tampered with
    # since a previous run.
    verify_checksum "$tarball" "$expected_sha"
    return
  fi
  echo "Downloading $(basename "$tarball")..."
  curl -fsSL "$url" -o "$tarball"
  verify_checksum "$tarball" "$expected_sha"
}

openssl_target_for_arch() {
  case "$1" in
    arm64) echo "darwin64-arm64-cc" ;;
    x86_64) echo "darwin64-x86_64-cc" ;;
    *)
      echo "Unsupported OpenSSL arch: $1" >&2
      exit 1
      ;;
  esac
}

libssh2_host_for_arch() {
  case "$1" in
    arm64) echo "aarch64-apple-darwin" ;;
    x86_64) echo "x86_64-apple-darwin" ;;
    *)
      echo "Unsupported libssh2 arch: $1" >&2
      exit 1
      ;;
  esac
}

run_for_arch() {
  local arch="$1"
  shift

  if [[ "$arch" == "x86_64" && "$USE_ROSETTA_FOR_X86" == "1" ]]; then
    arch -x86_64 "$@"
  else
    "$@"
  fi
}

run_logged() {
  local log_file="$1"
  shift
  if ! "$@" >"$log_file" 2>&1; then
    echo "Command failed. Full log: $log_file" >&2
    cat "$log_file" >&2
    exit 1
  fi
}

build_openssl_arch() {
  local arch="$1"
  local arch_build_root="$BUILD_ROOT/openssl-$arch"
  rm -rf "$arch_build_root"
  mkdir -p "$arch_build_root"

  tar -xzf "$OPENSSL_TARBALL" -C "$arch_build_root"
  local src_dir
  src_dir="$(find "$arch_build_root" -mindepth 1 -maxdepth 1 -type d -name "openssl-*" | head -n 1)"
  if [[ -z "$src_dir" ]]; then
    echo "Unable to find extracted OpenSSL source directory in $arch_build_root" >&2
    exit 1
  fi

  local openssl_target
  openssl_target="$(openssl_target_for_arch "$arch")"
  local configure_log="$arch_build_root/openssl-configure.log"
  local make_log="$arch_build_root/openssl-make.log"
  local install_log="$arch_build_root/openssl-install.log"

  pushd "$src_dir" >/dev/null
  run_logged "$configure_log" \
    run_for_arch "$arch" env \
    CC="cc -arch $arch" \
    CFLAGS="-mmacosx-version-min=${MACOS_MIN_VERSION}" \
    LDFLAGS="-mmacosx-version-min=${MACOS_MIN_VERSION}" \
    ./Configure "$openssl_target" no-shared no-tests "${OPENSSL_SAFE_MINIMIZE_FLAGS[@]}" "--prefix=$arch_build_root/install"
  run_logged "$make_log" run_for_arch "$arch" make -j"$(sysctl -n hw.ncpu)"
  run_logged "$install_log" run_for_arch "$arch" make install_sw
  popd >/dev/null
}

build_libssh2_arch() {
  local arch="$1"
  local arch_build_root="$BUILD_ROOT/libssh2-$arch"
  rm -rf "$arch_build_root"
  mkdir -p "$arch_build_root"

  tar -xzf "$LIBSSH2_TARBALL" -C "$arch_build_root"
  local src_dir
  src_dir="$(find "$arch_build_root" -mindepth 1 -maxdepth 1 -type d -name "libssh2-*" | head -n 1)"
  if [[ -z "$src_dir" ]]; then
    echo "Unable to find extracted libssh2 source directory in $arch_build_root" >&2
    exit 1
  fi

  local host
  host="$(libssh2_host_for_arch "$arch")"
  local configure_log="$arch_build_root/libssh2-configure.log"
  local make_log="$arch_build_root/libssh2-make.log"

  pushd "$src_dir" >/dev/null
  run_logged "$configure_log" \
    run_for_arch "$arch" env \
    CC="cc -arch $arch" \
    ./configure \
      --host="$host" \
      --disable-shared \
      --enable-static \
      --with-crypto=openssl \
      CPPFLAGS="-I$OPENSSL_OUTPUT_INCLUDE" \
      CFLAGS="-O2 -arch $arch -mmacosx-version-min=${MACOS_MIN_VERSION}" \
      LDFLAGS="-L$OPENSSL_OUTPUT_LIB -arch $arch -mmacosx-version-min=${MACOS_MIN_VERSION}"
  run_logged "$make_log" run_for_arch "$arch" make -j"$(sysctl -n hw.ncpu)"
  popd >/dev/null
}

finalize_static_library() {
  local output="$1"
  shift
  local inputs=("$@")
  if [[ "${#inputs[@]}" -eq 1 ]]; then
    cp "${inputs[0]}" "$output"
  else
    lipo -create "${inputs[@]}" -output "$output"
  fi
}

verify_library_arch() {
  local archive_path="$1"
  local expected_arch="$2"
  local arch_info

  if [[ ! -f "$archive_path" ]]; then
    echo "Missing archive for architecture verification: $archive_path" >&2
    exit 1
  fi

  arch_info="$(lipo -info "$archive_path" 2>&1 || true)"
  if [[ -z "$arch_info" ]]; then
    arch_info="$(file "$archive_path" 2>&1 || true)"
  fi

  case "$expected_arch" in
    arm64)
      if [[ "$arch_info" != *"arm64"* || "$arch_info" == *"x86_64"* ]]; then
        echo "Architecture verification failed for $archive_path. Expected arm64-only archive, got: $arch_info" >&2
        exit 1
      fi
      ;;
    x86_64)
      if [[ "$arch_info" != *"x86_64"* || "$arch_info" == *"arm64"* ]]; then
        echo "Architecture verification failed for $archive_path. Expected x86_64-only archive, got: $arch_info" >&2
        exit 1
      fi
      ;;
    universal)
      if [[ "$arch_info" != *"arm64"* || "$arch_info" != *"x86_64"* ]]; then
        echo "Architecture verification failed for $archive_path. Expected universal archive with arm64 and x86_64, got: $arch_info" >&2
        exit 1
      fi
      ;;
    *)
      echo "Unsupported expected architecture for verification: $expected_arch" >&2
      exit 1
      ;;
  esac
}

if have_cached_outputs; then
  echo "Using cached OpenSSL/libssh2 artifacts for: $EXPECTED_FINGERPRINT"
  echo "Prepared OpenSSL artifacts in: $OPENSSL_OUTPUT_ROOT"
  echo "Prepared libssh2 artifacts in: $LIBSSH2_OUTPUT_ROOT"
  exit 0
fi

download_if_missing "$OPENSSL_TARBALL" "$OPENSSL_URL" "$OPENSSL_SHA256"
download_if_missing "$LIBSSH2_TARBALL" "$LIBSSH2_URL" "$LIBSSH2_SHA256"

rm -rf "$BUILD_ROOT" "$OPENSSL_OUTPUT_INCLUDE" "$OPENSSL_OUTPUT_LIB" "$LIBSSH2_OUTPUT_INCLUDE" "$LIBSSH2_OUTPUT_LIB"
mkdir -p "$BUILD_ROOT" "$OPENSSL_OUTPUT_INCLUDE" "$OPENSSL_OUTPUT_LIB" "$LIBSSH2_OUTPUT_INCLUDE" "$LIBSSH2_OUTPUT_LIB"

for arch in "${ARCHES[@]}"; do
  echo "Building OpenSSL ($arch)..."
  build_openssl_arch "$arch"
done

FIRST_OPENSSL_ARCH="${ARCHES[0]}"
cp -R "$BUILD_ROOT/openssl-$FIRST_OPENSSL_ARCH/install/include/." "$OPENSSL_OUTPUT_INCLUDE/"

OPENSSL_CRYPTO_LIBS=()
OPENSSL_SSL_LIBS=()
for arch in "${ARCHES[@]}"; do
  OPENSSL_CRYPTO_LIBS+=("$BUILD_ROOT/openssl-$arch/install/lib/libcrypto.a")
  OPENSSL_SSL_LIBS+=("$BUILD_ROOT/openssl-$arch/install/lib/libssl.a")
done
finalize_static_library "$OPENSSL_OUTPUT_LIB/libcrypto.a" "${OPENSSL_CRYPTO_LIBS[@]}"
finalize_static_library "$OPENSSL_OUTPUT_LIB/libssl.a" "${OPENSSL_SSL_LIBS[@]}"
verify_library_arch "$OPENSSL_OUTPUT_LIB/libcrypto.a" "$ARCH_OVERRIDE_VALUE"
verify_library_arch "$OPENSSL_OUTPUT_LIB/libssl.a" "$ARCH_OVERRIDE_VALUE"

for arch in "${ARCHES[@]}"; do
  echo "Building libssh2 ($arch)..."
  build_libssh2_arch "$arch"
done

FIRST_LIBSSH2_ARCH="${ARCHES[0]}"
cp -R "$BUILD_ROOT/libssh2-$FIRST_LIBSSH2_ARCH/libssh2-$LIBSSH2_VERSION/include/." "$LIBSSH2_OUTPUT_INCLUDE/"

LIBSSH2_LIBS=()
for arch in "${ARCHES[@]}"; do
  LIBSSH2_LIBS+=("$BUILD_ROOT/libssh2-$arch/libssh2-$LIBSSH2_VERSION/src/.libs/libssh2.a")
done
finalize_static_library "$LIBSSH2_OUTPUT_LIB/libssh2.a" "${LIBSSH2_LIBS[@]}"
verify_library_arch "$LIBSSH2_OUTPUT_LIB/libssh2.a" "$ARCH_OVERRIDE_VALUE"

cat > "$BUILD_INFO_FILE" <<EOF2
libssh2 build info
fingerprint=$EXPECTED_FINGERPRINT
generated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
openssl_tarball=$OPENSSL_TARBALL
libssh2_tarball=$LIBSSH2_TARBALL
EOF2

echo "Prepared OpenSSL artifacts in: $OPENSSL_OUTPUT_ROOT"
echo "Prepared libssh2 artifacts in: $LIBSSH2_OUTPUT_ROOT"
