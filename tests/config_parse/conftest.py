"""Path constants for KTPMatchHandler config-parse tests.

Mirrors the shape of KTPInfrastructure/tests/config_parse/conftest.py — see
that repo's `docs/CI_SETUP.md` for the parent test-infra design.
"""
from __future__ import annotations

from pathlib import Path

# tests/config_parse/conftest.py → repo root
REPO_ROOT = Path(__file__).resolve().parents[2]
