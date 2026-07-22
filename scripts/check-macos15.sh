#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_ROOT=${CODEX_WHIP_COMPAT_BUILD_ROOT:-"$PROJECT_DIR/.build/compat/macos15"}

cd "$PROJECT_DIR"

for architecture in arm64 x86_64; do
    architecture_build_root="$BUILD_ROOT/$architecture"
    export CLANG_MODULE_CACHE_PATH="$architecture_build_root/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$architecture_build_root/swiftpm-module-cache"

    echo "Building CodexWhip for $architecture-apple-macosx15.0"
    swift build \
        --disable-sandbox \
        --scratch-path "$architecture_build_root" \
        --triple "$architecture-apple-macosx15.0"
done

native_architecture=$(uname -m)
native_build_root="$BUILD_ROOT/$native_architecture"
export CLANG_MODULE_CACHE_PATH="$native_build_root/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$native_build_root/swiftpm-module-cache"
native_bin_path=$(swift build \
    --disable-sandbox \
    --scratch-path "$native_build_root" \
    --triple "$native_architecture-apple-macosx15.0" \
    --show-bin-path)

echo "Running built-in self-check on the current Mac"
"$native_bin_path/CodexWhip" --self-check

echo "macOS 15 compatibility check passed for arm64 and x86_64"
