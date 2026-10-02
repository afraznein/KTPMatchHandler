"""The round-live fallback and the score restore must outwait mp_clan_timer.

The DoD clan restart only takes effect when the mp_clan_timer countdown ends.
A fallback that fires before then activates match stats during warmup, and a
score restore that lands before then is undone by the restart itself.
"""
from pathlib import Path
import re

from ._pawn_sim import Sim


SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"
HELPER = "ktp_clan_restart_wait_secs"


def _text() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _body(kind: str, name: str) -> str:
    match = re.search(
        rf"{kind} (?:Float:)?{name}\([^)]*\) \{{(?P<body>.*?)\n\}}", _text(), re.DOTALL
    )
    assert match is not None, f"missing {kind} {name}"
    return match.group("body")


def _define(name: str) -> float:
    match = re.search(rf"^#define {name}\s+([0-9.]+)", _text(), re.MULTILINE)
    assert match is not None, f"missing #define {name}"
    return float(match.group(1))


def _delay_expr(body: str, task: str) -> str:
    calls = re.findall(rf'set_task\(\s*([^,]+),\s*"{task}"', body)
    assert len(calls) == 1, f"expected one set_task for {task}, found {calls}"
    return calls[0].strip()


def _wait_for(margin_define: str, clan_timer: float) -> float:
    """Run the helper as written in the source, with mp_clan_timer set."""
    sim = Sim(clan_timer=clan_timer)
    return sim.call(HELPER, [_define(margin_define)])


def _delay_variable_uses_helper(body: str, expr: str, margin_define: str) -> None:
    assert re.fullmatch(r"[A-Za-z_]\w*", expr), f"delay is a literal, not derived: {expr}"
    assert re.search(
        rf"new Float:{expr} = {HELPER}\({margin_define}\);", body
    ), f"{expr} is not derived from {HELPER}({margin_define})"


def test_every_roundlive_timeout_is_armed_from_the_clan_timer():
    arms = re.findall(r'set_task\(\s*([^,]+),\s*"task_roundlive_timeout"', _text())
    assert arms == ["delay"], f"fallback armed outside ktp_arm_roundlive_fallback: {arms}"
    assert _delay_expr(_body("stock", "ktp_arm_roundlive_fallback"), "task_roundlive_timeout") == "delay"

    await_live = _body("stock", "ktp_await_initial_roundlive")
    assert re.search(
        rf"ktp_arm_roundlive_fallback\(\s*{HELPER}\(ROUNDLIVE_FALLBACK_MARGIN_SECS\)\)", await_live
    ), "the go-live wait does not arm the fallback from the clan timer"
    assert "ktp_await_initial_roundlive(g_deferredHalfText);" in _body("public", "task_deferred_stats")

    # Phase 1 can run before the config task in the same 0.1s task check, so the
    # config task re-arms it from the value the map config just set.
    apply = _body("public", "task_apply_match_config_and_start")
    rearm = apply.index("ktp_arm_roundlive_fallback(")
    assert apply.index("exec_map_config();") < rearm
    assert f"{HELPER}(ROUNDLIVE_FALLBACK_MARGIN_SECS)" in apply[rearm:]


def test_score_restore_is_scheduled_from_the_clan_timer():
    body = _body("stock", "schedule_score_restoration")
    expr = _delay_expr(body, "task_delayed_score_restore")
    _delay_variable_uses_helper(body, expr, "SCORE_RESTORE_MARGIN_SECS")


def test_waits_exceed_the_countdown_across_the_dll_range():
    for clan_timer in [0.0, 1.0, 5.0, 10.0, 30.0, 255.0]:
        for margin in ("ROUNDLIVE_FALLBACK_MARGIN_SECS", "SCORE_RESTORE_MARGIN_SECS"):
            assert _wait_for(margin, clan_timer) > clan_timer, (margin, clan_timer)


def test_waits_at_the_fleet_clan_timer():
    # Every match config sets mp_clan_timer 10 (the aim map-start configs set 0).
    # The fallback outlasts the restart's round reset, which lands as the countdown ends.
    assert 11.0 <= _wait_for("ROUNDLIVE_FALLBACK_MARGIN_SECS", 10.0) <= 15.0
    assert _wait_for("SCORE_RESTORE_MARGIN_SECS", 10.0) == 12.0


def test_absurd_clan_timer_is_bounded():
    ceiling = _define("CLAN_TIMER_MAX_SECS") + _define("SCORE_RESTORE_MARGIN_SECS")
    assert _wait_for("SCORE_RESTORE_MARGIN_SECS", 100000.0) == ceiling
    assert _wait_for("SCORE_RESTORE_MARGIN_SECS", -5.0) == _define(
        "CLAN_RESTART_WAIT_FLOOR_SECS"
    )


def test_real_round_live_signal_cancels_the_fallback():
    body = _body("public", "evt_RoundState")
    live = body.split("} else {", 1)[0]
    assert live.index("remove_task(g_taskRoundLiveTimeoutId);") < live.index(
        "task_roundlive_match_context();"
    )


def test_cmd_ready_arms_the_score_restore_after_the_map_config():
    ready = _body("public", "cmd_ready")
    assert "schedule_score_restoration()" not in ready, (
        "cmd_ready schedules the restore before the map config sets mp_clan_timer"
    )
    assert ready.count("g_scoreRestoreAfterConfig = true;") == 2  # OT and 2nd half
    reset = ready.index("g_scoreRestoreAfterConfig = false;")
    assert reset < ready.index('"task_apply_match_config_and_start"'), (
        "the flag must be cleared before the config task is armed"
    )

    apply = _body("public", "task_apply_match_config_and_start")
    consumed = apply.index("g_scoreRestoreAfterConfig = false;")
    assert consumed < apply.index("if (!g_matchLive) return;"), (
        "an aborted config task must still consume the flag"
    )
    schedule = apply.index("if (restoreScores) schedule_score_restoration();")
    assert apply.index("exec_map_config();") < schedule
    assert apply.rindex("server_exec();") < schedule
