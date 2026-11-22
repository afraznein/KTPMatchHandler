"""The AC auto-start arm and the private ready-up nudge.

Three properties matter, and each is easy to lose in a later edit.

It is a REPORT. The arm and the nudge read run through pre-start and pending, the
window in which a refusal would hold a match hostage, so nothing in them may touch
match state or act on a reply.

It arms official matches only. `.scrim`, `.12man`, `.draft` and `.draftOT` take no
password, so an arm on one would let anyone start recording on every signed-in
client on the server.

The nudge is private. Naming who is not running the client in open chat is
accusation-adjacent; the 2026-11-21 ruling allows one line to that player alone.

The beat itself (ac_arm_tick and the episode entry points) is run through
_pawn_sim with the looping helpers stubbed; everything else is a source contract.
"""
from __future__ import annotations

import re

import pytest

from ._pawn_sim import SYSTIME_BASE, Sim, Source
from .conftest import REPO_ROOT

SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")


def _function_body(signature_prefix: str) -> str:
    start = SOURCE.index(signature_prefix)
    end = SOURCE.index("\n}", start)
    return SOURCE[start:end]


def _strip_comments(body: str) -> str:
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return re.sub(r"//.*", "", body)


def _region(start_marker: str, last_function: str) -> str:
    start = SOURCE.index(start_marker)
    end = SOURCE.index("\n}", SOURCE.index(last_function, start))
    return SOURCE[start:end]


def _arm_region() -> str:
    return _region("// ================= AC auto-start arm (official matches)",
                   "public ac_arm_callback(")


def _nudge_region() -> str:
    return _region("// ================= Ready-up nudge (official matches)",
                   "stock ac_nudge_render(")


# ------------------------------------------------------------- it reports only

@pytest.mark.parametrize("region", [_arm_region, _nudge_region])
def test_nothing_in_the_arm_or_the_nudge_can_change_a_match(region) -> None:
    code = _strip_comments(region())
    for forbidden in (
        "g_matchLive =", "g_matchPending =", "g_preStartPending =", "g_ready[",
        "PLUGIN_HANDLED", "server_cmd", "kick", "set_task", "enter_pending_phase",
        "register_cvar", "create_cvar",
    ):
        assert forbidden not in code, f"{forbidden!r} in a report-only path"
    # CONTROL: the region is the feature and really was searched.
    assert code.count("g_acArm") > 5 or code.count("g_acNudge") > 5


def test_the_arm_callback_only_logs() -> None:
    body = _strip_comments(_function_body("public ac_arm_callback("))
    assert set(re.findall(r"event=(\w+)", body)) == {"AC_ARM_FAILED", "AC_ARM_OK", "AC_ARM_REFUSED"}
    assert body.count("curl_easy_cleanup(curl)") == 1
    assert "g_acArmActive" not in body and "g_acArmLastSent" not in body, (
        "the reply must not steer the beat or the episode"
    )


# ------------------------------------------------------------- official only

@pytest.mark.parametrize("fn", [
    "stock ac_arm_on_prestart(", "stock ac_arm_on_pending(", "stock ac_arm_on_live(",
    "stock ac_arm_tick(", "stock ac_nudge_read(",
])
def test_every_entry_point_rechecks_the_official_predicate(fn) -> None:
    assert "is_official_match_type(g_matchType)" in _function_body(fn)


def test_the_arm_opens_at_the_password_accept_not_before_it() -> None:
    body = _function_body("stock match_start_with_args(")
    at = body.index("ac_arm_on_prestart();")
    assert body.index('"[KTP] Invalid match password."') < at, "arming before the password check"
    assert body.index("g_preStartPending = true;") < at
    assert at < body.index('set_task(1.0, "prestart_hud_tick"')


def test_every_pending_entry_and_the_go_live_reach_the_arm() -> None:
    assert "ac_arm_on_pending();" in _function_body("stock enter_pending_phase(")
    assert _function_body("stock restore_match_context_from_localinfo(").count(
        "ac_arm_on_pending();") == 2, "the 2nd-half and the OT restore each open a phase"
    live = _function_body("public task_deferred_discord_fwd(")
    assert live.index("send_ac_roster_report(g_matchId)") < live.index("ac_arm_on_live();")
    for tick in ("public prestart_hud_tick(", "public pending_hud_tick("):
        assert "ac_arm_tick();" in _function_body(tick)


def test_the_episode_latch_is_cleared_on_every_identity_clear() -> None:
    assert "ac_arm_state_reset();" in _function_body("stock ac_announce_state_reset(")
    assert "ac_arm_state_reset();" in _function_body("public plugin_init(")
    cancel = _function_body("public cmd_cancel(")
    pre = cancel[cancel.index("if (g_preStartPending)"):cancel.index("PRESTART_CANCEL")]
    assert "ac_arm_state_reset();" in pre, "a cancelled pre-start has no match id to clear"


# ------------------------------------------------------------- the request

def test_the_arm_request_matches_the_announce_transport() -> None:
    body = _function_body("stock ac_arm_send(")
    assert "/api/ac/arm" in body
    assert "CURLOPT_HTTPHEADER, g_acCurlHeaders" in body, "same secret headers as the announce"
    assert "CURLOPT_COPYPOSTFIELDS, g_acArmBody" in body
    assert "CURLOPT_TIMEOUT, 3" in body
    for key in ("serverEndpoint", "matchType", "phase", "nonce", "steamIds"):
        assert f'^"{key}^"' in body, f"{key} missing from the arm body"


def test_the_arm_body_budget_is_its_own_literal() -> None:
    body = _function_body("stock ac_arm_send(")
    fmt = re.search(r'formatex\(g_acArmBody, charsmax\(g_acArmBody\),\s*"((?:\^.|[^"^])*)"', body).group(1)
    literal = re.sub(r"\^.", "x", fmt.replace("%s", "")) + "]}"
    declared = int(re.search(r"^#define AC_ARM_LITERAL_BYTES (\d+)", SOURCE, re.M).group(1))
    assert len(literal) == declared
    formula = re.search(r"^#define AC_ARM_BODY_MAX (.+)$", SOURCE, re.M).group(1)
    assert "AC_ARM_MAX_IDS * AC_LIVE_ROW_MAX" in formula
    assert int(re.search(r"^#define AC_ARM_MAX_IDS (\d+)", SOURCE, re.M).group(1)) <= 32


def test_a_testmatch_suppresses_both_outbound_calls() -> None:
    for fn, sink in (("stock ac_arm_send(", "sink=ac_arm"), ("stock ac_nudge_read(", "sink=ac_nudge")):
        body = _function_body(fn)
        block = body[body.index("#if defined KTP_TEST_MODE"):body.index("#endif")]
        assert "g_testMatchActive" in block and sink in block and "return;" in block
        assert body.index("#endif") < body.index("curl_easy_init()")


def test_the_ids_armed_come_from_this_servers_own_slots() -> None:
    body = _function_body("stock ac_arm_collect(")
    assert "get_match_participants(players, pnum)" in body
    assert "get_user_team(players[i])" in body
    assert 'contain(sid, ":") == -1' in body
    assert "g_acArmNum < AC_ARM_MAX_IDS" in body


# ------------------------------------------------------------- the nudge

def test_the_nudge_never_reaches_public_chat() -> None:
    code = _strip_comments(_nudge_region())
    assert "announce_all" not in code
    assert "client_print(0" not in code
    assert "ac_roster_tell_admins" not in code and "ac_roster_announce_names" not in code
    prints = re.findall(r"client_print\((\w+),", code)
    assert prints == ["slot"], f"the nudge must print to the one player only, got {prints}"
    line = re.search(r'client_print\(slot, print_chat, "([^"]*)"\)', code).group(1)
    assert "%" not in line, "the line must carry nobody's name"


def test_the_nudge_is_once_per_player_per_pending_phase() -> None:
    assert "g_acNudgedNum = 0;" in _function_body("stock ac_arm_on_pending(")
    render = _function_body("stock ac_nudge_render(")
    say = render.index("client_print(slot")
    assert render.index("if (ac_nudge_already(nowSid)) continue;") < say
    assert render.index("g_acNudgedNum >= AC_NUDGE_MEMO_MAX") < say
    assert render.index("copy(g_acNudged[g_acNudgedNum]") < say
    assert "ac_nudge_already(g_acArmIds[i])" in _function_body("stock ac_nudge_read(")


def test_a_reply_that_fails_the_gate_nudges_nobody() -> None:
    render = _function_body("stock ac_nudge_render(")
    say = render.index("client_print(slot")
    for gate in (
        "!equal(g_acNudgeAskNonce, g_acArmNonce)",
        "p == -1 || ttl <= 0",
        "rows != g_acNudgeAskNum || echoed != rows || activeMissing > 0",
    ):
        at = render.index(gate)
        assert at < say
        assert render.index("return;", at) < say, f"{gate!r} must return before anyone is told"
    assert "get_user_authid(slot, nowSid" in render, "a slot is not an identity"
    assert render.index("get_user_authid(slot, nowSid") < say


def test_the_nudge_asks_the_id_scoped_route_and_never_by_endpoint() -> None:
    code = _strip_comments(_nudge_region())
    assert "/api/ac/live-sessions" in code
    assert "endpoint" not in code.lower()


# ------------------------------------------------------------- the beat, run

class ArmSim(Sim):
    """Runs the beat and the episode entry points; the looping helpers are stubbed."""

    def __init__(self, source):
        super().__init__(source)
        self.roster = ["STEAM_0:0:1", "STEAM_0:1:2"]
        self.sends = []      # (now, phase, reason, nonce)
        self.nudges = []     # (now, nonce)
        self.minted = 0
        self.g.update(g_matchType="ktp", g_preStartPending=False, g_matchPending=False)
        self.stubs = {
            "is_official_match_type": lambda t: t in ("ktp", "ktpot"),
            "equal": lambda a, b: a == b,
            "ac_arm_current_phase": lambda out, n: bool(self.g["g_preStartPending"] or self.g["g_matchPending"]),
            "ac_arm_collect": self._collect,
            "ac_arm_send": self._send,
            "ac_nudge_read": lambda: self.nudges.append((self.now, self.g["g_acArmNonce"])),
            "ac_arm_mint_nonce": self._mint,
            "ac_arm_state_reset": self._reset,
        }

    def call(self, name, args):
        if name in self.stubs:
            return self.stubs[name](*args)
        return super().call(name, args)

    def native(self, name, args):
        if name == "charsmax":
            return 0
        return super().native(name, args)

    def _collect(self):
        self.g["g_acArmNum"] = len(self.roster)
        return hash(frozenset(self.roster)) & 0x7FFFFFFF

    def _send(self, phase, reason):
        # Mirrors the stamp at the head of ac_arm_send; test_the_send_stamps_first holds it.
        sig = self._collect()
        self.g.update(g_acArmLastSent=SYSTIME_BASE + int(self.now), g_acArmSig=sig,
                      g_acArmSigNum=self.g["g_acArmNum"])
        state = "prestart" if self.g["g_preStartPending"] else "pending" if self.g["g_matchPending"] else "live"
        self.sends.append((self.now, state, reason, self.g["g_acArmNonce"]))

    def _mint(self):
        self.minted += 1
        self.g["g_acArmNonce"] = f"n{self.minted}"

    def _reset(self):
        self.g.update(g_acArmActive=False, g_acArmNonce="", g_acArmPhase="", g_acArmLastSent=0,
                      g_acArmSig=0, g_acArmSigNum=-1, g_acArmNum=0, g_acNudgedNum=0)

    def tick_until(self, end):
        t = int(self.now) + 1
        while t <= end:
            self.now = float(t)
            self.call("ac_arm_tick", [])
            t += 1

    def reasons(self):
        return [(int(t), phase, reason, nonce) for t, phase, reason, nonce in self.sends]


@pytest.fixture(scope="module")
def source():
    return Source()


def test_the_send_stamps_first(source) -> None:
    body = _function_body("stock ac_arm_send(")
    head = body[: body.index("#if defined KTP_TEST_MODE")]
    for stamp in ("new sig = ac_arm_collect();", "g_acArmLastSent = get_systime();",
                  "g_acArmSig = sig;", "g_acArmSigNum = g_acArmNum;"):
        assert stamp in head, f"{stamp!r} must run before any early return"


def test_a_ktp_arms_at_accept_beats_every_30s_and_keeps_its_nonce_into_pending(source) -> None:
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    sim.tick_until(160)
    assert sim.reasons() == [
        (100, "prestart", "ktp_accept", "n1"),
        (130, "prestart", "interval", "n1"),
        (160, "prestart", "interval", "n1"),
    ]

    sim.now = 170.0
    sim.g.update(g_preStartPending=False, g_matchPending=True)
    sim.call("ac_arm_on_pending", [])
    assert sim.sends[-1][1:] == ("pending", "pending_entry", "n1"), "the pre-start's nonce carries"
    assert sim.nudges == [(170.0, "n1")]

    sim.tick_until(200)
    assert sim.sends[-1] == (200.0, "pending", "interval", "n1")
    assert sim.nudges[-1] == (200.0, "n1")

    sim.now = 205.0
    sim.g.update(g_matchPending=False, g_matchLive=True)
    sim.call("ac_arm_on_live", [])
    assert sim.sends[-1] == (205.0, "live", "go_live", "n1")
    count = len(sim.sends)
    sim.tick_until(400)
    assert len(sim.sends) == count, "the beat stops at go-live; the arm lapses on its TTL"


def test_a_roster_change_resends_after_the_debounce_and_not_before(source) -> None:
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    sim.tick_until(101)
    sim.roster.append("STEAM_0:0:3")
    sim.tick_until(104)
    assert len(sim.sends) == 1, "inside the debounce"
    sim.tick_until(105)
    assert sim.reasons()[-1] == (105, "prestart", "roster_change", "n1")
    sim.tick_until(134)
    assert len(sim.sends) == 2, "no change, no send until the interval"
    sim.tick_until(135)
    assert sim.reasons()[-1] == (135, "prestart", "interval", "n1")


def test_a_continuation_pending_gets_a_fresh_nonce_and_a_restore_starts_clean(source) -> None:
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    sim.g.update(g_preStartPending=False, g_matchPending=True)
    sim.call("ac_arm_on_pending", [])
    sim.g.update(g_matchPending=False)
    sim.call("ac_arm_on_live", [])
    assert {s[3] for s in sim.sends} == {"n1"}

    # Map change to the 2nd half: plugin_init resets, the restore opens a pending phase.
    sim.call("ac_arm_state_reset", [])
    sim.now = 2000.0
    sim.g["g_matchPending"] = True
    sim.call("ac_arm_on_pending", [])
    assert sim.sends[-1][1:] == ("pending", "pending_entry", "n2")

    # And an OT round after a live 2nd half, without a reset in between, still re-mints.
    sim.g["g_matchPending"] = False
    sim.call("ac_arm_on_live", [])
    sim.g["g_matchPending"] = True
    sim.call("ac_arm_on_pending", [])
    assert sim.sends[-1][3] == "n3"


@pytest.mark.parametrize("match_type", ["scrim", "12man", "draft", "draftot"])
def test_an_unofficial_match_never_arms(source, match_type) -> None:
    sim = ArmSim(source)
    sim.g["g_matchType"] = match_type
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    sim.tick_until(140)
    sim.g.update(g_preStartPending=False, g_matchPending=True)
    sim.call("ac_arm_on_pending", [])
    sim.tick_until(200)
    sim.call("ac_arm_on_live", [])
    assert sim.sends == [] and sim.nudges == []


def test_a_stale_ktp_episode_cannot_arm_a_scrim(source) -> None:
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    assert len(sim.sends) == 1
    # Cancelled without a reset reaching it; then a scrim runs on the same server.
    sim.g.update(g_preStartPending=False, g_matchType="scrim", g_matchPending=True)
    sim.call("ac_arm_on_pending", [])
    sim.tick_until(300)
    assert len(sim.sends) == 1
    assert sim.g["g_acArmActive"] is False


def test_a_clock_that_moved_back_is_due_not_deferred(source) -> None:
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_preStartPending"] = True
    sim.call("ac_arm_on_prestart", [])
    sim.g["g_acArmLastSent"] = SYSTIME_BASE + 10_000
    sim.tick_until(101)
    assert sim.reasons()[-1] == (101, "prestart", "interval", "n1")


def test_a_roster_change_in_pending_arms_but_does_not_read_for_the_nudge(source) -> None:
    """A joiner was armed that instant and could not have started yet; reading him then
    would spend his one nudge on a false 'no session'."""
    sim = ArmSim(source)
    sim.now = 100.0
    sim.g["g_matchPending"] = True
    sim.call("ac_arm_on_pending", [])
    assert sim.nudges == [(100.0, "n1")]
    sim.roster.append("STEAM_0:0:9")
    sim.tick_until(110)
    assert sim.reasons()[-1] == (105, "pending", "roster_change", "n1")
    assert sim.nudges == [(100.0, "n1")]
    sim.tick_until(135)
    assert sim.reasons()[-1] == (135, "pending", "interval", "n1")
    assert sim.nudges[-1] == (135.0, "n1")


def test_the_nudge_skips_ids_armed_too_recently_to_have_started() -> None:
    read = _function_body("stock ac_nudge_read(")
    assert "ac_arm_seen_for(g_acArmIds[i], now)" in read
    assert "armedFor < AC_NUDGE_ARM_GRACE" in read
    assert read.index("armedFor < AC_NUDGE_ARM_GRACE") < read.index("copy(g_acNudgeAskIds")
    assert re.search(r"^#define AC_NUDGE_ARM_GRACE AC_ARM_INTERVAL", SOURCE, re.M)
    send = _function_body("stock ac_arm_send(")
    assert send.index('curl_easy_perform(curl, "ac_arm_callback"') < send.index("ac_arm_mark_seen(")
    assert "g_acArmSeenNum = 0;" in _function_body("stock ac_arm_mint_nonce(")
    assert "g_acArmSeenNum = 0;" in _function_body("stock ac_arm_state_reset(")


def test_a_reply_to_an_older_read_is_discarded() -> None:
    read = _function_body("stock ac_nudge_read(")
    assert "g_acNudgeSeq++;" in read
    assert 'curl_easy_perform(curl, "ac_nudge_callback", seq, sizeof(seq))' in read
    cb = _function_body("public ac_nudge_callback(")
    gate = cb.index("data[0] != g_acNudgeSeq")
    assert gate < cb.index("curl_get_response_body")
    assert cb.index("return;", gate) < cb.index("curl_get_response_body")
    arm = _function_body("public ac_arm_callback(")
    assert "copy(nonce, charsmax(nonce), data)" in arm
    assert "g_acArmNonce" not in arm, "log the nonce the request carried, not the current one"


def test_the_nudge_refuses_a_truncated_reply() -> None:
    render = _function_body("stock ac_nudge_render(")
    assert render.index("bytes >= AC_ROSTER_BODY_SIZE - 1") < render.index("client_print(slot")


def test_the_test_mode_setters_close_the_episode() -> None:
    for fn in ("public cmd_test_setup_match(", "public cmd_test_reset("):
        assert "ac_arm_state_reset();" in _function_body(fn)
