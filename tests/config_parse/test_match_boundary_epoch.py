"""KTP_MATCH_START and KTP_HALF_END carry the producer's clock for HLStatsX.

The daemon stamped a half's start with its own NOW() when it processed the line,
so any ingest backlog put the go-live snapshot before the half's start and the
event-time resolver rejected it. The line now carries `event_epoch` from
get_systime(), the clock every capture stream is stamped with, and the start's
epoch is read before activation so the half can never start after its own first
events.

The rest of the line is unchanged, so an old daemon that does not know the
property still parses the fields it reads.
"""
from __future__ import annotations

import re

import pytest

from ._pawn_sim import SYSTIME_BASE, Sim, Source

ARM = 100.0
OLD_START = re.compile(
    r'^KTP_MATCH_START \(matchid "[^"]+"\) \(map "[^"]*"\) \(half "[^"]+"\) \(type "\d+"\)')
OLD_HALF_END = re.compile(r'^KTP_HALF_END \(matchid "[^"]*"\) \(map "[^"]*"\) \(half "1st"\)')
EPOCH = re.compile(r' \(event_epoch "(\d+)"\)')


@pytest.fixture(scope="module")
def source():
    return Source()


def _go_live(source, at):
    sim = Sim(source, clan_timer=10.0)
    sim.advance(ARM)
    sim.g["g_delayedMatchId"] = "KTP-TEST-1"
    sim.g["g_delayedMap"] = "dod_test"
    sim.g["g_delayedHalf"] = "1st"
    sim.arm_go_live()
    sim.round_state(ARM + 10.0, 0)
    sim.round_state(at, 1)
    return sim


def _start_lines(sim):
    return [line for _, line in sim.hl_log if line.startswith("KTP_MATCH_START")]


def test_go_live_start_carries_the_producer_epoch(source):
    sim = _go_live(source, ARM + 15.0)
    lines = _start_lines(sim)
    assert len(lines) == 1
    m = EPOCH.search(lines[0])
    assert m, lines[0]
    assert int(m.group(1)) == SYSTIME_BASE + int(ARM + 15.0)


def test_the_epoch_is_appended_so_an_old_daemon_reads_the_same_fields(source):
    line = _start_lines(_go_live(source, ARM + 15.0))[0]
    assert OLD_START.match(line), line
    assert line.endswith(')')
    assert EPOCH.search(line).end() == len(line), "event_epoch must be the last property"


def test_the_start_epoch_is_read_before_activation(source):
    sim = _go_live(source, ARM + 15.0)
    order = sim.order
    activation = order.index("ktp_activate_initial_roundlive_stats")
    reads = [i for i, op in enumerate(order) if op == "get_systime"]
    assert reads and reads[0] < activation, order


@pytest.mark.parametrize("func", [
    "task_roundlive_match_context",
    "task_delayed_match_start_log",
    "cmd_test_fire_match_start_log",
])
def test_every_match_start_emitter_carries_the_epoch(source, func):
    body = source.code[source.code.index(f"public {func}("):]
    body = body[:body.index("\n}\n")]
    emits = re.findall(r'log_message\("KTP_MATCH_START[^\n]*', body)
    assert emits, func
    for e in emits:
        assert '(event_epoch ^"%d^")"' in e, e


def test_half_end_carries_the_epoch(source):
    emits = re.findall(r'log_message\("KTP_HALF_END[^\n]*', source.code)
    assert len(emits) == 1
    assert '(half ^"1st^") (event_epoch ^"%d^")"' in emits[0], emits[0]
    assert emits[0].rstrip().endswith('get_systime());'), emits[0]


def test_no_match_start_or_half_end_emitter_is_missed(source):
    for marker in ("KTP_MATCH_START", "KTP_HALF_END"):
        emits = re.findall(r'log_message\("' + marker + r'[^\n]*', source.code)
        assert emits
        assert all("event_epoch" in e for e in emits), [e for e in emits if "event_epoch" not in e]
