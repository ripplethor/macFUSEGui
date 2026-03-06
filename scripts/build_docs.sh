#!/usr/bin/env bash
set -euo pipefail

# scripts/build_docs.sh
# Run from repo root: ./scripts/build_docs.sh
#
# Builds the static docs CSS bundle and runs docs validation by default.
# Set SKIP_DOCS_CHECK=1 to skip the validation step.
# Set FORCE_NPM_INSTALL=1 to refresh node_modules before building.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="$ROOT_DIR/package.json"
PACKAGE_LOCK="$ROOT_DIR/package-lock.json"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ensure_dependencies() {
  if [[ "${FORCE_NPM_INSTALL:-0}" == "1" || ! -d "$ROOT_DIR/node_modules" ]]; then
    echo "Installing docs dependencies..."
    if [[ -f "$PACKAGE_LOCK" ]]; then
      (cd "$ROOT_DIR" && npm ci)
    else
      (cd "$ROOT_DIR" && npm install)
    fi
  fi
}

[[ -f "$PACKAGE_JSON" ]] || {
  echo "Missing package.json at $PACKAGE_JSON" >&2
  exit 1
}

require_cmd npm
ensure_dependencies

echo "Building static docs CSS..."
(cd "$ROOT_DIR" && npm run docs:build-css)

if [[ "${SKIP_DOCS_CHECK:-0}" != "1" ]]; then
  echo "Running docs checks..."
  (cd "$ROOT_DIR" && npm run docs:check)
fi

echo "Docs build complete"
