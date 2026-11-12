"""`amx_ktp_test_13_queue_id_input` must exist only in the test-mode build.

The rcon drives the 1.3 Queue ID prompt with no client so Tier 2 can test the
command-word refusal behaviourally. It sets prompt state directly, so in a
release build it would let any rcon holder rewrite a captain's prompt. These
tests hold every mention of it inside a `#if defined KTP_TEST_MODE` region, and
hold the handler to the production function rather than a copy of it.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT

SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")
LINES = SOURCE.split("\n")


def _test_mode_lines() -> set[int]:
    """Line indexes enclosed by a `#if defined KTP_TEST_MODE` branch, nesting-aware."""
    inside, stack = set(), []
    for i, line in enumerate(LINES):
        s = line.strip()
        if s.startswith("#if"):
            stack.append(s == "#if defined KTP_TEST_MODE")
        elif s.startswith("#else"):
            stack[-1] = False if stack[-1] else stack[-1]
        elif s.startswith("#endif"):
            stack.pop()
        elif any(stack):
            inside.add(i)
    assert not stack, "unbalanced #if/#endif"
    return inside


def _function_body(signature_prefix: str) -> str:
    start = SOURCE.index(signature_prefix)
    return SOURCE[start : SOURCE.index("\n}", start)]


def test_every_mention_is_inside_a_test_mode_region() -> None:
    inside = _test_mode_lines()
    hits = [i for i, line in enumerate(LINES)
            if "amx_ktp_test_13_queue_id_input" in line or "cmd_test_13_queue_id_input" in line]
    # CONTROL: the registration and the handler were both found.
    assert len(hits) >= 2, hits
    leaked = [i + 1 for i in hits if i not in inside]
    assert not leaked, f"reachable from a release build at lines {leaked}"


def test_the_region_finder_sees_release_code_as_outside() -> None:
    # CONTROL for the test above: a production-only line must read as outside.
    inside = _test_mode_lines()
    prod = next(i for i, line in enumerate(LINES) if "stock handle_13_queue_id_input(" in line)
    assert prod not in inside
    reg = next(i for i, line in enumerate(LINES) if '"amx_ktp_test_reset"' in line)
    assert reg in inside


def test_handler_calls_the_production_function_after_setting_the_state() -> None:
    body = _function_body("public cmd_test_13_queue_id_input(")
    assert "ADMIN_RCON" in body
    set_state = body.index("g_13InputState = inputState;")
    call = body.index("handle_13_queue_id_input(id, input);")
    assert set_state < call
    # The readback is printed after the call, so it reports what the handler left.
    assert call < body.index('"KTP_TEST_13_QUEUE_ID: ok')


def test_state_two_cannot_reach_the_confirm_branch() -> None:
    # The confirm branch opens a menu for the caller; an rcon caller has no player.
    body = _function_body("public cmd_test_13_queue_id_input(")
    assert body.index("g_13QueueIdFirst[0] = EOS;") < body.index("handle_13_queue_id_input(id, input);")
    assert not re.search(r"copy\(\s*g_13QueueIdFirst", body)


def test_reset_closes_an_open_prompt() -> None:
    body = _function_body("public cmd_test_reset(")
    assert "g_13InputState = 0;" in body
    assert "remove_task(g_task13InputTimeoutId);" in body
