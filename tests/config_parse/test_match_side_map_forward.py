"""Source-contract tests for the name-free match side-map companion forward.

The forward is an ABI boundary shared with score collectors.  These tests are
deliberately structural: they prevent a later refactor from silently changing
the old match-start ABI, deriving overtime from regulation-half shortcuts, or
delivering the lifecycle event before observers know the current side map.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT


SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")
COMPACT = re.sub(r"\s+", " ", SOURCE)


def _between(start: str, end: str) -> str:
    start_at = SOURCE.index(start)
    end_at = SOURCE.index(end, start_at)
    return SOURCE[start_at:end_at]


def test_existing_match_start_forward_abi_is_unchanged() -> None:
    old_abi = (
        'g_fwdMatchStart = CreateMultiForward("ktp_match_start", ET_IGNORE, '
        "FP_STRING, FP_STRING, FP_CELL, FP_CELL);"
    )
    assert old_abi in COMPACT
    assert SOURCE.count('CreateMultiForward("ktp_match_start"') == 1


def test_companion_forward_has_exact_six_argument_contract() -> None:
    expected = (
        'g_fwdMatchSideMap = CreateMultiForward("ktp_match_side_map", ET_IGNORE, '
        "FP_STRING, FP_STRING, FP_STRING, FP_CELL, FP_CELL, FP_CELL);"
    )
    assert expected in COMPACT
    assert SOURCE.count('CreateMultiForward("ktp_match_side_map"') == 1


def test_regulation_mapping_is_h1_identity_then_h2_swap() -> None:
    helper = _between("stock team1_current_side()", "stock get_match_type_key")
    assert "if (g_inOvertime) return g_otTeam1StartsAs;" in helper
    assert "if (g_secondHalfPending || g_currentHalf == 2) return 2;" in helper
    assert "return 1;" in helper

    emitter = _between("stock emit_match_side_map(half)", "// The current period")
    assert "new team1Side = team1_current_side();" in emitter
    assert "new alliesTeamSlot = (team1Side == 1) ? 1 : 2;" in emitter
    assert "new axisTeamSlot = (team1Side == 2) ? 1 : 2;" in emitter


def test_overtime_uses_persisted_round_side_not_half_two_inference() -> None:
    helper = _between("stock team1_current_side()", "stock get_match_type_key")
    assert helper.index("g_inOvertime") < helper.index("g_currentHalf == 2")
    assert "return g_otTeam1StartsAs;" in helper

    emitter = _between("stock emit_match_side_map(half)", "// The current period")
    assert "team1_current_side()" in emitter
    assert "g_currentHalf == 2" not in emitter
    assert "half == 2" not in emitter

    # Explicit OT initializes team 1 on Allies; every continued round swaps the
    # actual persisted side.  OT half numbers are identity, not side inference.
    assert "g_otTeam1StartsAs = 1;" in SOURCE
    assert "g_otTeam1StartsAs = (g_otTeam1StartsAs == 1) ? 2 : 1;" in SOURCE
    assert "g_currentHalf = OT_HALF_BASE + g_otRound;" in SOURCE


def test_side_map_is_emitted_immediately_before_each_match_start() -> None:
    lifecycle = _between(
        "public task_deferred_discord_fwd()",
        "public cmd_status(id)",
    )
    assert SOURCE.count("ExecuteForward(g_fwdMatchStart") == 1
    assert lifecycle.count("ExecuteForward(g_fwdMatchStart") == 1
    assert lifecycle.count("emit_match_side_map(half);") == 1
    assert (
        "emit_match_side_map(half); ExecuteForward(g_fwdMatchStart, ret, "
        "g_matchId, g_currentMap, g_matchType, half);"
    ) in re.sub(r"\s+", " ", lifecycle)


def test_payload_is_name_free_and_recomputed_for_each_period() -> None:
    emitter = _between("stock emit_match_side_map(half)", "// The current period")
    assert (
        "ExecuteForward(g_fwdMatchSideMap, ret, g_matchId, g_currentMap, "
        "matchType, half, alliesTeamSlot, axisTeamSlot);"
    ) in re.sub(r"\s+", " ", emitter)
    assert "team1_current_side()" in emitter
    assert "g_teamName" not in emitter
    assert "g_team1Name" not in emitter
    assert "g_team2Name" not in emitter
    assert "authid" not in emitter.lower()
    assert "player" not in emitter.lower()


def test_match_type_wire_keys_are_canonical_and_bounded() -> None:
    helper = _between("stock get_match_type_key", "stock emit_match_side_map")
    expected = {
        "MATCH_TYPE_COMPETITIVE": "competitive",
        "MATCH_TYPE_SCRIM": "scrim",
        "MATCH_TYPE_12MAN": "12man",
        "MATCH_TYPE_DRAFT": "draft",
        "MATCH_TYPE_KTP_OT": "ktpOT",
        "MATCH_TYPE_DRAFT_OT": "draftOT",
    }
    for enum_name, wire_value in expected.items():
        assert re.search(
            rf"case\s+{enum_name}:\s+copy\(out,\s*maxlen,\s*\"{wire_value}\"\);",
            helper,
        )
    assert 'default:                     copy(out, maxlen, "unknown");' in helper

    emitter = _between("stock emit_match_side_map(half)", "// The current period")
    assert "new matchType[16];" in emitter
