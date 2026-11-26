"""Source-contract tests for the ktp_match_aborted forward.

The forward exists so the HLTV recorder can close a demo window on the two
match closes that fire no ktp_match_end. Firing ktp_match_end there instead
would make stats consumers record a cancelled match as finished, so these
tests pin both where it fires and where it must not.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT


SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")
COMPACT = re.sub(r"\s+", " ", SOURCE)
INCLUDE = (REPO_ROOT / "ktp_matchhandler.inc").read_text(encoding="utf-8")


def _between(start: str, end: str) -> str:
    start_at = SOURCE.index(start)
    end_at = SOURCE.index(end, start_at)
    return SOURCE[start_at:end_at]


def test_forward_is_registered_once_with_four_argument_contract() -> None:
    expected = (
        'g_fwdMatchAborted = CreateMultiForward("ktp_match_aborted", ET_IGNORE, '
        "FP_STRING, FP_STRING, FP_CELL, FP_STRING);"
    )
    assert expected in COMPACT
    assert SOURCE.count('CreateMultiForward("ktp_match_aborted"') == 1


def test_forward_executes_only_from_the_helper_and_skips_an_empty_id() -> None:
    assert SOURCE.count("ExecuteForward(g_fwdMatchAborted") == 1
    helper = _between("stock fire_match_aborted(", "stock bool: ac_timeline_should_record()")
    assert "ExecuteForward(g_fwdMatchAborted" in helper
    assert helper.index("if (!matchId[0]) return;") < helper.index("ExecuteForward")


def test_fired_from_exactly_the_two_ruled_exits() -> None:
    calls = re.findall(r'fire_match_aborted\([^;]*\);', SOURCE)
    calls = [c for c in calls if "const matchId[]" not in c]
    assert calls == [
        'fire_match_aborted(savedMatchId, g_currentMap, "secondhalf_cancel");',
        'fire_match_aborted(g_matchId, g_currentMap, "forcereset");',
    ]


def _assert_after_teardown_before_clear(block: str, teardown: str, fire: str) -> None:
    assert block.index(teardown) < block.index(fire) < block.index("clear_match_id();")
    # The match type rides in the payload, so it must still be the match's own.
    reset = "g_matchType = MATCH_TYPE_COMPETITIVE;"
    if reset in block:
        assert block.index(fire) < block.index(reset)


def test_secondhalf_cancel_fires_after_close_and_before_identity_clear() -> None:
    block = _between("// Handle second half pending - this is cancelling the entire match after first half", 'disarm_ready_override("secondhalf_cancel");')
    block += _between('disarm_ready_override("secondhalf_cancel");', "reset_match_scores();")
    _assert_after_teardown_before_clear(
        block,
        'ktp_match_teardown_notify(savedMatchId, g_currentMap, "secondhalf_cancel"',
        'fire_match_aborted(savedMatchId, g_currentMap, "secondhalf_cancel");',
    )


def test_forcereset_fires_after_close_and_before_identity_clear() -> None:
    block = _between(
        'ktp_match_teardown_notify(g_matchId, g_currentMap, "forcereset"',
        'clear_competitive_match_flags("forcereset");',
    )
    _assert_after_teardown_before_clear(
        block,
        'ktp_match_teardown_notify(g_matchId, g_currentMap, "forcereset"',
        'fire_match_aborted(g_matchId, g_currentMap, "forcereset");',
    )


def test_aborted_exits_do_not_fire_match_end() -> None:
    cancel = _between("// Handle second half pending - this is cancelling the entire match after first half", "reset_match_scores();")
    reset = _between(
        'ktp_match_teardown_notify(g_matchId, g_currentMap, "forcereset"',
        'clear_competitive_match_flags("forcereset");',
    )
    for block in (cancel, reset):
        assert "g_fwdMatchEnd" not in block


_FP = {"string": "FP_STRING", "cell": "FP_CELL"}


def _include_signature(name: str) -> list[str]:
    m = re.search(r"forward\s+" + name + r"\s*\(([^)]*)\)\s*;", INCLUDE)
    assert m, f"{name} missing from ktp_matchhandler.inc"
    kinds = []
    for param in m.group(1).split(","):
        kinds.append(_FP["string"] if param.strip().endswith("[]") else _FP["cell"])
    return kinds


def _registered_signature(name: str) -> list[str]:
    m = re.search(r'CreateMultiForward\("' + name + r'",\s*ET_IGNORE,\s*([^)]*)\)', SOURCE)
    assert m, f"{name} not registered"
    return [p.strip() for p in m.group(1).split(",")]


def test_public_include_matches_every_registered_forward() -> None:
    registered = re.findall(r'CreateMultiForward\("(ktp_[a-z_]+)"', SOURCE)
    assert "ktp_match_aborted" in registered
    for name in registered:
        assert _include_signature(name) == _registered_signature(name), name


def test_public_include_has_a_guard() -> None:
    assert "#if defined _ktp_matchhandler_included" in INCLUDE
    assert "#define _ktp_matchhandler_included" in INCLUDE
