#!/usr/bin/env python3
"""Tiny: a second, independent Sublang frontend.

Parses a small procedural language and writes Wire v2 (.sublang-wire). It shares
no code with the Emerald builder and does not import an Emerald AST. All
language rules (scoping, evaluation order, Int64 checked arithmetic) live here,
not in the neutral core.

Language:
    program   = { function }
    function  = "fn" NAME "(" [ NAME { "," NAME } ] ")" block
    statement = "let" NAME "=" expr ";" | NAME "=" expr ";"
              | "if" expr block [ "else" block ] | "while" expr block
              | "return" expr ";"
    expr      = comparison; comparison = sum [ ("=="|"!="|"<"|"<="|">"|">=") sum ]
    sum       = term { ("+"|"-") term }; term = unary { ("*"|"/"|"%") unary }
    unary     = "-" unary | NAME "(" args ")" | NAME | INT | "(" expr ")"

Every value is a signed 64-bit Int. Comparisons yield a condition and are only
valid as `if`/`while` conditions or as the whole right side of nothing else;
arithmetic traps (abort) on overflow and division by zero. `main()` is the entry.
"""
import re
import sys

KEYWORDS = {"fn", "let", "if", "else", "while", "return"}
TOKEN = re.compile(r"\s*(?:(//[^\n]*)|(\d+)|([A-Za-z_][A-Za-z0-9_]*)|(==|!=|<=|>=|[-+*/%<>=(){},;]))")
INT_MIN = -(1 << 63)
INT_MAX = (1 << 63) - 1
# Primitive type ids are schema-defined: Void, Bool, Int, Float.
BOOL, INT = 2, 3
FAILURE_ABORT = 1  # the single failure action declared below
EFFECT_CONSERVATIVE = 1
PROFILE_STARTUP = 1


class TinyError(Exception):
    def __init__(self, line, column, message):
        super().__init__(f"{line}:{column}: {message}")


def tokenize(text):
    tokens, position, line, line_start = [], 0, 1, 0
    while position < len(text):
        if text[position:].strip() == "":
            break
        match = TOKEN.match(text, position)
        if not match:
            skipped = len(text[position:]) - len(text[position:].lstrip())
            raise TinyError(line, position + skipped - line_start + 1, f"unexpected character {text[position + skipped]!r}")
        prefix = text[position:match.start(0) + (len(match.group(0)) - len(match.group(0).lstrip()))]
        line += prefix.count("\n")
        if "\n" in prefix:
            line_start = position + prefix.rfind("\n") + 1
        token_start = match.end(0) - len(match.group(0).lstrip())
        column = token_start - line_start + 1
        if match.group(1) is None:
            kind = "int" if match.group(2) else "name" if match.group(3) else "op"
            value = match.group(2) or match.group(3) or match.group(4)
            if kind == "name" and value in KEYWORDS:
                kind = "kw"
            tokens.append((kind, value, line, column))
        position = match.end(0)
    tokens.append(("eof", "", line, 1))
    return tokens


class Parser:
    def __init__(self, tokens):
        self.tokens, self.index = tokens, 0

    def peek(self):
        return self.tokens[self.index]

    def take(self, kind=None, value=None):
        token = self.tokens[self.index]
        if (kind and token[0] != kind) or (value and token[1] != value):
            wanted = value or kind
            raise TinyError(token[2], token[3], f"expected {wanted}, found {token[1] or 'end of file'!r}")
        self.index += 1
        return token

    def accept(self, value):
        if self.peek()[1] == value and self.peek()[0] in ("op", "kw"):
            self.index += 1
            return True
        return False

    def program(self):
        functions = []
        while self.peek()[0] != "eof":
            functions.append(self.function())
        return functions

    def function(self):
        start = self.take("kw", "fn")
        name = self.take("name")
        self.take("op", "(")
        params = []
        if not self.accept(")"):
            params.append(self.take("name"))
            while self.accept(","):
                params.append(self.take("name"))
            self.take("op", ")")
        return {"name": name[1], "span": (start[2], start[3]), "params": params, "body": self.block()}

    def block(self):
        self.take("op", "{")
        statements = []
        while not self.accept("}"):
            statements.append(self.statement())
        return statements

    def statement(self):
        token = self.peek()
        span = (token[2], token[3])
        if self.accept("let"):
            name = self.take("name")
            self.take("op", "=")
            value = self.expr()
            self.take("op", ";")
            return ("let", span, name[1], value)
        if self.accept("return"):
            value = self.expr()
            self.take("op", ";")
            return ("return", span, value)
        if self.accept("if"):
            condition = self.expr()
            then = self.block()
            other = self.block() if self.accept("else") else []
            return ("if", span, condition, then, other)
        if self.accept("while"):
            return ("while", span, self.expr(), self.block())
        name = self.take("name")
        self.take("op", "=")
        value = self.expr()
        self.take("op", ";")
        return ("assign", span, name[1], value)

    def expr(self):
        left = self.sum()
        token = self.peek()
        if token[0] == "op" and token[1] in ("==", "!=", "<", "<=", ">", ">="):
            self.index += 1
            return ("compare", (token[2], token[3]), token[1], left, self.sum())
        return left

    def sum(self):
        left = self.term()
        while self.peek()[0] == "op" and self.peek()[1] in ("+", "-"):
            token = self.take()
            left = ("binary", (token[2], token[3]), token[1], left, self.term())
        return left

    def term(self):
        left = self.unary()
        while self.peek()[0] == "op" and self.peek()[1] in ("*", "/", "%"):
            token = self.take()
            left = ("binary", (token[2], token[3]), token[1], left, self.unary())
        return left

    def unary(self):
        token = self.peek()
        span = (token[2], token[3])
        if self.accept("-"):
            return ("neg", span, self.unary())
        if token[0] == "int":
            self.index += 1
            return ("int", span, int(token[1]))
        if self.accept("("):
            inner = self.expr()
            self.take("op", ")")
            return inner
        name = self.take("name")
        if self.accept("("):
            args = []
            if not self.accept(")"):
                args.append(self.expr())
                while self.accept(","):
                    args.append(self.expr())
                self.take("op", ")")
            return ("call", span, name[1], args)
        return ("var", span, name[1])


PREDICATES = {"==": "eq", "!=": "ne", "<": "lt", "<=": "le", ">": "gt", ">=": "ge"}
OPCODES = {"+": "int.add", "-": "int.sub", "*": "int.mul", "/": "int.div", "%": "int.rem"}
PASS = "value"


class FunctionBuilder:
    """SSA construction. Every mutable variable in scope becomes a block parameter
    at joins and loop headers, so no phi analysis is needed."""

    def __init__(self, module, name, params):
        self.module, self.name = module, name
        self.values = []  # type per value id - 1
        self.params = []
        self.blocks = []  # each: {"params": [...], "ops": [...]}
        for param in params:
            self.params.append((self.new_value(INT), param))
        self.current = self.new_block([])
        self.env = {}  # name -> current value id
        for value, param in self.params:
            self.env[param[1]] = value
        self.terminated = False

    def new_value(self, type_id):
        self.values.append(type_id)
        return len(self.values)

    def new_block(self, params):
        self.blocks.append({"params": params, "ops": []})
        return len(self.blocks)

    def emit(self, opcode, span, **fields):
        if self.terminated:
            raise TinyError(span[0], span[1], "unreachable code after return")
        # The native backend requires operation ids to be unique across the module.
        op = dict(id=self.module.next_operation(), opcode=opcode, span=self.module.span(span), value=0, type=0, ref=0,
                  overflow="", predicate="", effect=0, integer=0, operands=[], targets=[], true_args=0)
        op.update(fields)
        self.blocks[self.current - 1]["ops"].append(op)
        return op

    def result(self, opcode, span, type_id, **fields):
        value = self.new_value(type_id)
        self.emit(opcode, span, value=value, type=type_id, **fields)
        return value

    # --- expressions -------------------------------------------------
    def value(self, node):
        kind, span = node[0], node[1]
        if kind == "int":
            if node[2] > INT_MAX:
                raise TinyError(span[0], span[1], "integer literal exceeds Int64")
            return self.result("const.int", span, INT, integer=node[2])
        if kind == "var":
            if node[2] not in self.env:
                raise TinyError(span[0], span[1], f"undefined variable {node[2]!r}")
            return self.env[node[2]]
        if kind == "neg":
            operand = self.value(node[2])
            return self.result("int.neg", span, INT, operands=[operand], overflow="trap", ref=FAILURE_ABORT)
        if kind == "binary":
            left = self.value(node[3])
            right = self.value(node[4])
            return self.result(OPCODES[node[2]], span, INT, operands=[left, right], overflow="trap", ref=FAILURE_ABORT)
        if kind == "call":
            return self.call(node)
        raise TinyError(span[0], span[1], "a comparison is only allowed as an if/while condition")

    def call(self, node):
        _, span, name, args = node
        if name not in self.module.functions:
            raise TinyError(span[0], span[1], f"unknown function {name!r}")
        function_id, arity = self.module.functions[name]
        if len(args) != arity:
            raise TinyError(span[0], span[1], f"{name} expects {arity} argument(s), got {len(args)}")
        operands = [self.value(argument) for argument in args]
        return self.result("call.direct", span, INT, operands=operands, ref=function_id, effect=EFFECT_CONSERVATIVE)

    def condition(self, node):
        if node[0] != "compare":
            raise TinyError(node[1][0], node[1][1], "condition must be a comparison")
        left = self.value(node[3])
        right = self.value(node[4])
        return self.result("compare", node[1], BOOL, operands=[left, right], predicate=PREDICATES[node[2]])

    # --- statements --------------------------------------------------
    def statements(self, statements):
        for statement in statements:
            if self.terminated:
                raise TinyError(statement[1][0], statement[1][1], "unreachable code after return")
            getattr(self, "s_" + statement[0])(statement)

    def scope_names(self):
        return list(self.env)  # insertion order is declaration order

    def s_let(self, node):
        if node[2] in self.env:
            raise TinyError(node[1][0], node[1][1], f"variable {node[2]!r} is already declared")
        self.env[node[2]] = self.value(node[3])

    def s_assign(self, node):
        if node[2] not in self.env:
            raise TinyError(node[1][0], node[1][1], f"undefined variable {node[2]!r}")
        self.env[node[2]] = self.value(node[3])

    def s_return(self, node):
        value = self.value(node[2])
        self.emit("return", node[1], operands=[value])
        self.terminated = True

    def jump_args(self, names):
        return [self.env[name] for name in names]

    def s_if(self, node):
        outer = self.scope_names()
        condition = self.condition(node[2])
        then_block = self.new_block([self.new_value(INT) for _ in outer])
        else_block = self.new_block([self.new_value(INT) for _ in outer])
        join_block = self.new_block([self.new_value(INT) for _ in outer])
        self.emit("cond_branch", node[1], operands=[condition] + self.jump_args(outer) + self.jump_args(outer),
                  targets=[then_block, else_block], true_args=len(outer))
        incoming = []
        for block, body in ((then_block, node[3]), (else_block, node[4])):
            self.current, self.terminated = block, False
            self.env = dict(zip(outer, self.blocks[block - 1]["params"]))
            self.statements(body)
            if not self.terminated:
                kept = {name: self.env[name] for name in outer}
                self.emit("branch", node[1], operands=[kept[name] for name in outer], targets=[join_block])
                incoming.append(True)
        self.current = join_block
        self.terminated = not incoming
        self.env = dict(zip(outer, self.blocks[join_block - 1]["params"]))

    def s_while(self, node):
        outer = self.scope_names()
        header = self.new_block([self.new_value(INT) for _ in outer])
        body = self.new_block([self.new_value(INT) for _ in outer])
        exit_block = self.new_block([self.new_value(INT) for _ in outer])
        self.emit("branch", node[1], operands=self.jump_args(outer), targets=[header])
        self.current = header
        self.env = dict(zip(outer, self.blocks[header - 1]["params"]))
        condition = self.condition(node[2])
        header_values = self.jump_args(outer)
        self.emit("cond_branch", node[1], operands=[condition] + header_values + header_values,
                  targets=[body, exit_block], true_args=len(outer))
        self.current, self.terminated = body, False
        self.env = dict(zip(outer, self.blocks[body - 1]["params"]))
        self.statements(node[3])
        if not self.terminated:
            self.emit("branch", node[1], operands=[self.env[name] for name in outer], targets=[header])
        self.current, self.terminated = exit_block, False
        self.env = dict(zip(outer, self.blocks[exit_block - 1]["params"]))


class Module:
    def __init__(self, source_name, functions):
        self.source_name = source_name
        self.spans = []
        self.span_ids = {}
        self.operations = 0
        self.functions = {}
        for index, function in enumerate(functions, start=1):
            if function["name"] in self.functions:
                raise TinyError(*function["span"], f"function {function['name']!r} is defined twice")
            self.functions[function["name"]] = (index, len(function["params"]))
        if "main" not in self.functions or self.functions["main"][1] != 0:
            raise TinyError(1, 1, "a zero-parameter main() is required")
        self.built = []
        for function in functions:
            seen = set()
            for param in function["params"]:
                if param[1] in seen:
                    raise TinyError(param[2], param[3], f"duplicate parameter {param[1]!r}")
                seen.add(param[1])
            builder = FunctionBuilder(self, function["name"], function["params"])
            builder.statements(function["body"])
            if not builder.terminated:
                raise TinyError(*function["span"], f"function {function['name']!r} can finish without returning")
            self.built.append((function, builder))

    def next_operation(self):
        self.operations += 1
        return self.operations

    def span(self, position):
        if position not in self.span_ids:
            self.spans.append(position)
            self.span_ids[position] = len(self.spans)
        return self.span_ids[position]


def netstring(value):
    data = str(value).encode("utf-8")
    return str(len(data)).encode("ascii") + b":" + data + b","


def write_wire(module, module_name):
    out = []

    def put(*values):
        out.extend(netstring(value) for value in values)

    # Header: version 2, schema 1, High stage, revision 1, one required feature.
    put("SUBLANG-WIRE", 2, 1, "High", 1, 1, "core.native64.v2", module_name, module.functions["main"][0])
    put("sources", 1, module.source_name)
    put("spans", len(module.spans))
    for line, column in module.spans:
        put(1, line, column, "")
    put("types", 0, "fields", 0)
    put("profiles", 1, "sublang.startup", 1, "i64-signed", "f64-ieee-rne", "abort", "none")
    put("failures", 1, "test.abort", "abort", "unbound", "noreturn void()", 0, "none", 0)
    put("locations", 0, "aliases", 0)
    # One conservative effect summary: nothing about callees is claimed.
    put("effects", 1, "conservative", 0, 9)
    for kind in ("allocation", "escape", "failure", "exceptions", "memory-read", "memory-write",
                 "synchronization", "observable", "control"):
        put(kind, "unknown", "assumed-conservative", "", "", "", 0, 0, 0)
    put("functions", len(module.built))
    for function, builder in module.built:
        put(function["name"], INT, 0, module.span(function["span"]), PROFILE_STARTUP, EFFECT_CONSERVATIVE,
            "internal", "sublang", "body")
        put(len(builder.values), *builder.values)
        put(len(builder.params))
        for value, param in builder.params:
            put(value, param[1], INT, PASS, 0)
        put(len(builder.blocks))
        for block in builder.blocks:
            put(len(block["params"]), *block["params"])
            put(len(block["ops"]))
            for op in block["ops"]:
                put(op["id"], op["opcode"], op["span"], op["value"], op["type"], "", op["ref"], 0,
                    op["overflow"], op["predicate"], "", op["effect"], op["integer"], 0, 0, "")
                put(len(op["operands"]), *op["operands"])
                put(len(op["operands"]), *([PASS] * len(op["operands"])))
                put(len(op["targets"]), *op["targets"])
                put(op["true_args"])
    put("end")
    return b"".join(out)


def compile_source(text, source_name, module_name):
    functions = Parser(tokenize(text)).program()
    return write_wire(Module(source_name, functions), module_name)


def main(argv):
    if len(argv) != 3:
        print("usage: tiny.py INPUT.tiny OUTPUT.sublang-wire", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as handle:
            text = handle.read()
        name = argv[1].rsplit("/", 1)[-1]
        data = compile_source(text, name, name.rsplit(".", 1)[0])
    except TinyError as error:
        print(f"{argv[1]}:{error}", file=sys.stderr)
        return 1
    with open(argv[2], "wb") as handle:
        handle.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
