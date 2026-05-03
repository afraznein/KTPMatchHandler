#!/bin/bash
# KTPMatchHandler Plugin Compiler - WSL/Linux version
# Mirrors compile.bat functionality
#
# Production build (default):
#   bash compile.sh
#   → output: compiled/KTPMatchHandler.amxx (also auto-staged to KTP DoD Server)
#
# Test-mode build (for KTPInfrastructure Tier 2 integration tests):
#   KTP_TEST_MODE=1 bash compile.sh
#   → output: compiled/test/KTPMatchHandler.amxx (NOT staged to production)
#   → enables amx_ktp_test_* RCON commands per CHANGELOG 0.10.122. Production
#     binary remains unaffected — both builds are reproducible from the same
#     source tree.

set -e  # Exit on error

# Test-mode flag — read once at top so the rest of the script can branch.
# Empty string = production build; "1" = test-mode build.
TEST_MODE="${KTP_TEST_MODE:-}"

echo "========================================"
if [ "$TEST_MODE" = "1" ]; then
    echo "KTPMatchHandler Plugin Compiler (TEST-MODE)"
else
    echo "KTPMatchHandler Plugin Compiler (WSL)"
fi
echo "========================================"
echo

# ============================================
# Path Configuration
# ============================================

KTPAMXX_DIR="/mnt/n/Nein_/KTP Git Projects/KTPAMXX"
KTPAMXX_BUILD="$KTPAMXX_DIR/obj-linux/packages/base/addons/ktpamx/scripting"
KTPAMXX_INCLUDES="$KTPAMXX_DIR/plugins/include"

# Handle both direct execution and piped execution
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="/mnt/n/Nein_/KTP Git Projects/KTPMatchHandler"
fi
PLUGIN_NAME="KTPMatchHandler"
if [ "$TEST_MODE" = "1" ]; then
    OUTPUT_DIR="$SCRIPT_DIR/compiled/test"
else
    OUTPUT_DIR="$SCRIPT_DIR/compiled"
fi
STAGE_DIR="/mnt/n/Nein_/KTP Git Projects/KTP DoD Server/serverfiles/dod/addons/ktpamx/plugins"

TEMP_BUILD="/tmp/ktpbuild"

# ============================================
# Validation
# ============================================

if [ ! -f "$KTPAMXX_BUILD/amxxpc" ]; then
    echo "[ERROR] KTPAMXX Linux compiler not found!"
    echo "        Expected: $KTPAMXX_BUILD/amxxpc"
    echo "        Please build KTPAMXX first: cd KTPAMXX && ./build_linux.sh"
    exit 1
fi

if [ ! -f "$KTPAMXX_INCLUDES/amxmodx.inc" ]; then
    echo "[ERROR] KTPAMXX includes not found!"
    echo "        Expected: $KTPAMXX_INCLUDES"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/$PLUGIN_NAME.sma" ]; then
    echo "[ERROR] Source file not found: $PLUGIN_NAME.sma"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================
# Compile
# ============================================

echo "[INFO] Compiling $PLUGIN_NAME.sma..."
echo "       Compiler: $KTPAMXX_BUILD/amxxpc"
echo "       Includes: $KTPAMXX_INCLUDES"
echo

# Create temp build directory — wipe first so re-runs don't accumulate
# nested include/ dirs from `cp -r src dst` semantics, which silently
# breaks new shared includes added between runs.
rm -rf "$TEMP_BUILD"
mkdir -p "$TEMP_BUILD"

# Copy compiler and libraries
cp "$KTPAMXX_BUILD/amxxpc" "$TEMP_BUILD/"
cp "$KTPAMXX_BUILD/amxxpc32.so" "$TEMP_BUILD/"
cp -r "$KTPAMXX_INCLUDES" "$TEMP_BUILD/include"

# Convert line endings and copy source + local includes
sed 's/\r$//' "$SCRIPT_DIR/$PLUGIN_NAME.sma" > "$TEMP_BUILD/$PLUGIN_NAME.sma"
for inc in "$SCRIPT_DIR"/*.inc; do
    [ -f "$inc" ] && sed 's/\r$//' "$inc" > "$TEMP_BUILD/$(basename "$inc")"
done

# Generate build_info.inc for ktp_version_reporter — git SHA + build time
# get baked into the .amxx so `amx_ktp_versions` rcon can report what's
# actually deployed. Falls back to "unknown" if outside the canonical
# toolchain (e.g., compiling from a tarball without .git).
GIT_SHA=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=""
if [ "$GIT_SHA" != "unknown" ]; then
    if ! git -C "$SCRIPT_DIR" diff --quiet 2>/dev/null || \
       ! git -C "$SCRIPT_DIR" diff --cached --quiet 2>/dev/null; then
        GIT_DIRTY="-dirty"
    fi
fi
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%MZ)
cat > "$TEMP_BUILD/include/build_info.inc" <<EOF
#define KTP_BUILD_SHA "${GIT_SHA}${GIT_DIRTY}"
#define KTP_BUILD_TIME "$BUILD_TIME"
EOF
echo "[INFO] build_info: SHA=${GIT_SHA}${GIT_DIRTY} BUILD_TIME=$BUILD_TIME"

# Compile. amxxpc accepts trailing positional NAME=VALUE args as injected
# `#define`s; KTP_TEST_MODE=1 enables the test-mode block in KTPMatchHandler.sma
# (introduced in 0.10.122 — see CHANGELOG).
cd "$TEMP_BUILD"
if [ "$TEST_MODE" = "1" ]; then
    echo "[INFO] Building with -DKTP_TEST_MODE — adds amx_ktp_test_* RCON commands"
    ./amxxpc "$PLUGIN_NAME.sma" -i./include -i. -o"$PLUGIN_NAME.amxx" KTP_TEST_MODE=1
else
    ./amxxpc "$PLUGIN_NAME.sma" -i./include -i. -o"$PLUGIN_NAME.amxx"
fi

if [ $? -ne 0 ]; then
    echo
    echo "========================================"
    echo "[FAILED] Compilation failed!"
    echo "========================================"
    exit 1
fi

# Copy output
cp "$PLUGIN_NAME.amxx" "$OUTPUT_DIR/"

echo
echo "========================================"
echo "[SUCCESS] Compilation successful!"
echo "========================================"
echo "Output: $OUTPUT_DIR/$PLUGIN_NAME.amxx"
echo

# ============================================
# Stage to Server
# ============================================
# Test-mode binaries do NOT auto-stage. They consume from
# KTPInfrastructure/tests/integration/ via docker-compose volume mount on the
# data-server runner. Auto-staging into production would risk a test build
# bleeding into a production deploy via the .new auto-swap path on next restart.

if [ "$TEST_MODE" = "1" ]; then
    echo "[INFO] Test-mode build — staging skipped (binaries are consumed by"
    echo "       KTPInfrastructure integration-test docker-compose mount)."
else
    echo "[INFO] Staging to server..."
    if [ ! -d "$STAGE_DIR" ]; then
        echo "[WARN] Stage directory does not exist: $STAGE_DIR"
        echo "       Skipping staging."
    else
        cp "$OUTPUT_DIR/$PLUGIN_NAME.amxx" "$STAGE_DIR/$PLUGIN_NAME.amxx"
        echo "[OK] Staged: $STAGE_DIR/$PLUGIN_NAME.amxx"
    fi
fi

echo
echo "Done!"
