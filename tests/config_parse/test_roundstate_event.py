"""RoundState must reach the plugin, and a freeze pause must always end.

KTPAMXX in extension mode dispatches register_event (MessageHook_Handler) but
never register_message, so a message hook registers, logs, and never runs.
Once RoundState does run, every freeze pause it sets needs a way out.
"""
from pathlib import Path
import re


SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"


def _code() -> str:
    """Source without comments, so a comment naming a native is not a use."""
    text = SOURCE.read_text(encoding="utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", "", text)


def _body(kind: str, name: str) -> str:
    match = re.search(
        rf"{kind} (?:bool:|Float:)?{name}\([^)]*\) \{{(?P<body>.*?)\n\}}",
        SOURCE.read_text(encoding="utf-8"),
        re.DOTALL,
    )
    assert match is not None, f"missing {kind} {name}"
    return match.group("body")


def test_roundstate_is_an_event_not_a_message_hook():
    init = _body("public", "plugin_init")
    assert 'register_event("RoundState", "evt_RoundState", "a")' in init
    assert "read_data(1)" in _body("public", "evt_RoundState")


def test_no_message_hooks_remain():
    code = _code()
    for dead in ("register_message(", "get_msg_arg_", "set_msg_arg_",
                 "msg_RoundState", "msg_TeamScore", "g_skipTeamScoreAdjust"):
        assert dead not in code, f"{dead} is not dispatched in extension mode"


def test_freeze_pause_arms_a_watchdog_and_live_disarms_it():
    live, frozen = _body("public", "evt_RoundState").split("} else {", 1)
    assert "dodx_set_stats_paused(1);" in frozen
    assert '"task_round_freeze_watchdog", g_taskRoundFreezeWatchdogId' in frozen
    assert "remove_task(g_taskRoundFreezeWatchdogId);" in live

    watchdog = _body("public", "task_round_freeze_watchdog")
    assert "ktp_clear_round_freeze();" in watchdog


def test_clearing_a_freeze_unpauses_stats():
    clear = _body("stock", "ktp_clear_round_freeze")
    assert "g_roundLive = true;" in clear
    assert "dodx_set_stats_paused(0);" in clear
    assert "remove_task(g_taskRoundFreezeWatchdogId);" in clear


def test_every_teardown_clears_a_freeze_even_without_a_match_id():
    teardown = _body("stock", "ktp_match_teardown_notify")
    assert teardown.index("ktp_clear_round_freeze();") < teardown.index(
        "if (!matchId[0]) return;"
    )


def test_non_teardown_exits_still_unpause():
    # Exits that do not route through ktp_match_teardown_notify.
    for kind, name in (
        ("stock", "handle_first_half_end"),   # half 1 ends, match continues
        ("public", "plugin_init"),            # every map load
    ):
        assert "dodx_set_stats_paused(0);" in _body(kind, name), name
    forcereset = SOURCE.read_text(encoding="utf-8")
    assert re.search(r"g_roundLive = true;\s*g_awaitingRoundLive = false;\s*"
                     r"#if defined HAS_DODX\s*if \(g_hasDodxStatsNatives\) \{\s*"
                     r"dodx_set_stats_paused\(0\);", forcereset)


def test_only_known_sites_pause_stats():
    code = _code()
    sites = [m.start() for m in re.finditer(r"dodx_set_stats_paused\(1\)", code)]
    owners = set()
    for pos in sites:
        head = code[:pos]
        owner = re.findall(r"\n(?:public|stock) (?:bool:|Float:)?(\w+)\(", head)[-1]
        owners.add(owner)
    # freeze, the go-live wait (resumed by RoundState=1 or its timeout), and the
    # test-mode end, which is meant to stay paused until the next .testmatch.
    assert owners == {"evt_RoundState", "task_deferred_stats", "cmd_test_end_match"}, owners


def test_go_live_wait_clears_a_stale_freeze_watchdog():
    deferred = _body("public", "task_deferred_stats")
    assert deferred.index("remove_task(g_taskRoundFreezeWatchdogId);") < deferred.index(
        "ktp_arm_roundlive_fallback("
    )


def test_go_live_waits_for_the_clan_restart_round_reset():
    handler = _body("public", "evt_RoundState")
    gate = handler[: handler.index("if (roundState == 1) {")]
    # A 1 before the reset is the warmup round: ignored, and no go-live.
    ignored = gate.index("reason=before_clan_restart")
    assert "if (!g_roundResetSeen) {" in gate[:ignored]
    assert "return PLUGIN_CONTINUE;" in gate[ignored:]
    # The reset itself is recorded and re-arms the fallback from there.
    assert "g_roundResetSeen = true;" in gate
    assert "ktp_arm_roundlive_fallback(ROUNDLIVE_AFTER_RESET_SECS);" in gate
    # Each go-live wait starts without a reset seen.
    deferred = _body("public", "task_deferred_stats")
    assert deferred.index("g_roundResetSeen = false;") < deferred.index("ktp_arm_roundlive_fallback(")
