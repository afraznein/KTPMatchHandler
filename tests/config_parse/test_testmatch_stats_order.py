from pathlib import Path
import re


SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"


def _test_end_match_body() -> str:
    text = SOURCE.read_text(encoding="utf-8")
    start = text.index("public cmd_test_end_match(id)")
    end = text.index("public cmd_test_reset", start)
    return text[start:end]


def _stock_body(name: str) -> str:
    text = SOURCE.read_text(encoding="utf-8")
    match = re.search(rf"stock {name}\(\) \{{(?P<body>.*?)\n\}}", text, re.DOTALL)
    assert match is not None, f"missing stock {name}"
    return match.group("body")


def _public_body(name: str) -> str:
    text = SOURCE.read_text(encoding="utf-8")
    match = re.search(
        rf"public {name}\([^)]*\) \{{(?P<body>.*?)\n\}}", text, re.DOTALL
    )
    assert match is not None, f"missing public {name}"
    return match.group("body")


def test_testmatch_flushes_weapon_stats_before_closing_match_context():
    """Production's teardown flushes first and logs KTP_MATCH_END second.

    Lane B must preserve that ordering or StatsMe rows are recorded with a
    NULL match_id and half=0, certifying a path production does not use.
    """
    body = _test_end_match_body()
    assert body.index("dodx_flush_all_stats();") < body.index(
        'log_message("KTP_MATCH_END'
    )


def test_testmatch_resets_weapon_stats_immediately_after_flush():
    body = _test_end_match_body()
    assert body.index("dodx_flush_all_stats();") < body.index(
        "ktp_reset_test_wstats();"
    ) < body.index('log_message("KTP_MATCH_END')


def test_post_end_bot_kills_cannot_accumulate_or_flush_outside_context():
    """Test teardown must quiesce DODX before HLStatsX closes the match.

    Lane B bots keep fighting between consecutive matches. A kill injected in
    that interval must not enter a weapon accumulator that the next warmup
    flush can emit after the old daemon context has closed.
    """
    body = _test_end_match_body()
    ordered = (
        "dodx_flush_all_stats();",
        "ktp_reset_test_wstats();",
        "dodx_set_stats_paused(1);",
        'log_message("KTP_MATCH_END',
        "ExecuteForward(g_fwdMatchEnd",
        "send_ac_match_end(g_matchId);",
        'ktp_set_match_context("");',
    )
    positions = [body.index(token) for token in ordered]
    assert positions == sorted(positions)
    assert "dodx_set_stats_paused(0);" not in body


def test_testmatch_teardown_cancels_deferred_context_reopeners():
    """No old round-live callback may unpause or restore the closed context."""
    body = _test_end_match_body()
    pause = body.index("dodx_set_stats_paused(1);")

    assert body.index("g_awaitingRoundLive = false;") < pause
    assert body.index("remove_task(g_taskRoundLiveTimeoutId);") < pause
    assert body.index("remove_task(g_taskSetMatchIdId);") < pause
    assert body.index("remove_task(g_taskMatchStartLogId);") < pause


def test_final_stats_and_ac_tail_keep_native_match_context_until_drained():
    """StatsMe and AC receive the final in-match tail before context clear."""
    body = _test_end_match_body()
    assert body.index("dodx_flush_all_stats();") < body.index(
        'log_message("KTP_MATCH_END'
    )
    assert body.index("send_ac_match_end(g_matchId);") < body.index(
        'ktp_set_match_context("");'
    )


def test_testmatch_ac_reset_clears_every_match_scoped_buffer_without_outbound():
    """Suppressed test data must not survive into the next test match."""
    reset = _stock_body("ktp_reset_test_ac_state")
    timeline_reset = _stock_body("timeline_buffers_drain")
    fire_reset = _stock_body("fire_batch_reset")

    assert "timeline_buffers_drain();" in reset
    assert "g_swDropped = 0;" in reset
    assert "g_hitDropped = 0;" in reset
    assert "fire_batch_reset();" in reset
    assert "g_aimFlushCursor = 1;" in reset
    assert "g_fireFlushCursor = 1;" in reset
    assert "g_baselineMatchId[0] = EOS;" in reset
    assert "dodx_reset_aim_stats(i)" in reset

    assert "g_swCount = 0;" in timeline_reset
    assert "g_swHead  = 0;" in timeline_reset
    assert "g_hitCount = 0;" in timeline_reset

    for payload in (
        "g_acAnnouncePayload[0] = EOS;",
        "g_acEndPayload[0] = EOS;",
        "g_weaponTimelineJsonBuf[0] = EOS;",
        "g_aimGeometryJsonBuf[0] = EOS;",
        "g_fireJsonBuf[0] = EOS;",
    ):
        assert payload in reset

    assert "g_fireCount = 0;" in fire_reset
    assert "g_fireDropped = 0;" in fire_reset
    assert "g_fireGeomRejected = 0;" in fire_reset
    assert "g_fireRosterCount = 0;" in fire_reset
    assert "g_fireSlotCache[i] = -1;" in fire_reset

    assert "curl_" not in reset
    assert "send_ac_" not in reset


def test_testmatch_ac_end_uses_full_reset_then_returns_without_network():
    source = SOURCE.read_text(encoding="utf-8")
    start = source.index("stock send_ac_match_end(const matchId[])")
    end = source.index("// ================ 0.5.0 Weapon Timeline", start)
    body = source[start:end]
    suppressed = body.split("#endif", 1)[0]

    assert suppressed.index("if (g_testMatchActive)") < suppressed.index(
        "ktp_reset_test_ac_state();"
    ) < suppressed.index("return;")
    assert "curl_" not in suppressed
    assert "send_ac_weapon_timeline_batch();" not in suppressed
    assert "send_ac_weapon_fire_batch();" not in suppressed


def test_consecutive_all_bot_testmatches_cannot_replay_first_match_stats():
    """The test-only reset must include bots but continue to exclude HLTV.

    Lane B's roster is all bots. If this helper used production's ``ch`` flags,
    the first match's read-only StatsMe flush would remain in every bot's weapon
    accumulator and a second test match would emit the same rows again.
    """
    test_reset = _stock_body("ktp_reset_test_wstats")
    assert 'get_players(players, num, "h");' in test_reset
    assert 'get_players(players, num, "ch");' not in test_reset
    assert "reset_user_wstats(players[i])" in test_reset

    production_reset = _stock_body("ktp_reset_all_wstats")
    assert 'get_players(players, num, "ch");' in production_reset

    teardown = _test_end_match_body()
    assert teardown.count("dodx_flush_all_stats();") == 1
    assert teardown.count("ktp_reset_test_wstats();") == 1


def test_next_full_testmatch_reenables_dodx_at_round_live():
    """The post-end pause must not disable the following full bot match.

    ``task_testmatch_ready`` drives production ``cmd_ready``. That schedules
    the normal deferred stats boundary, which holds DODX paused through the
    restart and resumes on RoundState=1; the timeout provides the same resume
    if the engine signal is absent.
    """
    test_ready = _public_body("task_testmatch_ready")
    ready = _public_body("cmd_ready")
    deferred = _public_body("task_deferred_stats")
    round_state = _public_body("msg_RoundState")
    timeout = _public_body("task_roundlive_timeout")

    assert "cmd_ready(id);" in test_ready
    assert 'set_task(0.1, "task_deferred_stats"' in ready
    assert "dodx_set_stats_paused(1);" in deferred

    round_live, round_frozen = round_state.split("} else {", 1)
    assert "dodx_set_stats_paused(0);" in round_live
    assert "dodx_set_stats_paused(1);" in round_frozen
    assert "dodx_set_stats_paused(0);" in timeout
