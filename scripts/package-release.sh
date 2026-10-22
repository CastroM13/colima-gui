#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ColimaManager.app"
ARCHIVE_NAME="ColimaManager-macOS-universal.zip"

"$ROOT_DIR/scripts/build-app.sh" --arch arm64 --arch x86_64
cp "$ROOT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/ColimaManager" -verify_arch arm64 x86_64

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ROOT_DIR/dist/$ARCHIVE_NAME"
cd "$ROOT_DIR/dist"
shasum -a 256 "$ARCHIVE_NAME" > SHA256SUMS.txt

echo "Created $ROOT_DIR/dist/$ARCHIVE_NAME"
