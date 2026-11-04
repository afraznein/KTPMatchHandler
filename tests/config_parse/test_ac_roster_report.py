"""Source-contract tests for the go-live anti-cheat roster report.

The report answers one question in game — who has a LIVE anti-cheat session as
the match goes live — and it has two properties that source can prove without a
live match, both of which are easy to lose in a later edit.

It must stay a REPORT.  Phase 7 enforcement is blocked on AC adoption, and a
refusal wired in here is a cvar flip away from breaking every match on the
fleet, so no failure path may return anything a caller could act on.

And its zero must be a measurement.  An empty roster and a call that never
landed produce the same session count, so the reading is believed only when the
body echoes the endpoint this server sent and carries a usable TTL and a
sessions array — two markers a failed or misrouted call cannot produce.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT


SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")


def _function_body(signature_prefix: str) -> str:
    """Source of one Pawn function, from its signature to the closing column-0 brace."""
    start = SOURCE.index(signature_prefix)
    end = SOURCE.index("\n}", start)
    return SOURCE[start:end]


def _log_events(body: str) -> set[str]:
    """The event= names this function body emits through log_ktp."""
    return {
        match.group(1)
        for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        for match in [re.search(r"event=(\S+)", fmt)]
        if match
    }


# ------------------------------------------------------------------ it reports

def test_the_roster_read_fires_beside_the_match_announce() -> None:
    """Same deferred go-live phase, so the reading is of the moment it describes."""
    body = _function_body("public task_deferred_discord_fwd(")
    assert "send_ac_roster_report(g_matchId)" in body
    assert body.index("send_ac_match_announce(g_matchId)") < body.index(
        "send_ac_roster_report(g_matchId)"
    ), "the announce creates the match row the roster reading is read against"


def test_the_report_is_read_only_over_http() -> None:
    """A POST field here would make a report into a write."""
    body = _function_body("stock send_ac_roster_report(")
    assert "CURLOPT_COPYPOSTFIELDS" not in body
    assert "CURLOPT_POSTFIELDS" not in body
    assert "/api/ac/server-roster?server_endpoint=" in body


def test_nothing_in_the_report_can_refuse_a_go_live() -> None:
    """Phase 7 is blocked on adoption; an enforcement knob must not appear here."""
    region = SOURCE[
        SOURCE.index("// ================= AC live-session roster at go-live") :
        SOURCE.index('log_ktp("event=AC_ROSTER_SEND')
    ]
    for forbidden in (
        "ktp_ac_enforce",
        "register_cvar",
        "create_cvar",
        "PLUGIN_HANDLED",
        "server_cmd",
        "kick",
    ):
        assert forbidden not in region, (
            f"{forbidden!r} appears in the roster report; this is a report, not the "
            "Phase 7 enforcement gate"
        )


def test_every_failure_path_returns_after_logging() -> None:
    """Config absent, curl error, non-2xx, unparseable body, match gone."""
    assert "AC_ROSTER_SKIP" in _log_events(_function_body("stock send_ac_roster_report("))

    send = _function_body("stock send_ac_roster_report(")
    assert "reason='curl_init_failed'" in send

    callback = _function_body("public ac_roster_callback(")
    assert "reason=curl" in callback, "a transport failure must name itself"
    assert "reason=http" in callback, "a non-2xx must name itself"
    assert callback.count("curl_easy_cleanup(curl)") >= 3, (
        "every exit from the callback leaks the handle otherwise"
    )

    render = _function_body("stock ac_roster_render(")
    assert "AC_ROSTER_UNPARSED" in _log_events(render)
    assert "AC_ROSTER_DISCARDED" in _log_events(render)


def test_an_unavailable_reading_is_said_out_loud() -> None:
    """Silence would otherwise read as 'nobody is live', which is the wrong answer."""
    body = _function_body("stock ac_roster_announce_unavailable(")
    assert "announce_all(" in body
    callback = _function_body("public ac_roster_callback(")
    assert callback.count("ac_roster_announce_unavailable()") == 2, (
        "both the curl-error and the non-2xx exits need it"
    )


# ------------------------------------------------------- the non-vacuity control

def test_a_zero_is_only_believed_behind_two_independent_markers() -> None:
    body = _function_body("stock ac_roster_render(")
    assert 'formatex(echoWant, charsmax(echoWant), "^"serverEndpoint^":^"%s^"", g_acServerEndpoint)' in body, (
        "the echo marker must be built from THIS server's endpoint"
    )
    assert "ac_roster_parse_ttl()" in body
    assert '^"sessions^":[' in body
    assert re.search(r"if\s*\(\s*!echoOk\s*\|\|\s*!sessionsOk\s*\|\|\s*ttl\s*<=\s*0\s*\)", body), (
        "the markers must gate the rendering, not merely be logged beside it"
    )


def test_the_control_line_carries_the_markers_beside_the_counts() -> None:
    """A reader must be able to tell a real zero from a call that never landed."""
    body = _function_body("stock ac_roster_render(")
    parse = next(
        fmt
        for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        if "event=AC_ROSTER_PARSE" in fmt
    )
    for field in (
        "endpoint_echo=",
        "sessions_marker=",
        "ttl=",
        "sessions=",
        "matched=",
        "on_teams=",
        "bytes=",
        "truncated=",
    ):
        assert field in parse, f"AC_ROSTER_PARSE omits {field!r}"


def test_sessions_present_but_none_matched_gets_its_own_line() -> None:
    """That is the universe-digit identity failure returning, not a compliance reading."""
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"if\s*\(\s*sessions\s*>\s*0\s*&&\s*matched\s*==\s*0\s*\)", body)
    assert "AC_ROSTER_NONE_MATCHED" in _log_events(body)


def test_the_body_terminator_is_forced_not_trusted() -> None:
    """Every scan walks to an EOS, so a native that filled the buffer exactly would
    let one run past the array."""
    body = _function_body("public ac_roster_callback(")
    assert "g_acRosterBody[AC_ROSTER_BODY_SIZE - 1] = EOS" in body
    assert body.index("curl_get_response_body") < body.index(
        "g_acRosterBody[AC_ROSTER_BODY_SIZE - 1] = EOS"
    ), "the terminator must be forced after the copy, not before it"


def test_a_truncated_body_is_not_read_as_a_short_roster() -> None:
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"bytes\s*>=\s*AC_ROSTER_BODY_SIZE\s*-\s*1", body)
    assert "truncated" in body


# -------------------------------------------------------------- parse mechanics

def _define(name: str) -> str:
    """The string a #define in the source expands to, with Pawn's ^" unescaped."""
    raw = re.search(rf'#define\s+{name}\s+"(.*)"\s*$', SOURCE, re.M)
    assert raw, f"#define {name} not found"
    return raw.group(1).replace('^"', '"')


def test_the_parse_advances_are_derived_from_the_tag_not_counted() -> None:
    """A hand-counted width read ttlSeconds 90 as 0, which retires the whole report."""
    ttl = _function_body("stock ac_roster_parse_ttl(")
    assert "at += strlen(tag)" in ttl
    assert not re.search(r"at\s*\+=\s*\d+", ttl), f"hand-counted advance in {ttl!r}"

    render = _function_body("stock ac_roster_render(")
    assert "+ strlen(sidTag)" in render
    assert not re.search(r"rel\s*\+\s*\d+", render), "hand-counted advance past the id tag"


def test_the_wire_tags_are_the_keys_the_endpoint_emits() -> None:
    """Tripwire on KTPAntiCheat.Api/Endpoints/AcEndpoints.cs GET /api/ac/server-roster."""
    assert _define("AC_ROSTER_SID_TAG") == '"steamId":"'
    assert _define("AC_ROSTER_TTL_TAG") == '"ttlSeconds":'


def test_the_session_split_attributes_each_blind_flag_to_its_own_entry() -> None:
    """The algorithm, mirrored in Python — not proof the Pawn runs, only that
    bounding on the next id tag is the right rule for this body shape."""
    sid_tag = _define("AC_ROSTER_SID_TAG")
    body = (
        '{"serverEndpoint":"203.0.113.9:27015","ttlSeconds":90,"sessions":['
        '{"steamId":"STEAM_0:0:11111111","clientVersion":"1.4.2",'
        '"lastSeenSecondsAgo":5,"captureBlind":false},'
        '{"steamId":"STEAM_0:1:22222222","clientVersion":"1.4.2",'
        '"lastSeenSecondsAgo":12,"captureBlind":true},'
        '{"steamId":"STEAM_0:0:33333333","clientVersion":"1.4.2",'
        '"lastSeenSecondsAgo":31,"captureBlind":false}]}'
    )

    seen, cursor = [], 0
    while True:
        rel = body.find(sid_tag, cursor)
        if rel == -1:
            break
        at = rel + len(sid_tag)
        end = body.index('"', at)
        nxt = body.find(sid_tag, end)
        window = body[end:] if nxt == -1 else body[end:nxt]
        seen.append((body[at:end], '"captureBlind":true' in window))
        cursor = end

    assert seen == [
        ("STEAM_0:0:11111111", False),
        ("STEAM_0:1:22222222", True),
        ("STEAM_0:0:33333333", False),
    ], seen

    ttl_tag = _define("AC_ROSTER_TTL_TAG")
    at = body.index(ttl_tag) + len(ttl_tag)
    assert body[at:at + 2] == "90", "the TTL advance must land on the first digit"


# --------------------------------------------------------------- identity rules

def test_matching_folds_the_universe_digit_on_both_sides() -> None:
    """A STEAM_1 heartbeat read under a STEAM_0 key once reported a live player absent."""
    tail = _function_body("stock ac_steam_tail(")
    assert 'contain(sid, ":")' in tail
    assert "if (colon == -1) return" in tail, (
        "an id with no account part must yield an empty tail, never a best effort"
    )

    body = _function_body("stock ac_roster_render(")
    assert "ac_steam_tail(sid, sessionTail" in body
    assert "ac_steam_tail(playerSid, playerTail" in body
    assert re.search(
        r"playerTail\[0\]\s*&&\s*equal\(\s*sessionTail\s*,\s*playerTail\s*\)", body
    ), "two unparseable ids must never compare equal"


def test_the_blind_flag_is_bounded_to_its_own_session() -> None:
    """Unbounded, a later entry's flag reads onto this player."""
    body = _function_body("stock ac_roster_render(")
    assert "boundAt" in body
    assert "g_acRosterBody[boundAt] = EOS" in body
    assert "g_acRosterBody[boundAt] = saved" in body, "the body must be restored in place"


def test_capture_blind_is_rendered_as_a_third_state() -> None:
    """A boolean would hide it, and a blind session is not an absent one."""
    body = _function_body("stock ac_roster_render(")
    assert '^"captureBlind^":true' in body
    assert "blindIds" in body and "liveIds" in body
    assert re.search(r"if\s*\(\s*blindNum\s*>\s*0\s*\)\s*ac_roster_announce_names\(", body)
    assert re.search(r"if\s*\(\s*liveNum\s*>\s*0\s*\)\s*ac_roster_announce_names\(", body)


def test_only_the_live_are_named() -> None:
    """Naming who is not running the client in open chat is accusation-adjacent."""
    body = _function_body("stock ac_roster_render(")
    labels = re.findall(r'ac_roster_announce_names\(\s*"([^"]+)"', body)
    assert labels, "the report must name somebody"
    for label in labels:
        lowered = label.lower()
        for forbidden in ("not ", "missing", "no ac", "absent", "non-compliant", "without"):
            assert forbidden not in lowered, (
                f"label {label!r} names the absent; the report lists who IS live and "
                "lets absence speak"
            )


def test_absence_is_not_worded_as_proof() -> None:
    """A 30s beat behind a 90s TTL means a fresh client can read absent."""
    body = _function_body("stock ac_roster_render(")
    announces = re.findall(r'announce_all\(\s*"([^"]+)"', body)
    assert any("not proof" in line for line in announces), (
        f"no caveat line among {announces}"
    )


# --------------------------------------------------------------------- teardown

def test_the_pending_roster_id_dies_with_match_identity() -> None:
    """An in-flight read must not print its answer into the next match."""
    reset = _function_body("stock ac_announce_state_reset(")
    assert "g_acRosterMatchId[0] = EOS" in reset
    assert "ac_announce_state_reset()" in _function_body("stock clear_match_id(")

    current = _function_body("stock bool:ac_roster_match_is_current(")
    assert "g_matchLive" in current
    assert "equal(g_matchId, g_acRosterMatchId)" in current


def test_test_mode_takes_no_outbound_reading() -> None:
    body = _function_body("stock send_ac_roster_report(")
    suppressed = body.index("TESTMATCH_OUTBOUND_SUPPRESSED")
    assert suppressed < body.index("curl_easy_init()")
    assert suppressed < body.index("g_acRosterMatchId")
