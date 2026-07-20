#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_DIR="$PROJECT_DIR/dist/Codex Whip.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swiftpm-module-cache"
swift build --disable-sandbox

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/.build/debug/CodexWhip" "$CONTENTS_DIR/MacOS/CodexWhip"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Sources/CodexWhip/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Sources/CodexWhip/Resources/whip-crack.mp3" "$CONTENTS_DIR/Resources/whip-crack.mp3"
codesign --force --deep --sign - "$APP_DIR"
# Finder commonly shows the bundle directory's mtime; refresh it after rebuilding.
touch "$APP_DIR"

echo "$APP_DIR"
