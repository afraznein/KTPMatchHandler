"""`.restarthalf` leaves its clan countdown the way a half start does.

The restart re-runs the mp_clan_timer countdown mid-half, with the match id still
set and HLStatsX's match context still open. _pawn_sim runs execute_restart_half,
its deferred stats task, evt_RoundState and the go-live fallback out of
KTPMatchHandler.sma. Timings follow the bot stack at mp_clan_timer 10: the clan
restart's RoundState=0 lands 10s after the trigger and its RoundState=1 5s later.
"""
from __future__ import annotations

import re

import pytest

from ._pawn_sim import Sim, Source

T = 300.0
H2_START = 'KTP_MATCH_START (matchid "KTP-TEST-1") (map "dod_test") (half "2nd half") (type "1")'


@pytest.fixture(scope="module")
def source():
    return Source()


def _restarted(source, clan_timer=10.0):
    """A live 2nd half whose HLStatsX context is open, then .restarthalf at T."""
    sim = Sim(source, clan_timer=clan_timer)
    sim.g.update(g_matchLive=True, g_currentHalf=2, g_roundLive=True,
                 g_firstHalfScore=[0, 3, 1], g_matchScore=[0, 5, 4])
    sim.hl_log.append((50.0, H2_START))
    sim.advance(T)
    assert not sim.paused and sim.daemon_round_live() == 1
    sim.since = T
    sim.call("execute_restart_half", [1, "admin", "STEAM_0:0:1", "127.0.0.1"])
    return sim


def test_countdown_kills_are_not_counted_and_the_half_goes_live_on_the_round(source):
    sim = _restarted(source)
    assert sim.paused, "stats still collecting at the restart trigger"
    sim.advance(T + 0.2)
    assert sim.daemon_round_live() == 0, "HLStatsX still tagging kills after the restart"

    # The interrupted round plays on through the countdown, and wins and resets.
    for at, state in ((T + 2.0, 4), (T + 6.0, 0), (T + 8.0, 1)):
        sim.round_state(at, state)
        assert sim.paused, f"stats resumed on countdown RoundState={state}"
        assert sim.daemon_round_live() == 0
    assert sim.hl("KTP_MATCH_START") == []

    sim.round_state(T + 10.0, 0)      # the clan restart
    assert sim.paused
    sim.round_state(T + 15.0, 1)      # the restarted half's first round
    assert not sim.paused
    assert sim.hl("KTP_MATCH_START") == [T + 15.0]
    assert sim.hl_log[-1][1] == H2_START
    assert sim.daemon_round_live() == 1
    assert [c[0] for c in sim.called("ktp_activate_initial_roundlive_stats")] == [T + 15.0]

    sim.advance(T + 60.0)
    assert sim.ktp("ROUNDLIVE_TIMEOUT") == []


def test_the_restart_flushes_and_resets_inside_the_pause(source):
    sim = _restarted(source)
    sim.advance(T + 1.0)
    flush, reset = sim.called("dodx_flush_all_stats"), sim.called("dodx_reset_all_stats")
    assert len(flush) == 1 and len(reset) == 1
    assert flush[0][0] <= reset[0][0] < T + 10.0
    assert reset[0][3], "the reset ran with stats collecting"


def test_hlstatsx_freezes_only_after_the_abandoned_segment_is_flushed(source):
    sim = _restarted(source)
    assert sim.daemon_round_live() == 1, "frozen before the flush: its weaponstats land untagged"
    sim.advance(T + 1.0)
    order = [s for s in sim.order if s == "dodx_flush_all_stats" or s.startswith("KTP_ROUND_FREEZE")]
    assert order == ["dodx_flush_all_stats", 'KTP_ROUND_FREEZE (matchid "KTP-TEST-1")']
    assert sim.daemon_round_live() == 0


def test_the_score_restore_lands_between_the_clan_reset_and_go_live(source):
    sim = _restarted(source)
    assert sorted(c[2] for c in sim.called("dodx_set_team_score")) == [[1, 1], [2, 3]]
    sim.round_state(T + 10.0, 0)
    sim.round_state(T + 15.0, 1)
    assert [c[0] for c in sim.called("task_delayed_score_restore")] == [T + 12.0]


def test_a_missing_round_signal_still_goes_live_and_reopens_hlstatsx(source):
    sim = _restarted(source)
    sim.advance(T + 12.9)
    assert sim.paused and sim.daemon_round_live() == 0
    sim.advance(T + 14.0)
    assert sim.ktp("ROUNDLIVE_TIMEOUT") == [T + 13.0]
    assert not sim.paused
    assert sim.hl("KTP_MATCH_START") == [T + 13.0]
    assert sim.daemon_round_live() == 1


def test_a_restart_during_a_round_freeze_takes_over_the_freeze(source):
    sim = Sim(source)
    sim.g.update(g_matchLive=True, g_currentHalf=2, g_roundLive=True,
                 g_firstHalfScore=[0, 3, 1], g_matchScore=[0, 5, 4])
    sim.hl_log.append((50.0, H2_START))
    sim.round_state(T - 5.0, 3)       # a round win: freeze, watchdog armed
    sim.advance(T)
    assert sim.paused
    sim.since = T
    sim.call("execute_restart_half", [1, "admin", "STEAM_0:0:1", "127.0.0.1"])
    sim.advance(T + 40.0)             # past the freeze watchdog, no round signal
    assert sim.ktp("ROUND_FREEZE_WATCHDOG") == []
    assert sim.ktp("ROUNDLIVE_TIMEOUT") == [T + 13.0]
    assert not sim.paused


def test_the_restart_arms_before_it_restarts_and_announces_nothing_new(source):
    body = source.code[source.code.index("stock execute_restart_half("):]
    body = body[:body.index("\n}\n")]
    assert body.index('ktp_await_initial_roundlive("2nd half");') < body.index(
        'server_cmd("mp_clan_restartround 1");')
    # Same match, same demo: the HLTV/Discord forward and the AC announce stay at the half start.
    for later in ("task_restarthalf_stats", "task_restarthalf_discord"):
        tail = source.code[source.code.index(f"public {later}("):]
        tail = tail[:tail.index("\n}\n")]
        body += tail
    assert not re.search(r"g_fwdMatchStart|send_ac_match_start", body)
