#!/usr/bin/env bash
# Install git hooks for this repo. Idempotent — safe to re-run.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

install -m 0755 "$REPO_ROOT/scripts/pre-push.sh" "$HOOKS_DIR/pre-push"
echo "installed: $HOOKS_DIR/pre-push"
