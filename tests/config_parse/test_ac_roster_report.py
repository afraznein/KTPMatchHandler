"""Source-contract tests for the go-live anti-cheat roster report.

The report answers one question in game — who has a LIVE anti-cheat session as
the match goes live — and it has three properties that source can prove without
a live match, all of which are easy to lose in a later edit.

It must stay a REPORT.  Phase 7 enforcement is blocked on AC adoption, and a
refusal wired in here is a cvar flip away from breaking every match on the
fleet, so no failure path may return anything a caller could act on.

It must ask BY PLAYER ID.  The endpoint-scoped read this replaced asked which
clients claimed to be on this server's address, off a field the client asserts
and nothing verifies, and it once told a full server that nobody was running the
anti-cheat while every player on it was live.  A single surviving endpoint
comparison on this side puts that defect back behind a correct API, so the tests
below assert the ABSENCE of one and not merely the presence of the new route.

And its zero must be a measurement.  An empty reading and a call that never
landed produce the same count, so the reading is believed only when the body
carries a usable TTL and a sessions array AND holds one row per id this server
submitted, each echoing the bytes sent.  That row echo is what replaced the
endpoint echo: it is bound to this request, where the endpoint was not.
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


def _strip_comments(body: str) -> str:
    """Code only. A prose mention of a native is not a call to it."""
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//.*", "", body)


def _log_events(body: str) -> set[str]:
    """The event= names this function body emits through log_ktp."""
    return {
        match.group(1)
        for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        for match in [re.search(r"event=(\S+)", fmt)]
        if match
    }


def _roster_region() -> str:
    """Every line of the roster feature, request through render."""
    start = SOURCE.index("// ================= AC live-session roster at go-live")
    end = SOURCE.index('curl_easy_perform(curl, "ac_roster_callback");')
    return SOURCE[start : SOURCE.index("\n}", end)]


# ------------------------------------------------------------------ it reports

def test_the_roster_read_fires_beside_the_match_announce() -> None:
    """Same deferred go-live phase, so the reading is of the moment it describes."""
    body = _function_body("public task_deferred_discord_fwd(")
    assert "send_ac_roster_report(g_matchId)" in body
    assert body.index("send_ac_match_announce(g_matchId)") < body.index(
        "send_ac_roster_report(g_matchId)"
    ), "the announce creates the match row the roster reading is read against"


def test_nothing_in_the_report_can_refuse_a_go_live() -> None:
    """Phase 7 is blocked on adoption; an enforcement knob must not appear here."""
    region = _strip_comments(SOURCE[
        SOURCE.index("// ================= AC live-session roster at go-live") :
        SOURCE.index('log_ktp("event=AC_ROSTER_SEND')
    ])
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
    """Config absent, no roster, body headroom, curl error, 4xx, non-2xx, match gone."""
    send = _function_body("stock send_ac_roster_report(")
    assert "AC_ROSTER_SKIP" in _log_events(send)
    assert "AC_ROSTER_NO_ROSTER" in _log_events(send)
    assert "reason='curl_init_failed'" in send
    assert "reason='body_headroom'" in send

    callback = _function_body("public ac_roster_callback(")
    assert "reason=curl" in callback, "a transport failure must name itself"
    assert "reason=http" in callback, "a non-2xx must name itself"
    assert "AC_ROSTER_REFUSED" in _log_events(callback), "a 4xx must name itself"
    assert callback.count("curl_easy_cleanup(curl)") >= 4, (
        "every exit from the callback leaks the handle otherwise"
    )

    render = _function_body("stock ac_roster_render(")
    assert "AC_ROSTER_UNPARSED" in _log_events(render)
    assert "AC_ROSTER_DISCARDED" in _log_events(render)
    assert "AC_ROSTER_ECHO_MISMATCH" in _log_events(render)


def test_an_unavailable_reading_is_said_out_loud() -> None:
    """Silence would otherwise read as 'nobody is live', which is the wrong answer."""
    body = _function_body("stock ac_roster_announce_unavailable(")
    assert "announce_all(" in body
    callback = _function_body("public ac_roster_callback(")
    assert callback.count("ac_roster_announce_unavailable()") == 3, (
        "the curl-error, 4xx and non-2xx exits each need it"
    )


# ------------------------------------------------- it asks by id, not by endpoint

def test_the_request_is_the_id_scoped_route() -> None:
    body = _function_body("stock send_ac_roster_report(")
    assert "/api/ac/live-sessions" in body
    assert "server-roster" not in body, "the endpoint-scoped route must be gone"
    assert "CURLOPT_COPYPOSTFIELDS" in body, (
        "a roster of ids goes in the POST body; a URL would be a fixed buffer again"
    )


def test_not_one_endpoint_comparison_survives_in_the_roster_path() -> None:
    """The whole point of the change. A correct API does not help if this side still
    filters on an address the client asserted, so absence is what is asserted here."""
    code = _strip_comments(_roster_region())
    assert "g_acServerEndpoint" not in code
    assert "endpoint" not in code.lower(), (
        "an endpoint read anywhere in this path is the defect surviving behind a "
        "correct API"
    )
    # CONTROL — the region really is the roster feature and really was searched.
    assert code.count("g_acRosterBody") > 5
    assert code.count("g_acLiveIds") > 1


def test_the_ids_sent_are_the_players_being_gated() -> None:
    """Derived from this server's own connected players, never from an API reply."""
    body = _function_body("stock send_ac_roster_report(")
    assert "get_match_participants(participants, pnum)" in body
    assert "get_user_team(participants[i])" in body
    assert "get_user_authid(participants[i], sid, charsmax(sid))" in body
    assert re.search(r"copy\(g_acLiveIds\[g_acLiveNum\],\s*charsmax\(g_acLiveIds\[\]\),\s*sid\)", body), (
        "the id must be stored as read, with no second spelling derived from it"
    )


def test_the_only_plugin_side_id_test_is_sendability() -> None:
    """Folding the universe digit here would be a second identity path. The API folds
    STEAM_1 for every reader; a fold on this side can disagree with it, and that
    disagreement once read a live player as not running the client at all."""
    body = _function_body("stock send_ac_roster_report(")
    assert 'contain(sid, ":") == -1' in body, (
        "an id with no account part cannot be asked about"
    )
    assert "g_acLiveUnsendable++" in body, "and it must be counted, not dropped silently"
    code = _strip_comments(_roster_region())
    for forbidden in ("ac_steam_tail", "canonical", "universe", "STEAM_0", "STEAM_1"):
        assert forbidden not in code, (
            f"{forbidden!r} in the roster path is a canonical spelling derived on this "
            "side; rows are matched on the bytes that were sent"
        )
    assert "ac_steam_tail" not in SOURCE, (
        "the helper is dead once matching is by echo, and a dead predicate reads as "
        "the canonical one the next caller should reach for"
    )


# ---------------------------------------------------- the request cannot truncate

def _define_num(name: str) -> str:
    raw = re.search(rf"^#define\s+{name}\s+(.+?)\s*(?://.*)?$", SOURCE, re.M)
    assert raw, f"#define {name} not found"
    return raw.group(1).strip()


def test_the_request_buffer_is_derived_from_the_worst_case_not_written_as_a_literal() -> None:
    """A fixed body buffer truncating at a full roster is the same silent-short-read
    class the endpoint filter belonged to: the request would ask about fewer players
    than the reading then claims to cover."""
    body_max = _define_num("AC_LIVE_BODY_MAX")
    assert "AC_LIVE_LITERAL_BYTES" in body_max and "AC_LIVE_MAX_IDS" in body_max
    assert "AC_LIVE_ROW_MAX" in body_max
    assert not re.fullmatch(r"\d+", body_max), f"{body_max!r} is a literal"

    decl = re.search(r"new g_acLiveBody\[([^\]]+)\]", SOURCE)
    assert decl and "AC_LIVE_BODY_MAX" in decl.group(1), (
        "the buffer must be sized from the arithmetic, not beside it"
    )

    row = _define_num("AC_LIVE_ROW_MAX")
    assert "AC_LIVE_ID_BYTES" in row, "a row must be sized from the id capacity"
    assert "AC_LIVE_ID_SIZE" in _define_num("AC_LIVE_ID_BYTES")


def test_the_id_count_is_bounded_under_the_api_cap_at_compile_time() -> None:
    """A run-time clamp would drop a player from the reading and report the remainder
    as the whole team; the assert makes the over-limit 400 unreachable instead."""
    assert _define_num("AC_LIVE_MAX_IDS") == "MAX_PLAYERS"
    assert re.search(
        r"^#assert\s+AC_LIVE_MAX_IDS\s*<=\s*AC_LIVE_API_MAX_IDS\s*$", SOURCE, re.M
    ), "nothing holds the roster under the API's cap"
    body = _function_body("stock send_ac_roster_report(")
    assert "g_acLiveNum < AC_LIVE_MAX_IDS" in body, (
        "the array write needs the bound even where the assert makes it unreachable"
    )
    # Structural, not test-held: raising the cap must not overflow an array declared
    # from MAX_PLAYERS while the assert above still passes.
    assert "new g_acLiveIds[AC_LIVE_MAX_IDS][AC_LIVE_ID_SIZE]" in SOURCE
    assert "new g_acLiveSlots[AC_LIVE_MAX_IDS]" in SOURCE
    render = _function_body("stock ac_roster_render(")
    for decl in ("listed[AC_LIVE_MAX_IDS]", "liveIds[AC_LIVE_MAX_IDS]",
                 "blindIds[AC_LIVE_MAX_IDS]"):
        assert decl in render, f"{decl} is still sized from MAX_PLAYERS"


def test_the_api_cap_matches_the_merged_route() -> None:
    """A REMINDER, not a tripwire, and the docstring says so because the difference
    matters: this suite cannot reach the other repo, so it asserts this plugin's own
    copy of KTPAntiCheat.Api/Endpoints/AcEndpoints.cs `MaxLiveSessionIds` and cannot
    notice the API lowering its cap. What makes the drift survivable is that the
    consequence is a 400, reported as AC_ROSTER_REFUSED, rather than a wrong reading."""
    assert _define_num("AC_LIVE_API_MAX_IDS") == "64"
    source_note = SOURCE[SOURCE.index("#define AC_LIVE_API_MAX_IDS") - 400 :
                         SOURCE.index("#define AC_LIVE_API_MAX_IDS")]
    assert "NOT tied" in source_note, (
        "the copy must say it is a copy, or the next reader takes it for a tie"
    )


def test_the_full_worst_case_request_fits_the_derived_buffer() -> None:
    """The arithmetic, evaluated: the literals plus a full roster of maximum-width
    ids must fit, or the headroom guard fires on a legitimate full server."""
    id_size = int(_define_num("AC_LIVE_ID_SIZE"))
    literal = int(_define_num("AC_LIVE_LITERAL_BYTES"))
    max_ids = int(re.search(r"^#define\s+MAX_PLAYERS\s+(\d+)", SOURCE, re.M).group(1))

    rendered = '{"steamIds":[' + ",".join(['"' + "x" * (id_size - 1) + '"'] * max_ids) + "]}"
    budget = literal + max_ids * ((id_size - 1) + 3)
    assert len(rendered) <= budget, (
        f"a full roster renders to {len(rendered)} against a budget of {budget}"
    )
    assert literal >= len('{"steamIds":[]}')


def test_an_empty_roster_is_decided_here_and_not_spent_on_a_certain_400() -> None:
    """The API refuses an empty list. Sending one would come back as a 4xx, which is
    the same shape as a contract change and reads like an unreachable API."""
    body = _function_body("stock send_ac_roster_report(")
    assert re.search(r"if\s*\(\s*!g_acLiveNum\s*\)", body)
    assert body.index("AC_ROSTER_NO_ROSTER") < body.index("curl_easy_init()"), (
        "the empty case must return before a request is built"
    )
    assert "ac_roster_announce_unavailable()" in body, "and must still say so out loud"
    assert body.index("copy(g_acRosterMatchId") < body.index("AC_ROSTER_NO_ROSTER"), (
        "the pending id must be set first, or the notice is suppressed as stale and "
        "the empty roster passes silently"
    )


def test_a_4xx_is_told_apart_from_an_unreachable_api() -> None:
    """A definite refusal and a dead API both fail open to the same chat line, so the
    log is the only place they can be distinguished — and after the bounds above, a
    4xx means the route's contract moved."""
    callback = _function_body("public ac_roster_callback(")
    assert re.search(r"if\s*\(\s*httpCode\s*>=\s*400\s*&&\s*httpCode\s*<\s*500\s*\)", callback)
    assert callback.index("AC_ROSTER_REFUSED") < callback.index("reason=http"), (
        "the 4xx branch must precede the general non-2xx branch or it never runs"
    )
    refused = next(
        fmt for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', callback)
        if "AC_ROSTER_REFUSED" in fmt
    )
    for field in ("http=", "on_teams=", "body_max="):
        assert field in refused, f"AC_ROSTER_REFUSED omits {field!r}"


# ------------------------------------------------------- the non-vacuity control

def test_a_zero_is_only_believed_behind_the_marker_gate() -> None:
    body = _function_body("stock ac_roster_render(")
    assert "ac_roster_parse_ttl()" in body
    assert "AC_ROSTER_SESSIONS_TAG" in body
    assert re.search(r"if\s*\(\s*!sessionsOk\s*\|\|\s*ttl\s*<=\s*0\s*\)", body), (
        "the markers must gate the rendering, not merely be logged beside it"
    )


def test_the_row_echo_is_the_gate_that_replaced_the_endpoint_echo() -> None:
    """Bound to THIS request, where the endpoint was a client-asserted field. One row
    per submitted id, each echoing the bytes sent, is the route's contract."""
    body = _function_body("stock ac_roster_render(")
    assert re.search(
        r"if\s*\(\s*rows\s*!=\s*g_acLiveNum\s*\|\|\s*echoed\s*!=\s*rows"
        r"\s*\|\|\s*activeMissing\s*>\s*0\s*\)", body
    ), "the echo contract must gate the announce, not merely be logged"
    gate = body.index("AC_ROSTER_ECHO_MISMATCH")
    assert gate < body.index('announce_all("Anti-cheat check at go-live'), (
        "a reading must not be printed off a reply that broke the contract"
    )
    assert "ac_roster_announce_unavailable()" in body[gate : gate + 600]


def test_the_control_line_carries_the_markers_beside_the_counts() -> None:
    """A reader must be able to tell a real zero from a call that never landed."""
    body = _function_body("stock ac_roster_render(")
    parse = next(
        fmt
        for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        if "event=AC_ROSTER_PARSE" in fmt
    )
    for field in (
        "sessions_marker=",
        "ttl=",
        "objects=",
        "rows=",
        "echoed=",
        "on_teams=",
        "matched=",
        "blind_unparsed=",
        "active_missing=",
        "slots_not_connected=",
        "slots_authid_changed=",
        "bytes=",
        "truncated=",
    ):
        assert field in parse, f"AC_ROSTER_PARSE omits {field!r}"
    assert "endpoint" not in parse, (
        "the endpoint has no place in this line; its echo is not the control any more"
    )


def test_no_rows_matched_is_the_reading_and_not_flagged_as_a_fault() -> None:
    """The inversion the route change forces. Under endpoint scoping, sessions present
    with nobody matched was the identity failure returning. Under id scoping every
    submitted id answers, so matched=0 behind the echo gate is the true answer —
    nobody on teams is running the client — and a fault line there would make a
    correct reading look like a broken call."""
    body = _function_body("stock ac_roster_render(")
    assert "AC_ROSTER_NONE_MATCHED" not in body
    assert "AC_ROSTER_NONE_MATCHED" not in SOURCE
    assert not re.search(r"matched\s*==\s*0", body), (
        "nothing may branch on a zero reading; the echo gate is what catches a "
        "broken call now"
    )


def test_a_truncated_body_is_not_read_as_a_short_roster() -> None:
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"bytes\s*>=\s*AC_ROSTER_BODY_SIZE\s*-\s*1", body)
    assert "truncated" in body
    mismatch = next(
        fmt for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        if "AC_ROSTER_ECHO_MISMATCH" in fmt
    )
    assert "truncated=" in mismatch, (
        "a truncated reply loses rows, so it lands on the echo gate and must say so"
    )


def test_the_full_worst_case_reply_fits_the_derived_buffer() -> None:
    """EVALUATED, not symbol-checked, because the request-side twin of this test is
    what caught the only numeric defect in this change: the row literal measures one
    row's own braces and keys, so a reply of them also needs a separator each, and a
    hand count missed every one of them. Render it and compare."""
    def num(name: str) -> int:
        return int(_define_num(name))

    id_bytes = num("AC_LIVE_ID_SIZE") - 1
    cver = num("AC_ROSTER_CLIENTVER_BYTES")
    lastseen = num("AC_ROSTER_LASTSEEN_BYTES")
    literal = num("AC_ROSTER_ROW_LITERAL_BYTES")
    sep = num("AC_ROSTER_ROW_SEPARATOR_BYTES")
    envelope = num("AC_ROSTER_ENVELOPE_BYTES")
    max_ids = int(re.search(r"^#define\s+MAX_PLAYERS\s+(\d+)", SOURCE, re.M).group(1))

    row = (
        '{"steamId":"%s","active":false,"clientVersion":"%s",'
        '"lastSeenSecondsAgo":%s,"endedGracefully":false,"captureBlind":false}'
        % ("i" * id_bytes, "v" * cver, "9" * lastseen)
    )
    rendered = '{"ttlSeconds":90,"sessions":[' + ",".join([row] * max_ids) + "]}"

    row_max = literal + id_bytes + cver + lastseen + sep
    charsmax = envelope + max_ids * row_max  # BODY_SIZE is that + 1; charsmax is size-1
    assert len(rendered) <= charsmax, (
        f"a full reply renders to {len(rendered)} against charsmax {charsmax}"
    )
    # CONTROL — the literal really does exclude the separator, which is the whole
    # reason the +1 exists. Without it the budget is short by one per gap.
    assert len(row) == literal + id_bytes + cver + lastseen
    assert envelope >= len('{"ttlSeconds":90,"sessions":[]}')


def test_the_reply_buffer_is_sized_for_a_row_per_submitted_id() -> None:
    """This route answers about every id sent, not only the live ones, so a full
    server is the ordinary case. The size the endpoint-scoped read needed would now
    refuse every full-server reading through the echo gate."""
    size = _define_num("AC_ROSTER_BODY_SIZE")
    assert "AC_LIVE_MAX_IDS" in size and "AC_ROSTER_ROW_MAX" in size
    assert not re.fullmatch(r"\d+", size), f"{size!r} is a literal"
    row = _define_num("AC_ROSTER_ROW_MAX")
    for part in ("AC_ROSTER_ROW_LITERAL_BYTES", "AC_LIVE_ID_BYTES",
                 "AC_ROSTER_ROW_FIELD_BYTES", "AC_ROSTER_ROW_SEPARATOR_BYTES"):
        assert part in row, f"the reply row omits {part}"
    fields = _define_num("AC_ROSTER_ROW_FIELD_BYTES")
    assert "AC_ROSTER_CLIENTVER_BYTES" in fields and "AC_ROSTER_LASTSEEN_BYTES" in fields


# ------------------------------------------------------- row matching by the echo

def test_rows_are_matched_on_the_bytes_that_were_sent() -> None:
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"equal\(\s*g_acLiveIds\[i\]\s*,\s*sid\s*\)", body), (
        "the match must be an exact compare against the id submitted"
    )
    assert re.search(r"if\s*\(\s*hit\s*==\s*-1\s*\)\s*continue;", body), (
        "a row echoing nothing we sent must not be attributed to anybody"
    )
    assert "echoed++" in body
    assert "listed[hit] = true" in body, (
        "one entry per player, or two rows on one id name him twice"
    )


def test_submission_order_is_a_control_and_not_the_matching() -> None:
    """The API promises order. Matching by string does not need it, so a disagreement
    is visible without being load-bearing."""
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"if\s*\(\s*hit\s*!=\s*row\s*\)\s*ordinalOff\+\+;", body)
    assert "ordinal_off=" in next(
        fmt for fmt in re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)
        if "event=AC_ROSTER_PARSE" in fmt
    )
    assert not re.search(r"g_acLiveIds\[\s*row\s*\]", body), (
        "nothing may index the sent list by the row's position"
    )


def test_a_slot_is_revalidated_before_anybody_is_named() -> None:
    """Slots recycle across an async boundary, and is_user_connected only proves the
    slot is occupied. The id captured at send time is the identity."""
    body = _function_body("stock ac_roster_render(")
    assert "is_user_connected(g_acLiveSlots[hit])" in body
    assert re.search(
        r"if\s*\(\s*!equal\(\s*nowSid\s*,\s*g_acLiveIds\[hit\]\s*\)\s*\)", body
    ), "the authid must be re-read and compared, not trusted to the slot"
    # Told apart: a player who left and a different person in his slot mean different
    # things to a captain reading a low count.
    assert "notConnected++" in body and "authidChanged++" in body
    revalidate = body.index("nowSid")
    assert revalidate < body.index("blindIds[blindNum++]"), (
        "the compare must precede the naming or it is decoration"
    )


def test_the_liveness_flag_is_read_and_its_zero_is_a_measurement() -> None:
    """Presence in the array used to mean live. Every submitted id now gets a row, so
    liveness is a field — and a field whose spelling moves would read as nobody live,
    which is a plausible answer rather than an obvious fault."""
    body = _function_body("stock ac_roster_render(")
    assert '^"active^":true' in body
    assert '^"active^":false' in body, "the false literal is the control"
    assert "activeMissing++" in body
    assert re.search(r"if\s*\(\s*!activeTrue\s*&&\s*!activeFalse\s*\)\s*activeMissing\+\+;", body), (
        "the counter must fire whenever NEITHER literal matched"
    )
    assert re.search(r"if\s*\(\s*!activeTrue\s*\)\s*continue;", body), (
        "a row that is not active must not be named live"
    )
    assert "AC_ROSTER_ACTIVE_MISSING" in _log_events(body)


def test_a_renamed_liveness_key_cannot_announce_a_false_zero() -> None:
    """The one hole the echo gate did not close on its own, and the worst-shaped one:
    rename `active` and every row reads not-live, the row count and the echo still
    agree, and chat announces "0 of N" — a false "nobody is running the client" with
    no control firing. So the absence is counted with NO tag-presence precondition,
    unlike the blind flag, and it gates the reading."""
    body = _function_body("stock ac_roster_render(")
    counter = re.search(r"if\s*\(\s*!activeTrue\s*&&\s*!activeFalse([^)]*)\)\s*activeMissing", body)
    assert counter, "the liveness counter is not where this test thinks it is"
    assert "AC_ROSTER_ACTIVE_TAG" not in counter.group(1), (
        "a tag-presence precondition makes the counter blind to a RENAMED key, which "
        "is exactly the case that announces a false zero"
    )
    # CONTROL — the blind flag keeps its precondition, so the asymmetry is deliberate
    # rather than the predicate simply having been dropped everywhere.
    assert re.search(r"!blindTrue\s*&&\s*!blindFalse\s*&&\s*!blindNull\s*\n?\s*&&\s*contain\(", body), (
        "the blind flag must still require its key to be present"
    )
    # And it must gate, not merely log: a reply already judged unreadable must not
    # print a count.
    assert "activeMissing > 0" in body
    gate = body.index("AC_ROSTER_ECHO_MISMATCH")
    assert gate < body.index('announce_all("Anti-cheat check at go-live')


def test_a_match_that_ended_mid_request_is_not_logged_as_a_contract_break() -> None:
    """Currency is checked BEFORE the echo gate. The reset zeroes g_acLiveNum, so a
    reply in flight across a teardown would otherwise fail the gate and accuse the API
    of breaking its contract — with an empty match_id — on an ordinary cancel."""
    body = _function_body("stock ac_roster_render(")
    assert body.index("ac_roster_not_current_reason(staleReason") < body.index(
        "AC_ROSTER_ECHO_MISMATCH"
    ), "a stale reply must be discarded before it can look like a broken reply"
    # CONTROL — the measurement is still recorded first, so a discarded reply is not
    # an unmeasured one.
    assert body.index("event=AC_ROSTER_PARSE") < body.index(
        "ac_roster_not_current_reason(staleReason"
    )


def test_the_match_scoped_id_list_dies_with_match_identity() -> None:
    """Teardown exit invariant: a reply that outlives its match must not be matched
    against the previous roster's players."""
    reset = _function_body("stock ac_announce_state_reset(")
    assert "g_acRosterMatchId[0] = EOS" in reset
    assert "g_acLiveNum = 0" in reset
    assert "ac_announce_state_reset()" in _function_body("stock clear_match_id(")


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
    """Tripwire on KTPAntiCheat.Api/Endpoints/AcEndpoints.cs POST /api/ac/live-sessions."""
    assert _define("AC_ROSTER_SID_TAG") == '"steamId":"'
    assert _define("AC_ROSTER_TTL_TAG") == '"ttlSeconds":'
    assert _define("AC_ROSTER_ACTIVE_TAG") == '"active":'
    assert _define("AC_ROSTER_SESSIONS_TAG") == '"sessions":['


def _object_end(body: str, frm: int) -> int:
    """Python mirror of ac_roster_object_end."""
    in_str = False
    depth = 0
    i = frm
    while i < len(body):
        c = body[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            if depth == 0:
                return i
            depth -= 1
        i += 1
    return i


_OBJECTS: list[int] = []


def _parse(body: str) -> list[tuple[str, bool, bool]]:
    """Python mirror of the object walk in ac_roster_render — the algorithm, not proof
    the Pawn runs. What it pins is that bounding on the session OBJECT makes
    attribution independent of the order the API emits its fields in."""
    sid_tag = _define("AC_ROSTER_SID_TAG")
    arr_tag = _define("AC_ROSTER_SESSIONS_TAG")
    a = body.find(arr_tag)
    if a == -1:
        return []
    p = a + len(arr_tag)
    out = []
    while p < len(body) and body[p] != "]":
        if body[p] != "{":
            p += 1
            continue
        _OBJECTS.append(p)
        start = p + 1
        end = _object_end(body, start)
        obj = body[start:end]
        rel = obj.find(sid_tag)
        sid = ""
        if rel != -1:
            at = rel + len(sid_tag)
            sid = obj[at : obj.index('"', at)]
        if sid:
            out.append((sid, '"active":true' in obj, '"captureBlind":true' in obj))
        p = end + 1
    return out


def _match(sent: list[str], rows: list[tuple[str, bool, bool]]):
    """Python mirror of the echo matching: rows are resolved against the ids SENT, by
    exact compare, one entry per id."""
    listed: set[int] = set()
    live, blind, echoed, ordinal_off = [], [], 0, 0
    for row_index, (sid, active, is_blind) in enumerate(rows):
        hit = next(
            (i for i, s in enumerate(sent) if i not in listed and s == sid), None
        )
        if hit is None:
            continue
        echoed += 1
        listed.add(hit)
        if hit != row_index:
            ordinal_off += 1
        if not active:
            continue
        (blind if is_blind else live).append(sent[hit])
    return live, blind, echoed, ordinal_off


_SENT = ["STEAM_0:0:11111111", "STEAM_0:1:22222222", "STEAM_0:0:33333333"]

_SESSIONS = (
    '{"steamId":"STEAM_0:0:11111111","active":true,"clientVersion":"1.4.2",'
    '"lastSeenSecondsAgo":5,"endedGracefully":false,"captureBlind":false},'
    '{"steamId":"STEAM_0:1:22222222","active":true,"clientVersion":"1.4.2",'
    '"lastSeenSecondsAgo":12,"endedGracefully":false,"captureBlind":true},'
    '{"steamId":"STEAM_0:0:33333333","active":false,"clientVersion":null,'
    '"lastSeenSecondsAgo":null,"endedGracefully":null,"captureBlind":null}'
)


def _envelope(sessions: str) -> str:
    """The reply shape, which deliberately carries no serverEndpoint."""
    return '{"ttlSeconds":90,"sessions":[' + sessions + "]}"


def test_the_reply_envelope_under_test_carries_no_endpoint() -> None:
    """The route omits it on purpose: echoing an unverified field is how a caller is
    invited to filter on it again. A fixture that carried one would let a surviving
    plugin-side filter pass these tests."""
    assert "serverEndpoint" not in _envelope(_SESSIONS)


def test_the_object_split_attributes_each_flag_to_its_own_entry() -> None:
    rows = _parse(_envelope(_SESSIONS))
    assert rows == [
        ("STEAM_0:0:11111111", True, False),
        ("STEAM_0:1:22222222", True, True),
        ("STEAM_0:0:33333333", False, False),
    ]

    ttl_tag = _define("AC_ROSTER_TTL_TAG")
    body = _envelope(_SESSIONS)
    at = body.index(ttl_tag) + len(ttl_tag)
    assert body[at : at + 2] == "90", "the TTL advance must land on the first digit"


def test_a_submitted_id_that_is_not_live_is_a_row_and_not_an_absence() -> None:
    """The semantic the route change brings: every id answers, so not-live is a
    reading rather than a missing session."""
    live, blind, echoed, ordinal_off = _match(_SENT, _parse(_envelope(_SESSIONS)))
    assert live == ["STEAM_0:0:11111111"]
    assert blind == ["STEAM_0:1:22222222"]
    assert echoed == 3, "every row echoed an id that was sent"
    assert ordinal_off == 0


def test_a_row_echoing_an_id_nobody_sent_is_attributed_to_nobody() -> None:
    """The failure the echo gate exists for: a reply about another server's players
    must not be read as this server's roster."""
    foreign = _SESSIONS.replace("STEAM_0:1:22222222", "STEAM_0:1:99999999")
    live, blind, echoed, _ = _match(_SENT, _parse(_envelope(foreign)))
    assert echoed == 2, "the foreign row must not match"
    assert "STEAM_0:1:99999999" not in live + blind
    assert echoed != 3, "and the gate on echoed == rows is what refuses the reading"


def test_a_universe_digit_the_api_does_not_fold_reads_as_not_live_here_too() -> None:
    """A known gap, pinned on the API side and inherited deliberately. The plugin must
    not work around it: a fold on this side is a third identity path."""
    unfolded = _SESSIONS.replace('"steamId":"STEAM_0:0:11111111"', '"steamId":"STEAM_2:0:11111111"')
    live, blind, echoed, _ = _match(_SENT, _parse(_envelope(unfolded)))
    assert echoed == 2, "a respelled echo matches nothing sent, by design"
    assert "STEAM_0:0:11111111" not in live + blind
    # CONTROL — asked in its own spelling it resolves, so the miss is the echo compare
    # and not a row that was never parsed.
    sent_in_that_spelling = ["STEAM_2:0:11111111"] + _SENT[1:]
    live2, _, echoed2, _ = _match(sent_in_that_spelling, _parse(_envelope(unfolded)))
    assert echoed2 == 3 and "STEAM_2:0:11111111" in live2


def test_attribution_survives_the_flags_moving_ahead_of_steamId() -> None:
    """The field-order dependency this parse was reworked to remove. With the old
    next-steamId anchor, every session read its neighbour's flag."""
    reordered = (
        '{"captureBlind":false,"active":true,"steamId":"STEAM_0:0:11111111",'
        '"clientVersion":"1.4.2"},'
        '{"captureBlind":true,"active":true,"steamId":"STEAM_0:1:22222222",'
        '"clientVersion":"1.4.2"},'
        '{"captureBlind":null,"active":false,"steamId":"STEAM_0:0:33333333",'
        '"clientVersion":null}'
    )
    live, blind, echoed, _ = _match(_SENT, _parse(_envelope(reordered)))
    assert live == ["STEAM_0:0:11111111"]
    assert blind == ["STEAM_0:1:22222222"]
    assert echoed == 3


def test_a_brace_inside_clientVersion_cannot_end_the_object_early() -> None:
    """JSON escapes a quote inside a string, never a brace, and clientVersion is
    client-supplied."""
    hostile = (
        '{"steamId":"STEAM_0:0:11111111","active":true,"clientVersion":"1.4.2}{",'
        '"lastSeenSecondsAgo":5,"captureBlind":true}'
    )
    assert _parse(_envelope(hostile)) == [("STEAM_0:0:11111111", True, True)]


def test_an_escaped_quote_inside_clientVersion_does_not_desync_the_scan() -> None:
    hostile = (
        '{"steamId":"STEAM_0:0:11111111","active":true,"clientVersion":"1.4\\"2}",'
        '"lastSeenSecondsAgo":5,"captureBlind":true},'
        '{"steamId":"STEAM_0:1:22222222","active":true,"clientVersion":"ok",'
        '"lastSeenSecondsAgo":5,"captureBlind":false}'
    )
    assert _parse(_envelope(hostile)) == [
        ("STEAM_0:0:11111111", True, True),
        ("STEAM_0:1:22222222", True, False),
    ]


def test_a_blind_flag_that_stops_matching_is_counted_not_silently_cleared() -> None:
    """blind=0 must mean nobody is blind, not 'the wire spelling moved'. Unlike the
    other markers this one fails reassuringly, so it needs its own counter."""
    body = _function_body("stock ac_roster_render(")
    assert '^"captureBlind^":false' in body, "the false literal is the control"
    assert "blindUnparsed++" in body
    assert re.search(
        r"if\s*\(\s*!blindTrue\s*&&\s*!blindFalse\s*&&\s*!blindNull", body
    ), "the counter must fire only when NO literal matched"
    assert "AC_ROSTER_BLIND_UNPARSED" in _log_events(body)


def test_a_null_blind_flag_is_a_spelling_and_not_a_moved_key() -> None:
    """The control inverts without this. captureBlind is nullable on this route and is
    null for every submitted id with no session, so a reading where somebody is not
    running the client would report a wire change that did not happen -- on a route
    whose whole point is that such a row is now the ordinary case."""
    body = _function_body("stock ac_roster_render(")
    assert '^"captureBlind^":null' in body, (
        "null must be recognised, or the blind control fires on an ordinary reading"
    )
    assert "blindNull" in body

    # The field really is nullable in the fixture, so this is not a hypothetical.
    assert '"captureBlind":null' in _SESSIONS

    # And liveness deliberately has NO null branch: active is not nullable there, so a
    # null would be the contract change its control exists to catch.
    assert '^"active^":null' not in body
    assert not re.search(r"!activeTrue\s*&&\s*!activeFalse\s*&&\s*!activeNull", body)


def test_the_chat_lists_are_capped_so_a_report_cannot_overflow_a_client() -> None:
    """client_print(0, ...) is one RELIABLE per-client usermsg per line, and a
    reliable overflow drops the player. A report must not be able to kick anyone."""
    cap = re.search(r"#define\s+AC_ROSTER_MAX_LINES\s+(\d+)", SOURCE)
    assert cap, "#define AC_ROSTER_MAX_LINES not found"
    assert 1 <= int(cap.group(1)) <= 3, (
        f"a cap of {cap.group(1)} lines per list does not bound the go-live frame"
    )
    body = _function_body("stock ac_roster_announce_names(")
    assert "AC_ROSTER_MAX_LINES" in body
    assert "more)" in body, "the remainder must be counted, not dropped silently"


def test_the_capped_line_still_fits_the_dod_chat_width() -> None:
    """The binding cap is 190 in UTIL_ClientPrint, which truncates with no strlen
    check -- not announce_all's 192."""
    body = _function_body("stock ac_roster_announce_names(")
    wrap = re.search(r"idx\s*\+\s*strlen\(name\)\s*\+\s*2\s*>\s*(\d+)", body)
    assert wrap, "the wrap threshold is not where this test thinks it is"
    threshold = int(wrap.group(1))

    labels = re.findall(r'ac_roster_announce_names\(\s*"([^"]+)"', SOURCE)
    longest_label = max(len(x) for x in labels)
    suffix = len(" (+99 more)")
    prefix = len("[KTP] ") + longest_label + len(" ") + len("\n")
    assert threshold + suffix + prefix <= 190, (
        f"worst-case line is {threshold + suffix + prefix} against the 190-char cap"
    )

    line = re.search(r"new line\[(\d+)\]", body)
    assert line and threshold + suffix < int(line.group(1)), "the line buffer can truncate"


# --------------------------------------------------------------- identity rules

def test_the_blind_flag_is_bounded_to_the_session_OBJECT_not_to_field_order() -> None:
    """Anchoring on the NEXT steamId made attribution depend on the API emitting
    captureBlind after it, which JSON does not promise: moving that field would name
    one player capture blind because his neighbour was."""
    body = _function_body("stock ac_roster_render(")
    assert "ac_roster_object_end(objStart)" in body
    assert "g_acRosterBody[objEnd] = EOS" in body
    assert "g_acRosterBody[objEnd] = saved" in body, "the body must be restored in place"
    assert "boundAt" not in body, (
        "the next-steamId anchor is the field-order dependency; it must be gone"
    )
    # Every read is taken from the terminated object, so none can see a sibling.
    assert body.count("contain(g_acRosterBody[objStart]") >= 5


def test_the_object_scan_is_string_aware() -> None:
    """JSON escapes a quote inside a string but not a brace, and clientVersion is
    client-supplied, so a naive brace scan ends the object early."""
    body = _function_body("stock ac_roster_object_end(")
    # The predicate text, not just the name: gutting the branch to `if (false)`
    # leaves every `inStr` mention in place and disables the tracking.
    assert "if (inStr) {" in body
    assert "inStr = true" in body and "inStr = false" in body
    assert body.index("if (inStr) {") < body.index("c == '}'"), (
        "the brace test must sit in the else of the string test, or a brace inside "
        "a string ends the object"
    )
    assert r"c == '\'" in body, (
        "the backslash case must be handled or an escaped quote ends the string early"
    )
    assert "c == '}'" in body and "c == '\"'" in body


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

    reason = _function_body("stock bool:ac_roster_not_current_reason(")
    assert "g_matchLive" in reason
    assert "equal(g_matchId, g_acRosterMatchId)" in reason, (
        "the compare against the live id is what actually stops a stale answer"
    )
    for cause in ("match_not_live", "no_match_id", "no_pending_id", "match_changed"):
        assert cause in reason, f"{cause} is not told apart in the log"


def test_test_mode_takes_no_outbound_reading() -> None:
    body = _function_body("stock send_ac_roster_report(")
    suppressed = body.index("TESTMATCH_OUTBOUND_SUPPRESSED")
    assert suppressed < body.index("curl_easy_init()")
    assert suppressed < body.index("g_acRosterMatchId")
    assert suppressed < body.index("g_acLiveIds"), (
        "test mode must not even build the id list"
    )


def test_objects_walked_is_counted_separately_from_ids_read() -> None:
    """rows=0 with objects>0 is the id key moving on the wire. Counting only the ids
    read makes that case print every marker green beside a zero."""
    body = _function_body("stock ac_roster_render(")
    assert re.search(r"if\s*\(\s*g_acRosterBody\[p\]\s*!=\s*'\{'\s*\)\s*\{\s*p\+\+;\s*continue;\s*\}\s*objects\+\+;", body), (
        "objects must be counted for every object walked, before any id parse"
    )
    assert body.index("objects++;") < body.index("if (!sid[0]) continue;"), (
        "a skipped id must still have counted its object"
    )
    assert re.search(r"if\s*\(\s*objects\s*>\s*0\s*&&\s*rows\s*==\s*0\s*\)", body)
    assert "AC_ROSTER_NO_IDS" in _log_events(body)


def test_a_renamed_id_key_is_distinguishable_from_an_empty_roster() -> None:
    """The mirror: the objects are still walked, so the counts disagree."""
    wire = _SESSIONS.replace('"steamId"', '"steam_id"')
    _OBJECTS.clear()
    read = _parse(_envelope(wire))
    assert read == [], "a respelled key must yield no ids"
    assert len(_OBJECTS) == 3, "and must still count three objects walked"


def test_a_nested_object_does_not_close_the_session_window_early() -> None:
    """The window is depth-bounded, so a field added after a nested object is still
    inside it — including the flags, whose controls cannot fire on a key that fell
    outside the window rather than failing to match."""
    body = _function_body("stock ac_roster_object_end(")
    assert "depth++" in body and re.search(r"if\s*\(\s*!depth\s*\)\s*return i;", body), (
        "the closing brace must only end the object at depth zero"
    )
    wire = (
        '{"steamId":"STEAM_0:0:11111111","capture":{"mode":"off"},"active":true,'
        '"captureBlind":true}'
    )
    _OBJECTS.clear()
    assert _parse(_envelope(wire)) == [("STEAM_0:0:11111111", True, True)]


def test_a_missing_sessions_array_is_not_scanned_from_zero() -> None:
    """A scan from zero finds the ROOT brace, so the first window is the envelope and
    the parse is wrong rather than empty. The gate above makes this unreachable; a
    fallback that would be wrong is worse than none."""
    body = _function_body("stock ac_roster_render(")
    assert "? 0 :" not in body, "no fallback may start the walk at the body root"
    assert re.search(
        r"if\s*\(\s*p\s*==\s*-1\s*\)\s*\{\s*ac_roster_announce_unavailable\(\);\s*return;\s*\}",
        body,
    ), "an absent array must take the same fail-open path as the marker gate"


def test_no_roster_helper_is_defined_and_never_called() -> None:
    """amxxpc does not warn on an unused stock, so a dead predicate compiles clean and
    reads as the canonical one the next caller should reach for."""
    src = _strip_comments(SOURCE)
    for name in set(re.findall(r"^stock (?:bool:)?(ac_roster_\w+)\(", src, re.M)):
        assert len(re.findall(name + r"\(", src)) > 1, f"{name} is never called"
