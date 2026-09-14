"""The AC flush loops must visit every player slot exactly once per flush.

Both loops rotate a start cursor so a full payload sheds a different player each
interval. When the slot is derived from the cursor while the loop is still
advancing it, the walk jumps: some slots are visited twice (a player's whole shot
list sent twice) and others never (shots lost, counted nowhere). These tests read
the loop out of the source and run its cursor arithmetic, so a regression to that
shape fails here rather than on the fleet.
"""
from __future__ import annotations

import functools
import random
import re
from collections import Counter
from pathlib import Path

import pytest

SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"
MAX_PLAYERS = 32

LOOPS = [
    ("send_ac_weapon_fire_batch", "slot", "g_fireFlushCursor"),
    ("send_ac_aim_geometry_batch", "id", "g_aimFlushCursor"),
]


def _strip_strings_and_comments(text: str) -> str:
    """Blank out string literals and comments so brace matching sees code only.

    Pawn escapes with ^, and these loops build JSON, so their literals are full of
    braces.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "^" else 1
            out.append(" " * (j + 1 - i))
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _stock(name: str) -> str:
    code = _strip_strings_and_comments(SOURCE.read_text(encoding="utf-8"))
    start = code.index(f"stock {name}()")
    open_brace = code.index("{", start)
    depth = 0
    for j in range(open_brace, len(code)):
        if code[j] == "{":
            depth += 1
        elif code[j] == "}":
            depth -= 1
            if depth == 0:
                return code[start : j + 1]
    raise AssertionError(f"unterminated stock {name}")


def _step_loop(stock: str) -> tuple[str, str]:
    """Return (code before the step loop, the step loop's body)."""
    header = "for (new step = 0; step < MAX_PLAYERS; step++) {"
    at = stock.index(header)
    open_brace = at + len(header) - 1
    depth = 0
    for j in range(open_brace, len(stock)):
        if stock[j] == "{":
            depth += 1
        elif stock[j] == "}":
            depth -= 1
            if depth == 0:
                return stock[:at], stock[open_brace + 1 : j]
    raise AssertionError("unterminated step loop")


@functools.lru_cache(maxsize=None)
def _loop_shape(stock_name: str, slot_var: str, cursor: str) -> tuple[bool, bool]:
    """Return (slot reads the live cursor, loop advances the cursor)."""
    before, body = _step_loop(_stock(stock_name))

    m = re.search(
        rf"new {slot_var} = 1 \+ \(\((\w+) - 1 \+ step\) % MAX_PLAYERS\);", body
    )
    assert m, f"{stock_name}: slot derivation changed shape; update this test"
    base = m.group(1)

    writes = re.findall(rf"\b{re.escape(cursor)}\s*=(?!=)[^;]*;", body)
    advance = f"{cursor} = 1 + ({slot_var} % MAX_PLAYERS);"
    assert all(w == advance for w in writes), (
        f"{stock_name}: unrecognised cursor write {writes}; update this test"
    )

    if base != cursor:
        assert re.search(rf"new {base} = {re.escape(cursor)};", before), (
            f"{stock_name}: {base} is not taken from {cursor} before the loop"
        )
        assert not re.search(rf"\b{base}\s*=(?!=)", body), (
            f"{stock_name}: {base} is reassigned inside the loop"
        )
    return base == cursor, bool(writes)


def _simulate(stock_name: str, slot_var: str, cursor: str, start: int, occupied: set[int]):
    """Run the loop's cursor arithmetic as written; return (visits, final cursor)."""
    reads_live, advances = _loop_shape(stock_name, slot_var, cursor)
    live = start
    visits: Counter[int] = Counter()
    for step in range(MAX_PLAYERS):
        origin = live if reads_live else start
        slot = 1 + ((origin - 1 + step) % MAX_PLAYERS)
        if slot in occupied:
            visits[slot] += 1
            if advances:
                live = 1 + (slot % MAX_PLAYERS)
    return visits, live


def _cases():
    rng = random.Random(20260913)
    sets = [set(range(1, MAX_PLAYERS + 1)), {1}, {MAX_PLAYERS}, {3, 4, 5, 6, 7, 8}]
    sets += [set(rng.sample(range(1, MAX_PLAYERS + 1), rng.randint(1, 12))) for _ in range(40)]
    return sets


@pytest.mark.parametrize("stock_name,slot_var,cursor", LOOPS)
def test_every_slot_is_visited_exactly_once(stock_name, slot_var, cursor):
    for occupied in _cases():
        for start in range(1, MAX_PLAYERS + 1):
            visits, _ = _simulate(stock_name, slot_var, cursor, start, occupied)
            wrong = {s: visits[s] for s in occupied if visits[s] != 1}
            assert not wrong, (
                f"{stock_name}: start={start} slots visited !=1 times: {wrong}"
            )


@pytest.mark.parametrize("stock_name,slot_var,cursor", LOOPS)
def test_cursor_still_rotates_past_the_last_emitted_slot(stock_name, slot_var, cursor):
    for occupied in _cases():
        for start in range(1, MAX_PLAYERS + 1):
            _, final = _simulate(stock_name, slot_var, cursor, start, occupied)
            walk = [1 + ((start - 1 + s) % MAX_PLAYERS) for s in range(MAX_PLAYERS)]
            last = [s for s in walk if s in occupied][-1]
            assert final == 1 + (last % MAX_PLAYERS)


def test_fire_flush_names_an_accounting_break():
    stock = SOURCE.read_text(encoding="utf-8")
    body = stock[stock.index("stock send_ac_weapon_fire_batch()") :]
    body = body[: body.index("\n}\n")]
    assert "if (shotsEmitted + truncShots != g_fireCount)" in body
    assert "event=AC_WEAPON_FIRE_ACCOUNTING_MISMATCH" in body
