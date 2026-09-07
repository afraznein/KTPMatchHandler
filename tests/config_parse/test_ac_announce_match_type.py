"""Source-contract tests for the match type carried on the anti-cheat bodies.

`ktp_ac_match_index.match_type` was written NULL by every release before
0.10.170 because no announce ever carried the field.  These tests pin the three
things that made that defect possible and invisible: the key must be present on
both bodies, the vocabulary must stay joinable with what the column already
holds, and the widened format string must provably fit its buffer -- `formatex`
truncates in silence, so a payload that overflows would emit malformed JSON
rather than fail.
"""
from __future__ import annotations

import json
import re

from .conftest import REPO_ROOT


SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")

# The AC wire vocabulary, keyed by the MatchType enum member that selects it.
# These spellings are shared with KTPHLTVRecorder's MATCH_WINDOW_OPEN lines and
# with demo filenames, which is what makes the column joinable against them.
AC_MATCH_TYPE_KEYS = {
    "MATCH_TYPE_COMPETITIVE": "ktp",
    "MATCH_TYPE_SCRIM": "scrim",
    "MATCH_TYPE_12MAN": "12man",
    "MATCH_TYPE_DRAFT": "draft",
    "MATCH_TYPE_KTP_OT": "ktpot",
    "MATCH_TYPE_DRAFT_OT": "draftot",
}
AC_FALLBACK_KEY = "match"

# Pawn escapes a double quote as ^" — the payload literals are read back through
# this so the tests reason about real JSON rather than about Pawn source.
def _unescape(pawn_literal: str) -> str:
    return pawn_literal.replace('^"', '"')


def _body_format(buffer_name: str) -> str:
    """The format string passed to formatex for one of the two AC bodies."""
    # A Pawn string literal runs to the first UNESCAPED quote; ^" is the escape,
    # so it has to be consumed as one token or the match stops inside the JSON.
    call = re.search(
        r"formatex\(\s*" + re.escape(buffer_name) + r"\s*,\s*charsmax\("
        + re.escape(buffer_name) + r"\)\s*,\s*\"((?:\^\"|[^\"\n])*)\"\s*,",
        SOURCE,
    )
    assert call, f"no formatex call found for {buffer_name}"
    return _unescape(call.group(1))


def _define(name: str) -> int:
    m = re.search(r"#define\s+" + re.escape(name) + r"\s+(\d+)", SOURCE)
    assert m, f"#define {name} not found"
    return int(m.group(1))


def _decl_size(var: str) -> int:
    m = re.search(r"\bnew\s+" + re.escape(var) + r"\[(\d+)\]", SOURCE)
    assert m, f"declaration of {var} not found"
    return int(m.group(1))


def test_helper_maps_every_match_kind_to_the_ac_vocabulary() -> None:
    start = SOURCE.index("stock get_ac_match_type_key(")
    end = SOURCE.index("\n}", start)
    body = SOURCE[start:end]

    for enum_member, expected_key in AC_MATCH_TYPE_KEYS.items():
        assert re.search(
            r"case\s+" + re.escape(enum_member) + r":\s*copy\([^)]*\"" + expected_key + r"\"\)",
            body,
        ), f"{enum_member} must map to \"{expected_key}\""

    assert re.search(r"default:\s*copy\([^)]*\"" + AC_FALLBACK_KEY + r"\"\)", body)


def test_ac_vocabulary_is_not_the_side_map_forward_spelling() -> None:
    """get_match_type_key is the ktp_match_side_map ABI and must stay separate.

    Sharing one helper would either break that forward's contract or put two
    spellings of one concept into match_type, which is what makes the column
    joinable or not.
    """
    assert "stock get_ac_match_type_key(" in SOURCE
    assert "stock get_match_type_key(" in SOURCE

    forward_start = SOURCE.index("stock get_match_type_key(")
    forward_body = SOURCE[forward_start:SOURCE.index("\n}", forward_start)]
    assert '"competitive"' in forward_body
    assert '"ktpOT"' in forward_body

    ac_start = SOURCE.index("stock get_ac_match_type_key(")
    ac_body = SOURCE[ac_start:SOURCE.index("\n}", ac_start)]
    assert '"competitive"' not in ac_body
    assert '"ktpOT"' not in ac_body


def test_helper_is_defined_before_both_call_sites() -> None:
    """Pawn resolves calls in source order; a later definition fails to compile."""
    definition = SOURCE.index("stock get_ac_match_type_key(")
    announce = SOURCE.index("stock send_ac_match_announce(")
    end = SOURCE.index("stock send_ac_match_end(")
    assert definition < announce < end


def test_both_ac_bodies_emit_the_match_type_key() -> None:
    for buffer_name in ("g_acAnnouncePayload", "g_acEndPayload"):
        fmt = _body_format(buffer_name)
        assert '"matchType":"%s"' in fmt, f"{buffer_name} omits matchType"
        assert '"matchId":"%s"' in fmt
        assert '"serverEndpoint":"%s"' in fmt
        assert fmt.count("%s") == 3, f"{buffer_name} arity changed"


def test_rendered_body_is_valid_json_for_every_match_kind() -> None:
    for buffer_name in ("g_acAnnouncePayload", "g_acEndPayload"):
        fmt = _body_format(buffer_name)
        for key in list(AC_MATCH_TYPE_KEYS.values()) + [AC_FALLBACK_KEY]:
            rendered = fmt % ("1788138646-CHI1", "172.238.176.101:27015", key)
            parsed = json.loads(rendered)
            assert parsed["matchType"] == key
            assert parsed["matchId"] == "1788138646-CHI1"
            assert parsed["serverEndpoint"] == "172.238.176.101:27015"


def test_widest_possible_body_fits_both_buffers_without_truncation() -> None:
    """Re-derive the budget from the declarations, independently of #assert.

    formatex truncates silently, so the failure this guards against would ship
    as malformed JSON on the longest match ids rather than as an error.
    """
    match_id_max = _decl_size("g_matchId") - 1               # 63
    endpoint_max = _decl_size("g_acServerEndpoint") - 1      # 47
    type_max = _define("AC_MATCH_TYPE_SIZE") - 1             # 15

    # No vocabulary entry may overflow the type buffer in the first place.
    for key in list(AC_MATCH_TYPE_KEYS.values()) + [AC_FALLBACK_KEY]:
        assert len(key) <= type_max, f"{key!r} exceeds AC_MATCH_TYPE_SIZE"

    for buffer_name in ("g_acAnnouncePayload", "g_acEndPayload"):
        fmt = _body_format(buffer_name)
        widest = fmt % ("M" * match_id_max, "E" * endpoint_max, "T" * type_max)
        capacity = _decl_size(buffer_name)
        # +1 for the EOS formatex always writes.
        assert len(widest) + 1 <= capacity, (
            f"{buffer_name}[{capacity}] cannot hold {len(widest)}+1 worst-case bytes"
        )
        assert json.loads(widest)["matchType"] == "T" * type_max


def test_declared_literal_budget_matches_the_real_format_string() -> None:
    """The #define must track the format string, or the #assert guards nothing."""
    declared = _define("AC_BODY_LITERAL_BYTES")
    fmt = _body_format("g_acAnnouncePayload")
    actual = len(fmt.replace("%s", ""))
    assert declared == actual, f"AC_BODY_LITERAL_BYTES={declared} but literals are {actual}"


def test_compile_time_budget_assertions_are_present() -> None:
    assert "#assert AC_BODY_MAX_BYTES + 1 <= 512" in SOURCE
    assert "#assert AC_BODY_MAX_BYTES + 1 <= 256" in SOURCE
