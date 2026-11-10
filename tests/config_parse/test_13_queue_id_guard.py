"""The 1.3 Queue ID prompt must not accept a command word as the Queue ID.

The captain's chat is captured raw while the prompt is open, so whatever he types
by reflex becomes part of the match id. A leading '.' or '/' was already refused,
but the bare word was not: "confirm" became `1.3-confirm-<host>`, an id that had
been used before, and the stats daemon attached the half to the old match's
interval and dropped every capture line in it.

The refused list is a literal in the plugin, so these tests derive the commands
the plugin registers from the source and hold the list to them.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT

SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")


def _function_body(signature_prefix: str) -> str:
    start = SOURCE.index(signature_prefix)
    return SOURCE[start : SOURCE.index("\n}", start)]


def _reserved() -> set[str]:
    block = re.search(r"new const g_13ReservedWords\[\]\[\]\s*=\s*\{(.*?)\};", SOURCE, re.S)
    assert block, "the refused-word list is gone"
    words = re.findall(r'"([^"]*)"', block.group(1))
    assert len(words) == len(set(words)), "duplicate entries hide a missing one in review"
    return set(words)


def _registered_chat_words() -> set[str]:
    words = {
        w.lower()
        for w in re.findall(r'register_clcmd\(\s*"say(?:_team)?\s+[./]([A-Za-z0-9_]+)"', SOURCE)
    }
    # Commands that take arguments are matched by prefix in the say hook instead.
    words |= {
        w.lower()
        for w in re.findall(r'equali\(\s*args\s*,\s*"[./]([A-Za-z0-9_]+)"\s*,\s*\d+\s*\)', SOURCE)
    }
    return words


def test_every_registered_chat_command_is_refused_as_a_queue_id() -> None:
    registered = _registered_chat_words()
    # CONTROL: the derivation found the commands a captain actually types.
    assert {"confirm", "ready", "cancel", "ktp", "12man"} <= registered
    missing = registered - _reserved()
    assert not missing, f"add these to g_13ReservedWords: {sorted(missing)}"


def test_reflex_answers_are_refused_too() -> None:
    assert {"confirm", "cancel", "ready", "unready", "yes", "no"} <= _reserved()


def test_entries_are_lowercase_and_survive_the_sanitizer() -> None:
    # An entry the sanitizer would alter could never equal a sanitized input.
    for word in _reserved():
        assert re.fullmatch(r"[a-z0-9_-]+", word), word


def test_the_word_check_runs_on_the_sanitized_input_before_either_entry_is_stored() -> None:
    body = _function_body("stock handle_13_queue_id_input(")
    check = re.search(
        r"for\s*\(\s*new\s+(\w+)\s*=\s*0\s*;\s*\1\s*<\s*sizeof\(g_13ReservedWords\)\s*;\s*\1\+\+\s*\)\s*\{\s*"
        r"if\s*\(\s*equali\(\s*sanitized\s*,\s*g_13ReservedWords\[\1\]\s*\)\s*\)",
        body,
    )
    assert check, "the word check must compare the sanitized input, case-insensitively"
    after = body[check.end() :]
    assert after.index("return PLUGIN_HANDLED;") < after.index("if (g_13InputState == 1)"), (
        "a refused word must return before the first entry is stored"
    )
    assert body.index("new sanitized[") < check.start()
    # Both the first entry and the confirmation pass through it.
    assert check.start() < body.index("if (g_13InputState == 1)") < body.index(
        "} else if (g_13InputState == 2)"
    )


def test_the_prefix_guard_still_stands() -> None:
    body = _function_body("stock handle_13_queue_id_input(")
    assert re.search(r"if\s*\(\s*input\[0\]\s*==\s*'\.'\s*\|\|\s*input\[0\]\s*==\s*'/'\s*\)", body)


def test_the_second_prompt_does_not_invite_the_word() -> None:
    body = _function_body("stock handle_13_queue_id_input(")
    first = body[body.index("if (g_13InputState == 1)") : body.index("} else if (g_13InputState == 2)")]
    prompts = re.findall(r'client_print\(\s*id\s*,\s*print_chat\s*,\s*"([^"]*)"', first)
    # CONTROL: the prompts were found at all.
    assert any("Queue ID received" in p for p in prompts)
    for p in prompts:
        assert not re.search(r"(?i)\bconfirm\b", p), f"prompt invites the word: {p!r}"
