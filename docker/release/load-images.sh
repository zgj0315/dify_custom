#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
RELEASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE_PATH="${1:-$RELEASE_DIR/images.tar.gz}"
CHECKSUM_FILE="$RELEASE_DIR/SHA256SUMS"

if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "Missing image archive: $ARCHIVE_PATH"
  exit 1
fi

if [ -f "$CHECKSUM_FILE" ]; then
  echo "Verifying release bundle checksums"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$RELEASE_DIR" && sha256sum -c SHA256SUMS)
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS)
  else
    echo "No sha256 checksum tool found, skipping checksum verification"
  fi
fi

echo "Loading Docker images from $ARCHIVE_PATH"
docker image load -i "$ARCHIVE_PATH"
