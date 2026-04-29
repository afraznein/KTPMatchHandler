"""Schema validation for `ktp_maps.ini` — the plugin's per-map config map.

Each section is a map name (without `.bsp`); each section carries:
  - `config` — a `.cfg` filename loaded by exec at match start
  - `name` — display string surfaced in chat / Discord embeds
  - `type` — one of {competitive, scrim, casual, draft, 12man, special}

A typo in any of these silently breaks match flow at runtime — the plugin
falls back to no map config. This test catches structural drift early.
"""
from __future__ import annotations

import configparser
import re

import pytest

from .conftest import REPO_ROOT

CONFIG_PATH = REPO_ROOT / "ktp_maps.ini"

# Per-section required keys. `name` is human-facing; everything else routes
# to runtime behavior. If a new section type is added in the plugin source,
# expand this set.
REQUIRED_KEYS = {"config", "name", "type"}

# Conservative — match what the plugin actually accepts. If the plugin
# grows new types, this list grows too.
ALLOWED_TYPES = {"competitive", "scrim", "casual", "draft", "12man", "special"}

# A `.cfg` filename pattern. No directories — the plugin loads from the
# server's `addons/ktpamx/configs/` dir directly.
_CFG_RE = re.compile(r"^[A-Za-z0-9_.\-]+\.cfg$")

# Map names use the dod_ prefix in production; `.bsp` is stripped for the
# section name. Allow alphanumerics, underscore, dash.
_MAP_NAME_RE = re.compile(r"^[A-Za-z0-9_\-]+$")


@pytest.fixture(scope="module")
def parsed():
    if not CONFIG_PATH.exists():
        pytest.skip(f"{CONFIG_PATH} not present")
    parser = configparser.ConfigParser()
    parser.read(CONFIG_PATH, encoding="utf-8")
    return parser


def test_file_parses_cleanly(parsed):
    # configparser raises on duplicate sections / unclosed values; we just
    # assert at least one map section exists post-parse.
    assert parsed.sections(), f"{CONFIG_PATH.name}: no sections parsed"


def test_required_keys_per_section(parsed):
    for section in parsed.sections():
        missing = REQUIRED_KEYS - set(parsed.options(section))
        assert not missing, (
            f"{CONFIG_PATH.name} [{section}]: missing required keys: {sorted(missing)}"
        )


def test_section_names_look_like_map_names(parsed):
    for section in parsed.sections():
        assert _MAP_NAME_RE.match(section), (
            f"{CONFIG_PATH.name}: section name {section!r} doesn't look like a map name"
        )


def test_config_values_are_cfg_filenames(parsed):
    for section in parsed.sections():
        cfg = parsed.get(section, "config", fallback="").strip()
        assert _CFG_RE.match(cfg), (
            f"{CONFIG_PATH.name} [{section}]: config={cfg!r} should be a bare .cfg filename"
        )


def test_type_values_are_in_allowed_set(parsed):
    for section in parsed.sections():
        t = parsed.get(section, "type", fallback="").strip().lower()
        assert t in ALLOWED_TYPES, (
            f"{CONFIG_PATH.name} [{section}]: type={t!r} not in {sorted(ALLOWED_TYPES)}"
        )


def test_name_values_are_non_empty(parsed):
    for section in parsed.sections():
        name = parsed.get(section, "name", fallback="").strip()
        assert name, f"{CONFIG_PATH.name} [{section}]: name is empty"


def test_no_duplicate_map_sections(parsed):
    """ConfigParser silently merges duplicate sections by default. We can't
    detect that post-parse, so re-scan the raw file for duplicate `[name]`
    headers. (This is the bug class where someone copy-pastes a section to
    edit it and forgets to rename — runtime then picks one arbitrarily.)"""
    seen: set[str] = set()
    dups: list[str] = []
    header_re = re.compile(r"^\s*\[([^\]]+)\]\s*$")
    for raw in CONFIG_PATH.read_text(encoding="utf-8").splitlines():
        m = header_re.match(raw)
        if not m:
            continue
        name = m.group(1).strip()
        if name in seen:
            dups.append(name)
        seen.add(name)
    assert not dups, f"{CONFIG_PATH.name}: duplicate sections: {dups}"
