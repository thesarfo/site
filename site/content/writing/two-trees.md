---
title: "Navigating a Red/Green Syntax Tree"
date: 2026-07-27
excerpt: ""
tags: ["engineering"]
image: "/rbst.png"
---

How can a syntax tree be immutable and still tell you where every node sits in the source and who its parent is? I set out to explore this by example, writing a small config-language compiler built on the same red/green design [Roslyn](https://github.com/dotnet/roslyn) uses under the hood.

The compiler processes a small configuration language. Each statement assigns a value to a key, values can be expressions, and a key can reference another key:

```
# a tiny config with references and expressions
name    = "web-server"
port    = 8080
timeout = port + 1000
url     = "http://localhost:" + port
debug   = true
```

The compiler runs the same phases a full compiler does: a lexer produces tokens, a parser produces a syntax tree, a semantic model resolves names and checks types, and an emitter produces output. The rest of this article focuses on the syntax tree, because that is where the red/green design applies.

## Why an immutable tree uses two representations

An immutable syntax tree has to satisfy two goals that are in tension:

- **Immutability.** An immutable tree can be shared safely across threads, cached for the lifetime of a process, and passed to many consumers at once without any of them affecting the others.
- **Navigation.** From any node, you need its absolute position in the source text and a reference to its parent, so that tools can report locations, navigate upward, and map nodes back to spans.

These goals conflict. If every node stores its absolute position, inserting a single character near the start of the file changes the position of every node after it. Because the tree is immutable, those positions can't be updated in place, so any edit requires rebuilding the entire tree. If nodes don't store positions, the tree can't be navigated.

The red/green design resolves the conflict by using two representations of the same tree: an internal *green* tree and a public *red* tree.

## Green nodes

A green node is the internal representation. It stores the node's kind, its width, and its child slots. It doesn't store an absolute position or a reference to its parent.

The following code shows the base green node type:

```csharp
internal abstract class GreenNode
{
    public SyntaxKind Kind { get; }
    public int FullWidth { get; }
    public abstract int SlotCount { get; }
    public abstract GreenNode? GetSlot(int index);
}
```

Because a green node has no position and no parent, the same green node can appear in more than one tree, at more than one position, under more than one parent. It represents a shape of code independent of where that shape occurs. The parser builds green nodes from the bottom up, and each node computes its width from the widths of its children.

## Red nodes

A red node is the public representation that your code navigates. Each red node wraps a single green node and adds the two pieces of information the green node omits: an absolute position and a parent reference.

Red nodes are created on demand as you move down the tree. The root node has position 0. When you request a child, the red node computes that child's position by adding the widths of the preceding green children to its own position, wraps the green child at that position, and caches the result:

```csharp
protected SyntaxNode? GetRed(int slot)
{
    var cached = _children[slot];
    if (cached is null)
    {
        var greenChild = Green.GetSlot(slot);
        if (greenChild is not null)
        {
            int offset = 0;
            for (int i = 0; i < slot; i++)
                offset += Green.GetSlot(i)?.FullWidth ?? 0;

            cached = greenChild.CreateRed(this, Position + offset);
            _children[slot] = cached;   // cache the realized child
        }
    }
    return cached;
}
```

The position is derived from green widths rather than stored on the green node. With this design, both goals hold at once:

- **Immutability.** Green nodes are never modified. Red nodes are lightweight views that can be discarded and recreated.
- **Efficient edits.** Changing one token requires rebuilding only the green nodes from that token up to the root. Every green subtree that wasn't changed is reused by reference.
- **Correct positions.** Positions and parents are computed on the red side each time you navigate, so they're always accurate and never become stale.

## Structural sharing

Because green nodes are position-independent, the same green node can be reused across trees while each red node reports the correct, distinct position. The example project demonstrates this by placing one green literal (the number `42`) into two trees, where the second is shifted by leading whitespace, and then reading the node from each tree:

```
green(valueA) is green(valueB)?   True    same green node, reused by reference
red   valueA is red   valueB?     False   distinct red wrappers
valueA.FullSpan = [3..5)
valueB.FullSpan = [10..12)                same green node, different position
```

The green node is shared. The two red nodes are distinct, and each reports the position derived from the widths that precede it.

## Full width and trivia

A token's width includes the whitespace and comments attached to it, which are called *trivia*. As a result, a node's full span (including trivia) is wider than the span of the token text alone. Because trivia is preserved on the tokens, the tree reproduces the original source text exactly.

You can see trivia reflected in the widths when you print the tree:

```
AssignmentStatement  [0..70)
  IdentifierToken  [0..52)  "name"      the leading comment is stored as trivia on this token
  EqualsToken  [52..57)  "="
  LiteralExpression  [57..70)
    StringToken  [57..70)  ""web-server""
```

## Missing tokens and error recovery

When the parser expects a token that isn't present, it reports a diagnostic and inserts a zero-width *missing* token instead of stopping. The slots stay filled and the child indices stay stable, so the tree remains well-formed and can still be navigated.

This behavior is what allows tools to analyze incomplete code. Source that is still being edited is, by definition, often incomplete, and a parser that produced a usable tree only for complete input would fail exactly when a developer needs assistance.

## The semantic model

The syntax tree describes the structure of the source. It doesn't determine what a name refers to or whether an expression is valid. The semantic model provides that information. It builds a symbol table, resolves each reference to the key it names, evaluates expressions, and reports errors that aren't visible in the syntax.

Consider a configuration that parses successfully but isn't meaningful:

```
a = b + 1
b = a - 1        # cycle
host = missing   # undefined key
mix = "x" - 2    # type error
```

All four statements are well-formed, so the parser accepts them. The semantic model reports the problems that only name and type resolution can detect:

```
[0..1):     Cyclic reference involving 'a'.
[71..78):   Undefined key 'missing'.
[107..108): Operator '-' cannot be applied to String and Number.
```

Detecting these requires resolving names to symbols: that `missing` refers to no declared key, that `a` and `b` depend on each other, and that subtraction isn't defined between a string and a number. This is the distinction between code that parses and code that has meaning.

## Emit

After the semantic model resolves and evaluates the configuration, the emitter serializes the result. In this example it produces JSON:

```json
{
  "name": "web-server",
  "port": 8080,
  "timeout": 9080,
  "url": "http://localhost:8080",
  "debug": true
}
```

The value of `timeout` is `9080` because `port + 1000` was evaluated, and `url` includes the resolved port. A production compiler emits IL at this stage instead of JSON, but the phase serves the same role: it turns the fully resolved program into the target output.

The red/green design lets a syntax tree be immutable, inexpensive to edit, and fully navigable at the same time. Green nodes store width and structure but not position, which allows them to be shared across trees and reused across edits. Red nodes add position and parent information and are created on demand as you navigate. Writing a compiler with this design was an effective way to understand the same architecture that supports analyzers, source generators, and refactorings in Roslyn.
