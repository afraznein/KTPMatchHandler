"""Source-contract tests for the blocked-cvar .ready refusal (0.10.172).

KTPCvarChecker is optional, and this plugin runs every match on the fleet, so the
binding has to degrade to "no refusal" rather than to "plugin failed to load" or
"plugin paused". Those properties come from AMXX core, not from anything a
compile can show:

  * CPlugin::Finalize fails the load on any unbound native unless a native filter
    returns non-zero for it, then routes calls to invalid_native, which asks the
    filter again with trap=1 and raises a runtime error if it answers 0.
  * amxx_DynaCallback pauses the CALLING plugin when the native's owner is not
    executable, and a plugin that fails to load after plugin_natives keeps its
    registered natives -- hence the running-by-title check on every call.

These tests pin the source shape those rules depend on. They also pin the names
KTPCvarChecker's tools/check_blocked_bridge.py holds on the other side.
"""
from __future__ import annotations

import re

from .conftest import REPO_ROOT

SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")
CODE = "\n".join(line.split("//", 1)[0] if '"' not in line.split("//", 1)[0] else line
                 for line in SOURCE.splitlines())
COMPACT = re.sub(r"\s+", " ", CODE)
NATIVE = "ktp_cvar_get_blocked"


def _body(signature: str) -> str:
    start = SOURCE.index(signature)
    i = SOURCE.index("{", start)
    depth = 0
    for j in range(i, len(SOURCE)):
        if SOURCE[j] == "{":
            depth += 1
        elif SOURCE[j] == "}":
            depth -= 1
            if depth == 0:
                return SOURCE[i:j + 1]
    raise AssertionError(f"unbalanced body for {signature}")


def test_names_match_what_the_checker_registers() -> None:
    assert '#define KTP_CVAR_LIBRARY      "ktp_cvar_checker"' in SOURCE
    assert '#define KTP_CVAR_PLUGIN_TITLE "KTP Cvar Checker"' in SOURCE
    assert f"native {NATIVE}(id, cvar[], cvarLen, required[], requiredLen);" in SOURCE


def test_native_is_not_a_required_library() -> None:
    # A reqlib pragma would make the checker mandatory at load, bypassing the filter.
    assert "#pragma reqlib" not in SOURCE
    assert "#pragma loadlib" not in SOURCE


def test_filter_is_set_in_plugin_natives_and_scoped_to_the_bridge() -> None:
    natives = _body("public plugin_natives()")
    assert 'set_native_filter("native_filter_optional");' in natives

    flt = _body("public native_filter_optional(const name[], index, trap)")
    # Handled for both trap values, and nothing else: any other missing native
    # must still fail the load.
    assert f'return equal(name, "{NATIVE}") ? PLUGIN_HANDLED : PLUGIN_CONTINUE;' in flt
    assert flt.count("return") == 1


def test_every_native_call_goes_through_the_guarded_wrapper() -> None:
    calls = [m.start() for m in re.finditer(NATIVE + r"\s*\(", CODE)
             if not CODE[max(0, m.start() - 7):m.start()].endswith("native ")]
    lookup = _body("stock cvar_block_lookup(id, cvar[], cvarLen, required[], requiredLen)")
    assert len(calls) == 1 and NATIVE + "(" in lookup

    wrapper_calls = [m.start() for m in re.finditer(r"\bcvar_block_lookup\s*\(", CODE)
                     if not CODE[max(0, m.start() - 6):m.start()].endswith("stock ")]
    assert wrapper_calls, "the lookup is never used"
    for at in wrapper_calls:
        # Each use sits inside a function that proved the bridge is callable.
        fn_start = max(CODE.rfind("\npublic ", 0, at), CODE.rfind("\nstock ", 0, at))
        fn_head = CODE[fn_start:at]
        if fn_head.startswith("\nstock hold_golive_for_cvar_blocks"):
            continue  # only reached from cmd_ready's guarded go-live check
        assert "cvar_bridge_available()" in fn_head, fn_head[:80]


def test_bridge_requires_a_running_checker_not_just_the_library() -> None:
    avail = _body("stock bool: cvar_bridge_available()")
    assert "LibraryExists(KTP_CVAR_LIBRARY, LibType_Library)" in avail
    assert "is_plugin_loaded(KTP_CVAR_PLUGIN_TITLE)" in avail
    assert 'equal(status, "running") || equal(status, "debug")' in avail


def test_ready_refusal_runs_before_the_player_is_marked_ready() -> None:
    ready = _body("public cmd_ready(id)")
    refuse = ready.index("event=READY_REFUSED_CVAR_BLOCKED")
    mark = ready.index("g_ready[id] = true;")
    pending_gate = ready.index("if (!g_matchPending)")
    assert pending_gate < refuse < mark
    guard = ready[:refuse]
    assert "cvar_block_applies() && cvar_bridge_available()" in guard


def test_golive_hold_precedes_the_live_transition() -> None:
    ready = _body("public cmd_ready(id)")
    hold = ready.index("hold_golive_for_cvar_blocks()")
    assert "(cvar_block_applies() && cvar_bridge_available()) ? " in ready[:hold]
    assert hold < ready.index("EXPLICIT_OT_INIT")
    assert hold < ready.index("g_matchLive       = true;")
    assert "g_cvarGoliveHeld = held > 0;" in ready

    body = _body("stock hold_golive_for_cvar_blocks()")
    assert "g_ready[p] = false;" in body
    assert "if (!on_match_team(p)) continue;" in body
    assert "kick" not in body.lower()

    # Team 0 only: a rostered spectator (team 3) must release the hold, or it cannot clear.
    team = _body("stock bool: on_match_team(id)")
    assert "(tid == 0 && g_secondHalfPending && get_player_roster_team(id) > 0)" in team


def test_a_held_golive_can_always_be_retried() -> None:
    ready = _body("public cmd_ready(id)")
    already = ready.index("You are already READY.")
    # An already-ready player re-checks go-live while held, instead of the old early return.
    assert "if (!g_cvarGoliveHeld) {" in ready[:already]
    # The refusal and the hold agree on who is on a match team.
    assert "if (on_match_team(id) && cvar_block_applies() && cvar_bridge_available())" in ready
    # The latch never outlives its pending phase.
    assert "g_cvarGoliveHeld = false;" in _body("stock enter_pending_phase(const initiator[])")
    assert "g_cvarGoliveHeld = false;" in _body("public plugin_init()")


def test_no_refusal_path_outside_the_pending_ready_flow() -> None:
    # Once live the plugin never acts on a blocked player: the helpers are reached
    # only from cmd_ready (after its !g_matchPending return) and the plugin_cfg log.
    for name in ("hold_golive_for_cvar_blocks", "tell_cvar_block_fix"):
        owners = set()
        for m in re.finditer(r"\b" + name + r"\s*\(", CODE):
            line_start = CODE.rfind("\n", 0, m.start()) + 1
            if re.match(r"(?:public|stock)\b", CODE[line_start:m.start()]):
                continue  # the definition, not a call
            decl = re.findall(r"^(?:public|stock)[^\n(]*?\b(\w+)\s*\(", CODE[:m.start()], re.M)
            owners.add(decl[-1] if decl else "")
        assert owners, f"{name} is never called"
        assert owners <= {"cmd_ready", "hold_golive_for_cvar_blocks"}, owners


def test_scope_default_is_every_type_except_scrim() -> None:
    enum = re.search(r"enum MatchType \{(.*?)\}", SOURCE, re.S)
    assert enum, "MatchType enum not found"
    values = dict(re.findall(r"(MATCH_TYPE_\w+)\s*=\s*(\d+)", enum.group(1)))
    assert values["MATCH_TYPE_SCRIM"] == "1"
    expected = sum(1 << int(v) for k, v in values.items() if k != "MATCH_TYPE_SCRIM")
    m = re.search(r'register_cvar\("ktp_blocked_cvar_match_types",\s*"(\d+)"\)', SOURCE)
    assert m and int(m.group(1)) == expected == 61

    applies = _body("stock bool: cvar_block_applies()")
    assert "(1 << _:g_matchType)" in applies
