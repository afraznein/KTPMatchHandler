"""Schema validation for `ktp_maps.ini` — the plugin's per-map config map.

This file is a CI fixture. The table the fleet loads lives on each game host at
`<configsdir>/ktp_maps.ini` and is owned by `afraznein/KTPDoDServerConfig`; the
copy in this repo exists so these assertions run against the real shape.

What `load_map_mappings()` in `KTPMatchHandler.sma` actually does, which is what
these tests are allowed to assert:

  - it reads `config = <file>` and nothing else; `name` and `type` are never
    parsed, so they are documentary
  - a section that declares no `config` is skipped, not an error — the live
    table uses one for `dod_pandemic_aim`, whose settings come from the
    map-start config instead
  - it stops at `MAX_MAP_ROWS` bindings and truncates keys and values to the
    buffer widths below, all three silently

An earlier version of this file required `config`, `name` and `type` in every
section and pinned `type` to a closed set. Neither is a contract the plugin
implements, and the live table has violated all three since `dod_pandemic_aim`
shipped — so the test rejected the file the fleet was already running. Assert
the parser's contract, not the format's prose.
"""
from __future__ import annotations

import configparser
import re

import pytest

from .conftest import REPO_ROOT

CONFIG_PATH = REPO_ROOT / "ktp_maps.ini"

# KTPMatchHandler.sma: `#define MAX_MAP_ROWS 128`, `g_mapKeys[...][96]`,
# `g_mapCfgs[...][128]`. Exceeding any of the three loses bindings or mangles a
# path with no error at load time and no symptom until a match starts.
MAX_MAP_ROWS = 128
MAX_KEY_LEN = 95
MAX_CFG_LEN = 127

# A `.cfg` filename pattern. No directories — the plugin loads from the
# server's `addons/ktpamx/configs/` dir directly.
_CFG_RE = re.compile(r"^[A-Za-z0-9_.\-]+\.cfg$")

# Map names use the dod_ prefix in production; `.bsp` is stripped for the
# section name. Allow alphanumerics, underscore, dash.
_MAP_NAME_RE = re.compile(r"^[A-Za-z0-9_\-]+$")


@pytest.fixture(scope="module")
def parsed():
    # Do not skip on a missing file: removing the fixture would then read as a
    # pass. If it is gone, that is the failure.
    assert CONFIG_PATH.exists(), f"{CONFIG_PATH} is missing"
    parser = configparser.ConfigParser()
    parser.read(CONFIG_PATH, encoding="utf-8")
    return parser


def bindings(parser):
    """Sections the plugin turns into a binding: those carrying `config`."""
    return {s: parser.get(s, "config").strip() for s in parser.sections()
            if parser.has_option(s, "config")}


def test_file_parses_cleanly(parsed):
    # configparser raises on duplicate sections / unclosed values; we just
    # assert at least one map section exists post-parse.
    assert parsed.sections(), f"{CONFIG_PATH.name}: no sections parsed"


def test_at_least_one_section_declares_a_config(parsed):
    assert bindings(parsed), (
        f"{CONFIG_PATH.name}: no section declares `config`, so the plugin "
        f"would load zero bindings"
    )


def test_section_names_look_like_map_names(parsed):
    for section in parsed.sections():
        assert _MAP_NAME_RE.match(section), (
            f"{CONFIG_PATH.name}: section name {section!r} doesn't look like a map name"
        )


def test_config_values_are_cfg_filenames(parsed):
    for section, cfg in bindings(parsed).items():
        assert _CFG_RE.match(cfg), (
            f"{CONFIG_PATH.name} [{section}]: config={cfg!r} should be a bare .cfg filename"
        )


def test_sections_without_config_are_documentary_not_malformed(parsed):
    """A `config`-less section is legal; it must still name itself, so a reader
    can tell a deliberate documentary entry from a dropped `config` line."""
    for section in parsed.sections():
        if parsed.has_option(section, "config"):
            continue
        assert parsed.get(section, "name", fallback="").strip(), (
            f"{CONFIG_PATH.name} [{section}]: declares no `config`, so the plugin "
            f"skips it entirely — give it a `name` so that reads as deliberate"
        )


def test_name_values_are_non_empty(parsed):
    for section in parsed.sections():
        name = parsed.get(section, "name", fallback="").strip()
        assert name, f"{CONFIG_PATH.name} [{section}]: name is empty"


def test_binding_count_is_under_the_plugin_row_cap(parsed):
    count = len(bindings(parsed))
    assert count <= MAX_MAP_ROWS, (
        f"{CONFIG_PATH.name}: {count} bindings exceeds MAX_MAP_ROWS={MAX_MAP_ROWS}; "
        f"the plugin drops the overflow silently"
    )


def test_keys_and_values_fit_the_plugin_buffers(parsed):
    for section, cfg in bindings(parsed).items():
        assert len(section) <= MAX_KEY_LEN, (
            f"{CONFIG_PATH.name} [{section}]: section name is {len(section)} chars; "
            f"the plugin truncates at {MAX_KEY_LEN} and the lookup then never matches"
        )
        assert len(cfg) <= MAX_CFG_LEN, (
            f"{CONFIG_PATH.name} [{section}]: config={cfg!r} is {len(cfg)} chars; "
            f"the plugin truncates at {MAX_CFG_LEN} and execs a mangled path"
        )


def test_no_two_sections_are_the_same_map(parsed):
    """The plugin lowercases and strips `.bsp`, so two spellings collide."""
    seen = {}
    for section in parsed.sections():
        key = section.lower()
        if key.endswith(".bsp"):
            key = key[: -len(".bsp")]
        assert key not in seen, (
            f"{CONFIG_PATH.name}: [{section}] and [{seen[key]}] normalise to the same "
            f"map key {key!r}; the plugin keeps only the first"
        )
        seen[key] = section


def test_points_at_the_owning_repo():
    """The fleet's copy is elsewhere. Say so in the file, not only in a doc."""
    text = CONFIG_PATH.read_text(encoding="utf-8")
    assert "KTPDoDServerConfig" in text, (
        f"{CONFIG_PATH.name}: must name the owning repo, or the next reader edits "
        f"this copy and changes nothing on any server"
    )
