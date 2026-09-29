"""The round-live fallback and the score restore must outwait mp_clan_timer.

The DoD clan restart only takes effect when the mp_clan_timer countdown ends.
A fallback that fires before then activates match stats during warmup, and a
score restore that lands before then is undone by the restart itself.
"""
from pathlib import Path
import re


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
    """Evaluate the helper's arithmetic as written in the source."""
    body = _body("stock", HELPER)
    assert 'get_cvar_float("mp_clan_timer")' in body
    assert "floatclamp(" in body and "CLAN_TIMER_MAX_SECS" in body
    assert "floatmax(countdown + margin, CLAN_RESTART_WAIT_FLOOR_SECS)" in body
    countdown = min(max(clan_timer, 0.0), _define("CLAN_TIMER_MAX_SECS"))
    return max(countdown + _define(margin_define), _define("CLAN_RESTART_WAIT_FLOOR_SECS"))


def _delay_variable_uses_helper(body: str, expr: str, margin_define: str) -> None:
    assert re.fullmatch(r"[A-Za-z_]\w*", expr), f"delay is a literal, not derived: {expr}"
    assert re.search(
        rf"new Float:{expr} = {HELPER}\({margin_define}\);", body
    ), f"{expr} is not derived from {HELPER}({margin_define})"


def test_every_roundlive_timeout_is_armed_from_the_clan_timer():
    arms = re.findall(r'set_task\(\s*([^,]+),\s*"task_roundlive_timeout"', _text())
    assert arms, "the round-live fallback is never armed"
    body = _body("public", "task_deferred_stats")
    expr = _delay_expr(body, "task_roundlive_timeout")
    assert arms == [expr], f"fallback armed outside task_deferred_stats: {arms}"
    _delay_variable_uses_helper(body, expr, "ROUNDLIVE_FALLBACK_MARGIN_SECS")


def test_score_restore_is_scheduled_from_the_clan_timer():
    body = _body("stock", "schedule_score_restoration")
    expr = _delay_expr(body, "task_delayed_score_restore")
    _delay_variable_uses_helper(body, expr, "SCORE_RESTORE_MARGIN_SECS")


def test_waits_exceed_the_countdown_across_the_dll_range():
    for clan_timer in [0.0, 1.0, 5.0, 10.0, 30.0, 255.0]:
        for margin in ("ROUNDLIVE_FALLBACK_MARGIN_SECS", "SCORE_RESTORE_MARGIN_SECS"):
            assert _wait_for(margin, clan_timer) > clan_timer, (margin, clan_timer)


def test_waits_at_the_fleet_clan_timer():
    # Every KTP config sets mp_clan_timer 10.
    assert 10.0 < _wait_for("ROUNDLIVE_FALLBACK_MARGIN_SECS", 10.0) <= 12.0
    assert _wait_for("SCORE_RESTORE_MARGIN_SECS", 10.0) == 12.0


def test_absurd_clan_timer_is_bounded():
    ceiling = _define("CLAN_TIMER_MAX_SECS") + _define("SCORE_RESTORE_MARGIN_SECS")
    assert _wait_for("SCORE_RESTORE_MARGIN_SECS", 100000.0) == ceiling
    assert _wait_for("ROUNDLIVE_FALLBACK_MARGIN_SECS", -5.0) == _define(
        "CLAN_RESTART_WAIT_FLOOR_SECS"
    )


def test_real_round_live_signal_cancels_the_fallback():
    body = _body("public", "msg_RoundState")
    live = body.split("} else {", 1)[0]
    assert live.index("remove_task(g_taskRoundLiveTimeoutId);") < live.index(
        "task_roundlive_match_context();"
    )
