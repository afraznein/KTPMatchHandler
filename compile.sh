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

# A failed build must be VISIBLE, not merely non-zero. Callers pipe this script
# (`| tail`, `| tee`), and the shell then reports the PIPE's status -- so a failed
# build reads as exit 0 unless the log itself says so. Gate on the banners below,
# never on the exit code.
_ktp_build_exit() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo ""
        echo "========================================"
        echo "[KTP-BUILD] FAILED: KTPMatchHandler compile.sh exited $rc"
        echo "========================================"
        echo "Nothing has been staged."
    fi
    exit "$rc"
}
trap _ktp_build_exit EXIT


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

# Resolve KTPAMXX. Order: explicit override -> sibling checkout -> the path this
# script used to hardcode. A contributor who clones the repos side by side gets
# the sibling case for free; nobody has to edit this file to build, which they
# previously did.
if [ -n "${KTPAMXX_ROOT:-}" ]; then
    KTPAMXX_DIR="$KTPAMXX_ROOT"
elif [ -d "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/../KTPAMXX" ]; then
    KTPAMXX_DIR="$(cd "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/../KTPAMXX" && pwd)"
else
    KTPAMXX_DIR="/mnt/n/Nein_/KTP Git Projects/KTPAMXX"
fi
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
# Staging is the maintainer's local test tree; overridable, and every
# call site already skips it when absent, so a contributor just builds.
STAGE_DIR="${KTP_STAGING_DIR:-/mnt/n/Nein_/KTP Git Projects/KTP DoD Server/serverfiles/dod/addons/ktpamx/plugins}"
# Set KTP_NO_STAGE=1 to build WITHOUT touching the staging tree. Verifying a
# change to this script must not overwrite a staged artifact whose md5 is
# pinned to a reviewed build -- doing exactly that churned a wave pin on
# 2026-08-10. Every stage call site already tests -d, so a sentinel disables it.
[ -n "${KTP_NO_STAGE:-}" ] && STAGE_DIR="(staging disabled by KTP_NO_STAGE)"


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
# Resolve the SHA, and make a failure to resolve it VISIBLE. This value is baked
# into the artifact and reported by `amx_ktp_versions` over rcon, so a build that
# bakes "unknown" cannot say where it came from -- and nothing in the output said so.
#
# The way it fails is not obvious: building from a git WORKTREE under WSL cannot
# resolve the repo at all, because a worktree's .git is a FILE holding a WINDOWS
# path that WSL concatenates onto the cwd. `git rev-parse` then fails, the old
# `|| echo unknown` swallowed it, and GIT_DIRTY below is only computed when the SHA
# resolves -- so the result was indistinguishable from a clean off-toolchain build.
#
# KTP_BUILD_SHA_OVERRIDE lets a caller that knows the commit supply it.
# KTP_BUILD_REQUIRE_SHA=1 makes an unresolved SHA fatal, for release builds that
# must not ship without provenance. Neither is set by default.
if [ -n "${KTP_BUILD_SHA_OVERRIDE:-}" ]; then
    GIT_SHA="$KTP_BUILD_SHA_OVERRIDE"
elif GIT_SHA=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null); then
    :
else
    GIT_SHA="unknown"
    echo "========================================"
    echo "[WARN] Could not resolve a git SHA for this build."
    echo "       The artifact will bake KTP_BUILD_SHA \"unknown\" and cannot report"
    echo "       its provenance via amx_ktp_versions."
    echo "       If this is a git worktree under WSL, that is the cause -- build from"
    echo "       a plain clone, or pass KTP_BUILD_SHA_OVERRIDE=<sha>."
    echo "       Set KTP_BUILD_REQUIRE_SHA=1 to make this fatal instead."
    echo "========================================"
    if [ "${KTP_BUILD_REQUIRE_SHA:-0}" = "1" ]; then
        echo "[KTP-BUILD] FAILED: KTP_BUILD_REQUIRE_SHA=1 and no SHA could be resolved."
        exit 1
    fi
fi
GIT_DIRTY=""
if [ "$GIT_SHA" != "unknown" ]; then
    # `git status --porcelain` rather than `git diff`: diff ignores the index, so a
    # staged-but-uncommitted change read as clean. And a FAILING git must not read
    # as dirty -- the old form was `! git diff --quiet`, which treats exit 128 (not
    # a repo, e.g. a worktree under WSL) identically to exit 1 (really dirty). With
    # KTP_BUILD_SHA_OVERRIDE set that produced a "-dirty" artifact from a clean tree.
    if _ktp_status=$(git -C "$SCRIPT_DIR" status --porcelain 2>/dev/null); then
        [ -n "$_ktp_status" ] && GIT_DIRTY="-dirty"
    else
        # Could not tell. Say so rather than claiming clean.
        GIT_DIRTY="-unverified"
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
# `set -e` would kill the script here, so the check below never ran.
set +e
if [ "$TEST_MODE" = "1" ]; then
    echo "[INFO] Building with -DKTP_TEST_MODE — adds amx_ktp_test_* RCON commands"
    ./amxxpc "$PLUGIN_NAME.sma" -i./include -i. -o"$PLUGIN_NAME.amxx" KTP_TEST_MODE=1
else
    ./amxxpc "$PLUGIN_NAME.sma" -i./include -i. -o"$PLUGIN_NAME.amxx"
fi
AMXXPC_RC=$?
set -e

if [ "$AMXXPC_RC" -ne 0 ]; then
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

# Success sentinel, last line on the only path that reaches here. A caller checks
# for this rather than for `$?`, which a pipe launders.
echo "[KTP-BUILD] OK: KTPMatchHandler compile.sh"
