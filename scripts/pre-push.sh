#!/usr/bin/env bash
# Pre-push hook for KTPMatchHandler.
#
# This repo is a ktp_discord.inc / amxxcurl consumer that ships an AMXX
# plugin loaded on every production KTP DoD server. Breaks land fast, so
# this hook gates pushes with the canonical amxxcurl async-lifetime lint
# from KTPInfrastructure — catches the slist UAF and sync-cleanup-after-
# async-perform anti-patterns documented in KTPAmxxCurl commit 7e1ce00
# (NY1 outage 2026-04-26).
#
# Currently a single-stage hook (lint only). The skeleton is in place if
# a future PR wants to add a Docker amxxpc compile or test stage.
#
# Requires KTPInfrastructure checked out as a sibling directory (same
# convention as KTPAMXX and DoD-hud-observer).
#
# Install with: scripts/install-hooks.sh
# Bypass once  : git push --no-verify
# Disable      : export KTP_SKIP_PREPUSH=1
set -euo pipefail

if [[ "${KTP_SKIP_PREPUSH:-0}" == "1" ]]; then
  echo "[pre-push] KTP_SKIP_PREPUSH=1 — skipping checks"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
INFRA_DIR="$REPO_ROOT/../KTPInfrastructure"

if [[ ! -d "$INFRA_DIR" ]]; then
  echo "[pre-push] KTPInfrastructure not found at $INFRA_DIR" >&2
  echo "[pre-push] Clone it as a sibling dir, or bypass with --no-verify" >&2
  exit 1
fi

# ============================================================
# amxxcurl async-lifetime lint (canonical, in KTPInfra)
# ============================================================
echo "[pre-push] amxxcurl lint"

LINT="$INFRA_DIR/scripts/hooks/lint-amxxcurl-async.sh"
if [[ ! -x "$LINT" ]]; then
  echo "[pre-push] canonical lint not found at $LINT" >&2
  echo "[pre-push] pull KTPInfrastructure (sibling dir) to latest, or bypass with --no-verify" >&2
  exit 1
fi

cd "$REPO_ROOT"
if ! "$LINT"; then
  echo "" >&2
  echo "[pre-push] LINT FAILED — see errors above." >&2
  echo "[pre-push] Bypass with --no-verify (and document why in the commit message)." >&2
  exit 1
fi

echo "[pre-push] lint OK"
