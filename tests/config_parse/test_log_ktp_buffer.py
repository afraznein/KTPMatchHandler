"""Every log_ktp line must fit log_ktp's buffer at its worst case.

log_ktp formats into a fixed buffer with vformat, and vformat truncates without a
word: the line still lands, it just ends early. AC_ROSTER_PARSE lost its last two
fields that way on every go-live, and its minimum render was already over the
limit, so nothing short of rendering the format strings would have caught it.

So each call is rendered at its maximum: every integer at full int32 width and
every string at the size of the buffer actually passed to it. A string that
arrives through an unsized parameter is followed back to every caller of that
function, and the largest buffer any of them passes is the one budgeted.
"""
from __future__ import annotations

import re
from functools import lru_cache

from .conftest import REPO_ROOT

SOURCE = (REPO_ROOT / "KTPMatchHandler.sma").read_text(encoding="utf-8")

INT_WIDTH = len("-2147483648")
HEX_WIDTH = len("ffffffff")
FLOAT_INT_DIGITS = len("-2147483648")
FLOAT_DEFAULT_PRECISION = 6

SPEC = re.compile(r"%([-+ 0#]*)(\d*)(?:\.(\d+))?([a-zA-Z%])")
FUNC_HEAD = re.compile(
    r"^(?:(?:public|stock|static)\s+)*(?:[A-Za-z_]\w*:)?([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?://[^\n]*)?\n?\s*\{",
    re.M,
)
NOT_FUNCS = {"if", "for", "while", "switch", "return", "new", "static", "else", "do"}

# Hook callbacks have no caller in this file; the engine fills these parameters.
# Map names travel through 64-byte level buffers in ReHLDS's changelevel paths.
ENGINE_SUPPLIED = {
    ("OnChangeLevel", 0): 63,
    ("OnPfnChangeLevel", 0): 63,
}


def _blank_comments(src: str) -> str:
    """Comments become spaces, newlines kept, strings untouched (Pawn escapes with ^)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "^" else 1
            out.append(src[i : j + 1])
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n and src[j] != "'":
                j += 2 if src[j] == "^" else 1
            out.append(src[i : j + 1])
            i = j + 1
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


CODE = _blank_comments(SOURCE)


def _split_args(text: str, start: int) -> tuple[list[str], int]:
    """Top-level comma-separated arguments of the call whose '(' ends at start."""
    args, cur, depth, i = [], [], 1, start
    while depth:
        c = text[i]
        if c == '"' or c == "'":
            j = i + 1
            while text[j] != c:
                j += 2 if text[j] == "^" else 1
            cur.append(text[i : j + 1])
            i = j + 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if not depth:
                break
        elif c == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    args.append("".join(cur).strip())
    return args, i


def _literal_len(lit: str) -> int:
    """Rendered length of a Pawn string literal body: ^x is one character."""
    return len(re.sub(r"\^.", "x", lit))


DEFINES: dict[str, str] = {
    m.group(1): m.group(2).strip()
    for m in re.finditer(r"^\s*#define\s+(\w+)\s+([^\n]+?)\s*$", CODE, re.M)
}
for m in re.finditer(r"\bconst\s+(\w+)\s*=\s*([^;]+);", CODE):
    DEFINES.setdefault(m.group(1), m.group(2).strip())


@lru_cache(maxsize=None)
def _const(expr: str) -> int:
    expr = expr.strip()
    for _ in range(20):
        new = re.sub(
            r"\b[A-Za-z_]\w*\b",
            lambda m: f"({DEFINES[m.group(0)]})" if m.group(0) in DEFINES else m.group(0),
            expr,
        )
        if new == expr:
            break
        expr = new
    if not re.fullmatch(r"[\d\s()+\-*/]+", expr):
        raise AssertionError(f"cannot size a buffer from {expr!r}")
    return int(eval(expr.replace("/", "//")))  # noqa: S307 - digits and operators only


def _functions() -> list[tuple[int, int, str, str]]:
    """(start, end, name, params) of every function body in the source."""
    out = []
    for m in FUNC_HEAD.finditer(CODE):
        name = m.group(1)
        if name in NOT_FUNCS:
            continue
        end = CODE.find("\n}", m.end())
        out.append((m.start(), end, name, m.group(2)))
    return out


FUNCTIONS = _functions()


def _enclosing(pos: int) -> tuple[int, int, str, str] | None:
    for fn in FUNCTIONS:
        if fn[0] <= pos <= fn[1]:
            return fn
    return None


def _declared_size(statement: str, name: str) -> int | None:
    """Last dimension of `name` in one new/static declaration, or None if absent."""
    m = re.search(r"(?:^|[\s,])(?:[A-Za-z_]\w*:)?" + re.escape(name) + r"\s*((?:\[[^\]]*\]\s*)+)", statement)
    if not m:
        return None
    dims = re.findall(r"\[([^\]]*)\]", m.group(1))
    return _const(dims[-1]) if dims[-1].strip() else -1


@lru_cache(maxsize=None)
def _param_budget(func: str, index: int) -> int:
    """Largest string any caller passes at this parameter position."""
    if (func, index) in ENGINE_SUPPLIED:
        return ENGINE_SUPPLIED[(func, index)]
    best = -1
    for m in re.finditer(r"(?<![\w.])" + re.escape(func) + r"\s*\(", CODE):
        line_start = CODE.rfind("\n", 0, m.start()) + 1
        if any(f[0] == line_start and f[2] == func for f in FUNCTIONS):
            continue  # the definition itself
        args, _ = _split_args(CODE, m.end())
        if index < len(args) and args[index]:
            best = max(best, _string_width(args[index], m.start()))
    if best < 0:
        raise AssertionError(f"no caller sizes parameter {index} of {func}()")
    return best


def _split_ternary(arg: str) -> tuple[str, str] | None:
    """(then, else) of a top-level `c ? a : b`, nesting and string contents respected."""
    depth, q, i, n = 0, -1, 0, len(arg)
    pending = 0
    while i < n:
        c = arg[i]
        if c in "\"'":
            j = i + 1
            while j < n and arg[j] != c:
                j += 2 if arg[j] == "^" else 1
            i = j + 1
            continue
        if c in "([":
            depth += 1
        elif c in ")]":
            depth -= 1
        elif depth == 0 and c == "?":
            if q < 0:
                q = i
            else:
                pending += 1
        elif depth == 0 and c == ":" and q >= 0:
            if pending:
                pending -= 1
            else:
                return arg[q + 1 : i], arg[i + 1 :]
        i += 1
    return None


def _string_width(arg: str, pos: int) -> int:
    """Longest string this argument expression can hold at this call site."""
    arg = arg.strip()
    while arg.startswith("(") and arg.endswith(")"):
        arg = arg[1:-1].strip()
    lits = re.findall(r'"((?:\^.|[^"^])*)"', arg)
    if arg.startswith('"') and arg.endswith('"') and len(lits) == 1:
        return _literal_len(lits[0])
    tern = _split_ternary(arg)
    if tern:
        return max(_string_width(tern[0], pos), _string_width(tern[1], pos))
    if arg in DEFINES:
        return _string_width(DEFINES[arg], pos)
    call = re.fullmatch(r"(\w+)\s*\(.*\)", arg, re.S)
    if call:
        fn = next((f for f in FUNCTIONS if f[2] == call.group(1)), None)
        assert fn is not None, f"cannot size the string returned by {arg!r}"
        sizes = [_const(s) for s in re.findall(r"\bstatic\s+\w+\[([^\]]+)\]", CODE[fn[0] : fn[1]])]
        assert sizes, f"{call.group(1)}() returns no static buffer to size"
        return max(sizes) - 1
    name_m = re.match(r"([A-Za-z_]\w*)", arg)
    assert name_m, f"cannot size string argument {arg!r}"
    name = name_m.group(1)

    fn = _enclosing(pos)
    if fn is not None:
        body = CODE[fn[0] : pos]
        for stmt in reversed(re.findall(r"\b(?:new|static)\s+([^;]*);", body)):
            size = _declared_size(" " + stmt, name)
            if size is not None:
                return size - 1
        params = [p.strip() for p in fn[3].split(",")]
        for i, p in enumerate(params):
            size = _declared_size(" " + p, name)
            if size is not None:
                return size - 1 if size > 0 else _param_budget(fn[2], i)
    for stmt in re.findall(r"^(?:new|static)\s+([^;]*);", CODE, re.M):
        size = _declared_size(" " + stmt, name)
        if size is not None:
            return size - 1
    raise AssertionError(f"no declaration sizes {name!r}")


def _spec_width(flags: str, width: str, prec: str | None, conv: str, arg: str, pos: int) -> int:
    if conv in "diu":
        w = INT_WIDTH
    elif conv in "xX":
        w = HEX_WIDTH
    elif conv == "c":
        w = 1
    elif conv == "f":
        w = FLOAT_INT_DIGITS + 1 + (int(prec) if prec else FLOAT_DEFAULT_PRECISION)
    elif conv == "s":
        w = _string_width(arg, pos)
        if prec:
            w = min(w, int(prec))
    else:
        raise AssertionError(f"teach this test the width of %{conv}")
    return max(w, int(width) if width else 0)


def _log_calls() -> list[tuple[int, str, list[str], int]]:
    calls = []
    for m in re.finditer(r"(?<![\w.])log_ktp\s*\(", CODE):
        if re.search(r"\bstock\s+$", CODE[CODE.rfind("\n", 0, m.start()) + 1 : m.start()]):
            continue
        args, _ = _split_args(CODE, m.end())
        line = CODE.count("\n", 0, m.start()) + 1
        calls.append((line, args[0], args[1:], m.start()))
    return calls


def _render_max(fmt_arg: str, args: list[str], pos: int) -> int:
    assert fmt_arg.startswith('"') and fmt_arg.endswith('"'), "format must be a literal"
    fmt = fmt_arg[1:-1]
    total = _literal_len(SPEC.sub("", fmt))
    ai = 0
    for m in SPEC.finditer(fmt):
        flags, width, prec, conv = m.groups()
        if conv == "%":
            total += 1
            continue
        assert ai < len(args), f"format {fmt[:60]!r} has more specifiers than arguments"
        total += _spec_width(flags, width, prec, conv, args[ai], pos)
        ai += 1
    return total


def _buffer_chars() -> int:
    body = SOURCE[SOURCE.index("stock log_ktp(") :]
    body = body[: body.index("\n}")]
    size = re.search(r"\b(?:new|static)\s+msg\[(\w+)\]", body).group(1)
    assert re.search(r"vformat\(\s*msg\s*,\s*charsmax\(msg\)", body), "vformat must be bounded by msg"
    return _const(size) - 1


def test_every_log_ktp_line_fits_its_buffer_at_worst_case() -> None:
    cap = _buffer_chars()
    calls = _log_calls()
    over = [
        (line, width)
        for line, fmt, args, pos in calls
        if (width := _render_max(fmt, args, pos)) > cap
    ]
    assert not over, (
        f"log_ktp truncates at {cap} chars; these lines can render longer "
        f"(source line, worst-case width): {over}. Split the line or widen the buffer."
    )


def test_the_walk_found_every_call() -> None:
    # CONTROL: a scanner that silently finds nothing would pass the test above.
    calls = _log_calls()
    assert len(calls) == len(re.findall(r"(?<![\w.])log_ktp\s*\(", CODE)) - 1
    assert len(calls) > 100
    events = {re.search(r"event=(\w+)", fmt).group(1) for _, fmt, _, _ in calls if "event=" in fmt}
    assert {"AC_ROSTER_PARSE", "AC_ROSTER_SLOTS", "MATCH_START"} <= events


def test_the_renderer_counts_what_it_claims() -> None:
    # CONTROL: the measured widths come from declarations, not defaults.
    assert _string_width("g_matchId", len(CODE) - 1) == 63
    assert _string_width('flag ? "yes" : "no"', 0) == 3
    assert _string_width("safe_sid(sid)", 0) == 43
    assert _render_max('"a=%d b=%s"', ['x', '"zz"'], 0) == len("a= b=") + INT_WIDTH + 2


def test_the_old_parse_line_would_fail_at_the_old_buffer() -> None:
    # CONTROL: the one-line PARSE format that shipped in 0.10.183 against 255 chars.
    old = (
        '"event=AC_ROSTER_PARSE match_id=%s http=%d bytes=%d truncated=%s '
        "sessions_marker=present ttl=%d objects=%d rows=%d echoed=%d on_teams=%d "
        "matched=%d blind=%d blind_unparsed=%d active_missing=%d ordinal_off=%d "
        'slots_not_connected=%d slots_authid_changed=%d unsendable_ids=%d"'
    )
    args = ["g_acRosterMatchId", "a", "b", 'truncated ? "yes" : "no"'] + ["n"] * 13
    assert _render_max(old, args, 0) > 255
