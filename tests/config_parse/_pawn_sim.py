"""A small interpreter for the Pawn subset the round-state handlers are written in.

It runs the plugin's own function bodies, read out of KTPMatchHandler.sma, against
Python stand-ins for the natives, with a clock and a task queue. A test can then
play a sequence of RoundState messages through the real logic instead of grepping
for the lines it hopes are there.

Supported: if/else, return, `new` locals, expression statements, assignment,
&& || ! ?: comparisons and arithmetic, calls, string indexing, tags (ignored),
#if defined / #else / #endif. Anything else raises, so a handler that grows a loop
fails loudly here rather than being half-simulated.
"""
from __future__ import annotations

import heapq
import re
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[2] / "KTPMatchHandler.sma"
DEFINED = {"HAS_DODX"}
# Pawn stocks that wrap engine output; the simulator records them instead.
AS_NATIVE = {"log_ktp", "ktp_activate_initial_roundlive_stats"}


# ---------------------------------------------------------------- source ----

def _strip_comments(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "^" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            j = text.index("*/", i + 2)
            out.append("\n" * text.count("\n", i, j))
            i = j + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def _preprocess(text: str) -> str:
    lines, stack = [], []
    for line in text.split("\n"):
        s = line.strip()
        m = re.match(r"#if\s+defined\s+(\w+)$", s)
        if m:
            stack.append(m.group(1) in DEFINED)
            lines.append("")
            continue
        if s.startswith("#if"):
            raise NotImplementedError(f"preprocessor: {s}")
        if s == "#else":
            stack[-1] = not stack[-1]
            lines.append("")
            continue
        if s == "#endif":
            stack.pop()
            lines.append("")
            continue
        lines.append(line if all(stack) else "")
    return "\n".join(lines)


class Source:
    def __init__(self, path: Path = SOURCE):
        self.raw = path.read_text(encoding="utf-8")
        self.code = _strip_comments(self.raw)
        self.defines = {
            m.group(1): float(m.group(2)) if "." in m.group(2) else int(m.group(2))
            for m in re.finditer(r"^#define (\w+) (-?[\d.]+)\b", self.code, re.M)
        }
        self.globals = {}
        for m in re.finditer(r"^new (?:bool:|Float:)?(g_\w+)(\[[^\]]*\])?(?: = ([^;]+))?;",
                             self.code, re.M):
            name, array, init = m.groups()
            if array:
                self.globals[name] = ""
            elif init is None:
                self.globals[name] = 0
            else:
                init = init.strip()
                self.globals[name] = {"true": True, "false": False}.get(
                    init, float(init) if "." in init else int(init) if re.fullmatch(r"-?\d+", init) else 0)

    def function(self, name: str):
        m = re.search(rf"^(?:public|stock) (?:bool:|Float:)?{name}\((?P<params>[^)]*)\)\s*\{{",
                      self.code, re.M)
        if m is None:
            return None
        body = _brace_block(self.code, m.end() - 1)
        params = []
        for p in m.group("params").split(","):
            p = p.split("=")[0].strip()
            if p:
                params.append(re.sub(r"^(?:const\s+)?(?:\w+:)?", "", p).split("[")[0].strip())
        return params, Parser(_preprocess(body)).block()

    def fragment(self, start_marker: str, end_marker: str):
        """Statements from the line holding start_marker to the one holding end_marker."""
        a = self.raw.index(start_marker)
        a = self.raw.rindex("\n", 0, a) + 1
        b = self.raw.index(end_marker, a)
        b = self.raw.index(";", b) + 1
        return Parser(_preprocess(_strip_comments(self.raw[a:b]))).statements()


def _brace_block(text: str, open_at: int) -> str:
    depth, i = 0, open_at
    while True:
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "^" else 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[open_at:i + 1]
        i += 1


# ----------------------------------------------------------------- lexer ----

_TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<str>"(?:\^.|[^"^])*")
  | (?P<tag>[A-Za-z_]\w*:(?=[A-Za-z_(]))
  | (?P<num>\d+\.\d+|\d+)
  | (?P<id>[A-Za-z_]\w*)
  | (?P<op>&&|\|\||==|!=|<=|>=|\+\+|--|\+=|-=|[-+*/%!<>=?:(){}\[\],;])
""", re.X)


def _unescape(s: str) -> str:
    return re.sub(r"\^(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s[1:-1])


def tokenize(text: str):
    toks, pos = [], 0
    while pos < len(text):
        m = _TOKEN.match(text, pos)
        if not m:
            raise SyntaxError(f"cannot lex {text[pos:pos + 30]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "tag"):
            continue
        val = m.group()
        if kind == "str":
            val = _unescape(val)
        elif kind == "num":
            val = float(val) if "." in val else int(val)
        toks.append((kind, val))
    toks.append(("eof", None))
    return toks


# ---------------------------------------------------------------- parser ----

_BINARY = {"||": 1, "&&": 2, "==": 3, "!=": 3, "<": 4, ">": 4, "<=": 4, ">=": 4,
           "+": 5, "-": 5, "*": 6, "/": 6, "%": 6}


class Parser:
    def __init__(self, text: str):
        self.toks = tokenize(text)
        self.i = 0

    def peek(self, val=None):
        kind, v = self.toks[self.i]
        return v == val and kind == "op" if val is not None else (kind, v)

    def take(self, val=None):
        tok = self.toks[self.i]
        if val is not None and not (tok[0] == "op" and tok[1] == val):
            raise SyntaxError(f"expected {val!r}, got {tok!r}")
        self.i += 1
        return tok

    def statements(self):
        out = []
        while self.peek()[0] != "eof":
            out.append(self.statement())
        return ("block", out)

    def block(self):
        self.take("{")
        out = []
        while not self.peek("}"):
            out.append(self.statement())
        self.take("}")
        return ("block", out)

    def statement(self):
        kind, v = self.peek()
        if kind == "op" and v == "{":
            return self.block()
        if kind == "op" and v == ";":
            self.take()
            return ("block", [])
        if kind == "id" and v == "if":
            self.take()
            self.take("(")
            cond = self.expr()
            self.take(")")
            then = self.statement()
            other = None
            if self.peek() == ("id", "else"):
                self.take()
                other = self.statement()
            return ("if", cond, then, other)
        if kind == "id" and v == "return":
            self.take()
            value = None if self.peek(";") else self.expr()
            self.take(";")
            return ("return", value)
        if kind == "id" and v == "new":
            self.take()
            decls = []
            while True:
                _, name = self.take()
                init = ("num", 0)
                if self.peek("["):
                    while not self.peek("]"):
                        self.take()
                    self.take("]")
                    init = ("str", "")
                if self.peek("="):
                    self.take()
                    init = self.expr()
                decls.append((name, init))
                if not self.peek(","):
                    break
                self.take(",")
            self.take(";")
            return ("new", decls)
        if kind == "id" and v in ("for", "while", "do", "switch"):
            raise NotImplementedError(f"statement {v!r} is not simulated")
        e = self.expr()
        self.take(";")
        return ("expr", e)

    def expr(self):
        left = self.ternary()
        for op in ("=", "+=", "-="):
            if self.peek(op):
                self.take()
                return ("assign", op, left, self.expr())
        return left

    def ternary(self):
        cond = self.binary(1)
        if self.peek("?"):
            self.take()
            a = self.expr()
            self.take(":")
            b = self.expr()
            return ("cond", cond, a, b)
        return cond

    def binary(self, level):
        left = self.unary()
        while True:
            kind, v = self.peek()
            if kind != "op" or v not in _BINARY or _BINARY[v] < level:
                return left
            self.take()
            left = ("bin", v, left, self.binary(_BINARY[v] + 1))

    def unary(self):
        if self.peek("!"):
            self.take()
            return ("not", self.unary())
        if self.peek("-"):
            self.take()
            return ("neg", self.unary())
        return self.postfix(self.primary())

    def primary(self):
        kind, v = self.take()
        if kind == "num":
            return ("num", v)
        if kind == "str":
            return ("str", v)
        if kind == "id":
            if v in ("true", "false"):
                return ("num", v == "true")
            return ("var", v)
        if kind == "op" and v == "(":
            e = self.expr()
            self.take(")")
            return e
        raise SyntaxError(f"unexpected {v!r}")

    def postfix(self, node):
        while True:
            if self.peek("("):
                self.take()
                args = []
                while not self.peek(")"):
                    args.append(self.expr())
                    if self.peek(","):
                        self.take()
                self.take(")")
                node = ("call", node[1], args)
            elif self.peek("["):
                self.take()
                idx = self.expr()
                self.take("]")
                node = ("index", node, idx)
            else:
                return node


# ----------------------------------------------------------- interpreter ----

class _Return(Exception):
    def __init__(self, value):
        self.value = value


def pawn_format(fmt: str, args) -> str:
    conv = iter(args)

    def one(m):
        spec = m.group()
        if spec == "%%":
            return "%"
        val = next(conv)
        if spec.endswith("d"):
            val = int(val)
        return spec % val
    return re.sub(r"%%|%[-\d.]*[dsfi]", one, fmt)


class Sim:
    """The plugin's round-state logic on a clock, with HLStatsX's view of it."""

    def __init__(self, source: Source | None = None, clan_timer: float = 10.0):
        self.src = source or Source()
        self.g = dict(self.src.globals)
        self.g.update(self.src.defines)
        self.g.update(g_hasDodxStatsNatives=True, g_matchLive=False, g_roundLive=True,
                      g_matchId="KTP-TEST-1", g_currentMap="dod_test", g_deferredHalfText="1st",
                      g_matchType=1)
        self.cvars = {"mp_clan_timer": clan_timer}
        self.now = 1.0
        self.tasks = []           # heap of (due, seq, id, name)
        self.seq = 0
        self.paused = False
        self.ktp_log = []         # (time, line) from log_ktp
        self.hl_log = []          # (time, line) from log_message: what HLStatsX reads
        self._event_arg = None
        self._funcs = {}
        self.since = 0.0          # hl() and ktp() ignore lines logged before this

    # ---- driving ----
    def arm_go_live(self, match_id: str = "KTP-TEST-1"):
        """Run task_deferred_stats' own arming statements: pause, then wait for go-live."""
        self.g.update(g_matchLive=True, g_matchId=match_id)
        self._exec(self.src.fragment("// 3. Pause stats until round goes live",
                                     "event=STATS_PAUSED_AWAITING_ROUNDLIVE"), {})

    def advance(self, to: float):
        while self.tasks and self.tasks[0][0] <= to:
            due, _, tid, name = heapq.heappop(self.tasks)
            self.now = due
            self.call(name, [])
        self.now = to

    def round_state(self, at: float, state: int):
        self.advance(at)
        self._event_arg = state
        self.call("evt_RoundState", [])
        self._event_arg = None

    def daemon_round_live(self):
        """HLStatsX's round_live for the current match, replayed from its log lines."""
        ctx = None
        for _, line in self.hl_log:
            if line.startswith("KTP_MATCH_START"):
                ctx = 1
            elif line.startswith(("KTP_MATCH_END", "KTP_HALF_END")):
                ctx = None
            elif ctx is not None and line.startswith("KTP_ROUND_FREEZE"):
                ctx = 0
            elif ctx is not None and line.startswith("KTP_ROUND_LIVE"):
                ctx = 1
        return ctx

    def hl(self, prefix: str):
        return [t for t, line in self.hl_log if t >= self.since and line.startswith(prefix)]

    def ktp(self, event: str):
        return [t for t, line in self.ktp_log
                if t >= self.since and f"event={event} " in line + " "]

    # ---- natives ----
    def native(self, name, args):
        if name == "read_data":
            return self._event_arg
        if name == "get_gametime":
            return self.now
        if name == "log_ktp":
            self.ktp_log.append((self.now, pawn_format(args[0], args[1:])))
            return 0
        if name == "log_message":
            self.hl_log.append((self.now, pawn_format(args[0], args[1:])))
            return 0
        if name == "log_amx":
            return 0
        if name == "set_task":
            delay, fn, tid = args[:3]
            self.seq += 1
            heapq.heappush(self.tasks, (self.now + delay, self.seq, tid, fn))
            return 1
        if name == "remove_task":
            before = len(self.tasks)
            self.tasks = [t for t in self.tasks if t[2] != args[0]]
            heapq.heapify(self.tasks)
            return int(before != len(self.tasks))
        if name == "dodx_set_stats_paused":
            self.paused = bool(args[0])
            return 1
        if name == "get_cvar_float":
            return float(self.cvars.get(args[0], 0.0))
        if name == "floatclamp":
            return min(max(args[0], args[1]), args[2])
        if name == "floatmax":
            return max(args[0], args[1])
        if name == "floatmin":
            return min(args[0], args[1])
        if name == "charsmax":
            return 0
        if name == "ktp_activate_initial_roundlive_stats":
            # Covered op-by-op by test_testmatch_stats_order; here only its resume matters.
            self.paused = False
            return 0
        raise NotImplementedError(f"native {name!r} is not simulated")

    # ---- evaluation ----
    def call(self, name, args):
        if name not in self._funcs:
            self._funcs[name] = None if name in AS_NATIVE else self.src.function(name)
        fn = self._funcs[name]
        if fn is None:
            return self.native(name, args)
        params, body = fn
        local = dict(zip(params, args))
        try:
            self._exec(body, local)
        except _Return as r:
            return r.value
        return 0

    def _exec(self, node, local):
        kind = node[0]
        if kind == "block":
            for st in node[1]:
                self._exec(st, local)
        elif kind == "if":
            if self._truth(self._eval(node[1], local)):
                self._exec(node[2], local)
            elif node[3] is not None:
                self._exec(node[3], local)
        elif kind == "return":
            raise _Return(None if node[1] is None else self._eval(node[1], local))
        elif kind == "new":
            for name, init in node[1]:
                local[name] = self._eval(init, local)
        elif kind == "expr":
            self._eval(node[1], local)
        else:
            raise NotImplementedError(kind)

    @staticmethod
    def _truth(v):
        return bool(v)

    def _lookup(self, name, local):
        if name in local:
            return local[name]
        if name in self.g:
            return self.g[name]
        if name == "PLUGIN_CONTINUE":
            return 0
        if name == "PLUGIN_HANDLED":
            return 1
        raise NameError(f"unknown symbol {name!r}")

    def _store(self, name, value, local):
        (local if name in local else self.g)[name] = value

    def _eval(self, node, local):
        kind = node[0]
        if kind in ("num", "str"):
            return node[1]
        if kind == "var":
            return self._lookup(node[1], local)
        if kind == "not":
            return not self._truth(self._eval(node[1], local))
        if kind == "neg":
            return -self._eval(node[1], local)
        if kind == "cond":
            return self._eval(node[2] if self._truth(self._eval(node[1], local)) else node[3], local)
        if kind == "index":
            base, idx = self._eval(node[1], local), self._eval(node[2], local)
            return ord(base[idx]) if idx < len(base) else 0
        if kind == "bin":
            op = node[1]
            if op == "&&":
                return self._truth(self._eval(node[2], local)) and self._truth(self._eval(node[3], local))
            if op == "||":
                return self._truth(self._eval(node[2], local)) or self._truth(self._eval(node[3], local))
            a, b = self._eval(node[2], local), self._eval(node[3], local)
            return {"==": lambda: a == b, "!=": lambda: a != b, "<": lambda: a < b,
                    ">": lambda: a > b, "<=": lambda: a <= b, ">=": lambda: a >= b,
                    "+": lambda: a + b, "-": lambda: a - b, "*": lambda: a * b,
                    "/": lambda: a / b, "%": lambda: a % b}[op]()
        if kind == "assign":
            op, target, value = node[1], node[2], self._eval(node[3], local)
            if target[0] != "var":
                raise NotImplementedError("assignment to a non-variable")
            if op == "+=":
                value = self._lookup(target[1], local) + value
            elif op == "-=":
                value = self._lookup(target[1], local) - value
            self._store(target[1], value, local)
            return value
        if kind == "call":
            name, arg_nodes = node[1], node[2]
            if name == "copy":
                self._store(arg_nodes[0][1], self._eval(arg_nodes[2], local), local)
                return 0
            return self.call(name, [self._eval(a, local) for a in arg_nodes])
        raise NotImplementedError(kind)
