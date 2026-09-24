"""Source-contract tests for anti-cheat announce diagnostics and re-announce.

The match announce was one POST per half at a 3s timeout with no retry and no
latch, and the callback it shared with every other AC call logged neither the
endpoint nor the match id.  A lost announce therefore left no ktp_ac_match_index
row *and* no log line naming what went missing, so the loss was only ever
visible months later as sessions that linked to a neighbouring match or to
nothing.

These tests pin the two halves of the fix that source can prove without a live
match: every announce outcome names the match and the endpoint, and the retry is
bounded, latched on success, and cleared when match identity is dropped.
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


def _log_calls(body: str) -> list[str]:
    """The log_ktp format strings emitted by a function body."""
    return re.findall(r'log_ktp\(\s*"((?:\^"|[^"\n])*)"', body)


# --------------------------------------------------------------- diagnostics

def test_announce_uses_a_dedicated_callback() -> None:
    """The shared ac_callback cannot name a match, so the announce must not use it."""
    body = _function_body("stock send_ac_match_announce(")
    perform = re.search(r'curl_easy_perform\(\s*curl\s*,\s*"([^"]+)"\s*\)', body)
    assert perform, "send_ac_match_announce must still perform the transfer"
    assert perform.group(1) == "ac_announce_callback", (
        f"announce performs via {perform.group(1)!r}; a shared callback cannot "
        "attribute a failure to a match"
    )
    assert "public ac_announce_callback(CURL:curl, CURLcode:code)" in SOURCE


def test_shared_callback_is_still_used_by_the_other_ac_posts() -> None:
    """Negative control: splitting the announce out must not orphan ac_callback."""
    assert 'curl_easy_perform(curl, "ac_callback")' in SOURCE
    assert "public ac_callback(CURL:curl, CURLcode:code)" in SOURCE


def test_every_announce_outcome_names_the_match_and_the_endpoint() -> None:
    """Both failure modes and the success path, or the log still cannot be correlated."""
    lines = _log_calls(_function_body("public ac_announce_callback("))
    assert len(lines) >= 3, f"expected curl-error, http-error and ok lines; got {lines}"
    for fmt in lines:
        assert "match_id=%s" in fmt, f"log line without a match id: {fmt!r}"
        assert "endpoint=%s" in fmt, f"log line without an endpoint: {fmt!r}"

    events = {re.search(r"event=(\S+)", fmt).group(1) for fmt in lines}
    assert "AC_ANNOUNCE_FAILED" in events
    assert "AC_ANNOUNCE_OK" in events


def test_curl_init_failure_on_the_announce_also_names_the_match() -> None:
    """The init-failure path never reaches the callback, so it needs its own id."""
    body = _function_body("stock send_ac_match_announce(")
    init_fail = [fmt for fmt in _log_calls(body) if "curl_init_failed" in fmt]
    assert init_fail, "send_ac_match_announce must still log a failed curl_easy_init"
    for fmt in init_fail:
        assert "match_id=%s" in fmt and "endpoint=%s" in fmt


# --------------------------------------------------------------- re-announce

def test_latch_is_set_only_on_a_2xx() -> None:
    body = _function_body("public ac_announce_callback(")
    assert re.search(r"httpCode\s*>=\s*200\s*&&\s*httpCode\s*<\s*300", body)
    sets = re.findall(r"g_acAnnounceConfirmed\s*=\s*(\w+)", body)
    assert sets == ["true"], (
        f"callback assigns the latch {sets}; only a success may set it, and "
        "nothing in the callback may clear it"
    )
    assert re.search(r"if\s*\(\s*ok\s*\)\s*g_acAnnounceConfirmed\s*=\s*true", body)


def test_reannounce_rides_the_existing_flush_task() -> None:
    """No private timer: the 30s flush task is the carrier, and it runs first."""
    body = _function_body("public task_flush_weapon_timeline(")
    assert "ac_announce_reannounce_if_unconfirmed()" in body
    assert body.index("ac_announce_reannounce_if_unconfirmed()") < body.index(
        "send_ac_weapon_timeline_batch()"
    ), "the announce must be re-sent before the batches that depend on its match_id"


def test_reannounce_is_guarded_latched_and_bounded() -> None:
    body = _function_body("stock ac_announce_reannounce_if_unconfirmed(")
    assert "g_acAnnounceConfirmed" in body, "a confirmed announce must not be re-sent"
    assert "g_acAnnounceMatchId[0]" in body, "an idle plugin must not POST"
    assert re.search(r"equal\(\s*g_matchId\s*,\s*g_acAnnounceMatchId\s*\)", body), (
        "a pending id from a finished match must not be re-announced"
    )
    assert re.search(
        r"g_acAnnounceAttempts\s*>=\s*AC_ANNOUNCE_MAX_ATTEMPTS", body
    ), "the retry budget must be bounded"
    assert "AC_ANNOUNCE_GIVEUP" in body, "exhausting the budget must leave a record"

    cap = re.search(r"#define\s+AC_ANNOUNCE_MAX_ATTEMPTS\s+(\d+)", SOURCE)
    assert cap, "#define AC_ANNOUNCE_MAX_ATTEMPTS not found"
    assert int(cap.group(1)) >= 10, (
        "the measured loss clusters on whole evenings; a handful of 30s attempts "
        "expires before the outage does"
    )


def test_a_new_match_id_restarts_the_budget_but_a_new_half_does_not() -> None:
    body = _function_body("stock send_ac_match_announce(")
    assert re.search(
        r"if\s*\(\s*!equal\(\s*g_acAnnounceMatchId\s*,\s*matchId\s*\)\s*\)", body
    ), "the attempt counter must reset on a different match id, and only then"
    assert "g_acAnnounceAttempts++" in body


def test_announce_state_is_dropped_with_match_identity() -> None:
    """clear_match_id is the single teardown funnel; the latch must not outlive it."""
    body = _function_body("stock clear_match_id(")
    assert "ac_announce_state_reset()" in body

    reset = _function_body("stock ac_announce_state_reset(")
    assert "g_acAnnounceMatchId[0] = EOS" in reset
    assert "g_acAnnounceAttempts = 0" in reset
    assert "g_acAnnounceConfirmed = false" in reset


def test_test_mode_never_arms_the_retry() -> None:
    """The suppression return has to precede every write to the announce state."""
    body = _function_body("stock send_ac_match_announce(")
    suppressed = body.index("TESTMATCH_OUTBOUND_SUPPRESSED")
    first_state_write = min(
        body.index(token)
        for token in ("g_acAnnounceMatchId", "g_acAnnounceAttempts", "g_acAnnounceConfirmed")
    )
    assert suppressed < first_state_write, (
        "a contained .testmatch would otherwise leave a pending announce that the "
        "flush task keeps re-POSTing"
    )
    assert "ac_announce_state_reset()" in _function_body("stock ktp_reset_test_ac_state(")
