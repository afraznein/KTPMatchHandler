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
