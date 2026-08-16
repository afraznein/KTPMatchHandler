from pathlib import Path


SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"


def _test_end_match_body() -> str:
    text = SOURCE.read_text(encoding="utf-8")
    start = text.index("public cmd_test_end_match(id)")
    end = text.index("public cmd_test_reset", start)
    return text[start:end]


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
        "ktp_reset_all_wstats();"
    ) < body.index('log_message("KTP_MATCH_END')
