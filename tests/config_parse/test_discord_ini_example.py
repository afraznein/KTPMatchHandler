"""Schema validation for the in-repo Discord config template.

This is the per-plugin test for `documents/discord.ini.example` — the
template operators copy onto the server side. KTPInfrastructure has its
own central test against `config/online/discord.ini`; this test guards
the in-repo template against schema drift (key renames, format changes)
that would silently break the operator's first install of this plugin.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from .conftest import REPO_ROOT

CONFIG_PATH = REPO_ROOT / "documents" / "discord.ini.example"

REQUIRED_KEYS = {
    "discord_relay_url",
    "discord_channel_id",
    "discord_auth_secret",
}


def _parse_kv(path: Path) -> dict[str, str]:
    """Parse a flat `key=value` config. Comments are `;`. Whitespace
    around `=` is permitted. Returns lowercased keys."""
    out: dict[str, str] = {}
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        if "=" not in line:
            raise ValueError(f"{path.name}:{lineno}: expected key=value, got {line!r}")
        k, _, v = line.partition("=")
        k = k.strip().lower()
        v = v.strip()
        if v.startswith('"') and v.endswith('"'):
            v = v[1:-1]
        if k in out:
            raise ValueError(f"{path.name}:{lineno}: duplicate key {k!r}")
        out[k] = v
    return out


@pytest.fixture(scope="module")
def cfg() -> dict[str, str]:
    if not CONFIG_PATH.exists():
        pytest.skip(f"{CONFIG_PATH} not present")
    return _parse_kv(CONFIG_PATH)


def test_template_parses(cfg):
    assert cfg, f"{CONFIG_PATH.name}: produced no key/value pairs"


def test_required_keys_present(cfg):
    missing = REQUIRED_KEYS - set(cfg.keys())
    assert not missing, (
        f"{CONFIG_PATH.name}: missing required keys: {sorted(missing)}"
    )


def test_template_values_are_placeholders():
    """The .example template should ship with placeholder values, not real
    secrets. Anyone editing the file in place (instead of copying first)
    would surface here."""
    cfg = _parse_kv(CONFIG_PATH)

    # Each key's value should look unfilled. If someone accidentally
    # commits a real webhook URL or secret, this test trips immediately.
    placeholders = {"YOUR_RELAY_URL_HERE", "YOUR_CHANNEL_ID_HERE", "YOUR_SECRET_HERE"}
    for key, val in cfg.items():
        assert val in placeholders or not val, (
            f"{CONFIG_PATH.name}: {key}={val!r} doesn't look like a placeholder; "
            "did you accidentally commit a real secret?"
        )
