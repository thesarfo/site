---
title: "It's Just Parsing"
date: 2026-09-03
excerpt: ""
tags: ["engineering"]
---
A compiler is not that difficult to understand. It just reads what you typed and rewrites it as a to-do list a machine can follow. It's just parsing.

The inspo for this piece comes from chapter 17 of Robert Nystrom's *Crafting Interpreters*, which builds a tiny compiler for math expressions like `2 * 3 + 4`. I originally ran into this while building a database execution engine. Writing its lexer and expression parser meant solving exactly this problem. Any query with arithmetic or conditions like `price * qty > 100` has to be broken into tokens and turned into steps the engine can run in the right order.


The obvious issue here is that machines do not read math and is dumb on purpose. Look at it like a stack of plates. It can put a number on top, take numbers off, and combine the top two. It has no idea what `2 * 3 + 4` means. So someone has to translate. That 'someone' is the compiler. It reads your expression left to right and writes out simple steps for the machine to follow

1. Put 2 down.
2. Put 3 down.
3. Multiply the top two.
4. Put 4 down.
5. Add the top two.

Notice the operator comes after its numbers. The machine needs both plates on the stack before it can combine them. Reordering things this way is half the compiler's job.

The above steps is a postfix notation, also called Reverse Polish Notation. It's the same thing behind the infix-to-postfix problems on LeetCode: Evaluate Reverse Polish Notation, the Basic Calculator series and so on. Turning `2 * 3 + 4` into `2 3 * 4 +` and evaluating it with a stack is what this compiler does.

The only hard part is order of operations. Multiply before add, and so on. The chapter solves this with Pratt parsing, which most CS curricula apparently skip entirely. The idea is that every operator gets a stickiness score. `*` and `/` score 2. `+` and `-` score 1. When the parser finishes a number, it peeks at the next operator and asks one question: does this stick tightly enough for what I'm currently building?

Walk through `2 * 3 + 4`:

1. Read 2. Peek: `*` sticks well, so grab it and parse its right side.
2. On the right side, read 3. Peek: `+` is looser than `*`, so stop here. Finish the multiplication.
3. Back at the top level, peek again: `+` is fine here, so grab it and parse 4. Finish the addition.

One loop and one score table. It handles precedence without a separate function for every level. It is a bit difficult to express the operation in writing but I promise it is not that complex.

This is a working version in Python. The book actually uses C, but the logic is identical. `compile_expr` writes the steps and `run` plays the stack-of-plates machine.

```python
import re

STICKINESS = {'+': 1, '-': 1, '*': 2, '/': 2}
OPCODES = {'+': 'ADD', '-': 'SUBTRACT', '*': 'MULTIPLY', '/': 'DIVIDE'}

def compile_expr(text):
    tokens = re.findall(r'\d+|[-+*/()]', text)
    code = []

    def parse(min_stickiness):
        tok = tokens.pop(0)
        # Step 1: handle whatever STARTS an expression
        if tok.isdigit():
            code.append(f"PUSH {tok}")
        elif tok == '(':
            parse(1)
            tokens.pop(0)                  # skip the ')'
        elif tok == '-':
            parse(3)                       # grab only the next small piece
            code.append("NEGATE")
        # Step 2: keep absorbing operators that stick tightly enough
        while tokens and tokens[0] in STICKINESS and STICKINESS[tokens[0]] >= min_stickiness:
            op = tokens.pop(0)
            parse(STICKINESS[op] + 1)      # parse the right-hand side
            code.append(OPCODES[op])       # operator goes AFTER its operands

    parse(1)
    return code

def run(code):
    stack = []
    for instr in code:
        if instr.startswith("PUSH"): stack.append(int(instr.split()[1]))
        elif instr == "NEGATE":      stack.append(-stack.pop())
        else:
            b, a = stack.pop(), stack.pop()
            stack.append({'ADD': a+b, 'SUBTRACT': a-b,
                          'MULTIPLY': a*b, 'DIVIDE': a/b}[instr])
    return stack[0]

code = compile_expr("2 * 3 + 4")
print(code)       # ['PUSH 2', 'PUSH 3', 'MULTIPLY', 'PUSH 4', 'ADD']
print(run(code))  # 10
```

In contrast to how I started off this piece, compilers are actually difficult to understand but it helps to keep in mind that "It's just parsing".