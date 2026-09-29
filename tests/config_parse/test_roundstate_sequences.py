"""Play RoundState sequences through the plugin's own handler code.

_pawn_sim runs evt_RoundState, the go-live fallback, the freeze watchdog and the
go-live arming helper task_deferred_stats calls straight out of KTPMatchHandler.sma,
on a clock. Timings follow the local bot stack at mp_clan_timer 10: the clan restart's
RoundState=0 lands 10s after the arm and its RoundState=1 5s after that.
"""
from __future__ import annotations

import pytest

from ._pawn_sim import Sim, Source

ARM = 100.0


@pytest.fixture(scope="module")
def source():
    return Source()


def _armed(source, clan_timer=10.0):
    sim = Sim(source, clan_timer=clan_timer)
    sim.advance(ARM)
    sim.arm_go_live()
    assert sim.paused and sim.g["g_awaitingRoundLive"]
    return sim


def _live(source):
    sim = _armed(source)
    sim.round_state(ARM + 10.0, 0)
    sim.round_state(ARM + 15.0, 1)
    assert sim.hl("KTP_MATCH_START") == [ARM + 15.0]
    sim.since = ARM + 15.0 + 1e-6    # later asserts read only what follows go-live
    return sim


def test_a_half_start_arms_through_the_shared_helper(source):
    assert source.function("ktp_await_initial_roundlive") is not None
    assert source.code.count("ktp_await_initial_roundlive(g_deferredHalfText);") == 1


def test_a_warmup_round_in_the_countdown_is_not_go_live(source):
    sim = _armed(source)
    sim.round_state(ARM + 2.0, 0)     # warmup round reset
    sim.round_state(ARM + 5.0, 1)     # warmup RoundUnfreeze
    assert sim.hl("KTP_MATCH_START") == []
    assert sim.paused
    sim.round_state(ARM + 10.0, 0)    # the clan restart
    sim.round_state(ARM + 15.0, 1)
    assert sim.hl("KTP_MATCH_START") == [ARM + 15.0]
    assert not sim.paused
    sim.advance(ARM + 60.0)
    assert sim.ktp("ROUNDLIVE_TIMEOUT") == []


def test_b_warmup_round_win_in_the_countdown_is_not_the_reset(source):
    sim = _armed(source)
    sim.round_state(ARM + 1.0, 3)     # warmup round won by Allies
    sim.round_state(ARM + 5.5, 0)     # warmup reset, ~4.5s before the clan one
    sim.round_state(ARM + 6.0, 1)     # warmup RoundUnfreeze
    assert sim.hl("KTP_MATCH_START") == []
    assert sim.paused
    sim.round_state(ARM + 10.0, 0)
    sim.round_state(ARM + 15.0, 1)
    assert sim.hl("KTP_MATCH_START") == [ARM + 15.0]
    assert len(sim.ktp("ROUNDLIVE_RESET_SEEN")) == 1
    assert len(sim.ktp("ROUNDLIVE_RESET_IGNORED")) == 2


@pytest.mark.parametrize("at, accepted", [(8.9, False), (9.0, True)])
def test_the_reset_threshold_is_one_second_short_of_the_timer(source, at, accepted):
    sim = _armed(source)
    sim.round_state(ARM + at, 0)
    assert bool(sim.ktp("ROUNDLIVE_RESET_SEEN")) is accepted


def test_c_a_round_win_freezes_then_the_next_round_goes_live(source):
    sim = _live(source)
    sim.round_state(200.0, 4)         # Axis win the round
    assert sim.paused and sim.hl("KTP_ROUND_FREEZE") == [200.0]
    assert sim.daemon_round_live() == 0
    sim.round_state(205.0, 0)         # round reset: still frozen, logged once
    assert sim.hl("KTP_ROUND_FREEZE") == [200.0]
    sim.round_state(208.0, 1)
    assert not sim.paused
    assert sim.hl("KTP_ROUND_LIVE") == [208.0]
    assert sim.daemon_round_live() == 1
    sim.advance(260.0)                # the watchdog was disarmed
    assert sim.ktp("ROUND_FREEZE_WATCHDOG") == []


def test_c_a_draw_is_a_freeze_too(source):
    sim = _live(source)
    sim.round_state(200.0, 5)
    assert sim.paused and sim.daemon_round_live() == 0


def test_d_a_freeze_with_no_round_live_is_released_and_hlstatsx_told(source):
    sim = _live(source)
    sim.round_state(200.0, 3)
    sim.advance(229.0)
    assert sim.paused
    sim.advance(231.0)
    assert not sim.paused
    assert sim.ktp("ROUND_FREEZE_WATCHDOG") == [230.0]
    assert sim.hl("KTP_ROUND_LIVE") == [230.0]
    assert sim.daemon_round_live() == 1
    # Same line the real go-live writes, so the daemon parses it the same way.
    assert sim.hl_log[-1][1] == 'KTP_ROUND_LIVE (matchid "KTP-TEST-1")'
    sim.round_state(235.0, 1)         # the late real one changes nothing
    assert sim.hl("KTP_ROUND_LIVE") == [230.0]


def test_e_a_reset_before_the_arm_leaves_go_live_to_the_fallback(source):
    # mp_clan_timer 0: the restart's reset can land before the wait is armed, so the
    # fallback goes live inside the first round's freeze and the real 1 is a no-op.
    sim = _armed(source, clan_timer=0.0)
    sim.advance(ARM + 4.0)
    assert sim.ktp("ROUNDLIVE_TIMEOUT") == [ARM + 3.0]
    assert sim.hl("KTP_MATCH_START") == [ARM + 3.0]
    assert not sim.paused
    sim.round_state(ARM + 5.0, 1)
    assert sim.hl("KTP_MATCH_START") == [ARM + 3.0]
    assert sim.hl("KTP_ROUND_LIVE") == []
