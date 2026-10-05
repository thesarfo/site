---
title: "Checking the answers"
date: 2026-10-05
excerpt: "An answer checker, a fuzzer that shrinks its own failures, and SQLite as a second opinion."
tags: ["engineering"]
series: query-optimizer
part: 2
---
An optimizer that returns the wrong answers faster is worse than having no optimizer. So before I trusted mine, I needed a way to check it. This part is about how I did that.

So I built an answer checker. It runs a query with the optimizer off, which is the plan exactly as written. Then it runs it with all the rules on, then with each rule switched off in turn, then with each rule on alone, then with each join method. Every answer has to match.

![One query is run under six configurations, and the answers are compared. If any differ, the query is shrunk to the smallest one that still fails.](/blog/query-optimizer/checker.svg)

"Match" took thought, because SQL leaves some things open:

- With no `ORDER BY` and no `LIMIT`, I compare the rows, in any order.
- With `ORDER BY`, rows that tie on the sort key can come out in either order. So I compare the sort key values, not whole rows.
- With `LIMIT` but no `ORDER BY`, SQL doesn't say which rows you get. I only compare how many.

If I got this wrong the checker would either cry wolf or sleep through real bugs.

Running each rule alone came from a mistake. I planted a broken rule on purpose to see if the checker would catch it, and it didn't. Another rule had rewritten the query first and hidden the damage. A test that only runs the whole pipeline can hide a bug behind a helper.

Hand-written tests only cover what I thought of. So I wrote a generator that makes random queries: one to three tables, joins, nested `AND`, `OR` and `NOT`, `BETWEEN`, `IN`, sorting, limits. The tables are small and full of NULLs and repeated values, so joins find matches and ties are common. Each query comes from a seed and an index, so any failure can be reproduced from two numbers.

When a query fails, a shrinker cuts it down. It tries dropping the `LIMIT`, the `ORDER BY`, a join, a branch of a condition, a column. It keeps every cut that still fails. A long ugly query comes back as something like:

```sql
SELECT q1.f FROM t3 AS q1 WHERE q1.f AND 0.5 < 0.5
```

You read that and the bug is sitting there.

A clean fuzz run proves nothing until you've watched it catch something. So I planted four wrong rules: one that drops half an `AND`, one that treats `x = x` as true, one that drops a join condition, one that flips a sort. The fuzzer found all four and shrank each to under five lines. Only after that did it mean something that 200,000 random queries passed on the real rules.

The checker only proves the engine agrees with itself. A bug in something both runs share, like the evaluator, would slip past it. So I load every test file into SQLite and check that it gives the answers I expect. 171 records agree. 22 differ, and each has a written reason: SQLite doesn't check types, it returns NULL for division by zero, it switches to floating point when a whole number overflows. A difference with no reason fails the script, and so does a reason that has gone stale. I'd rather keep an honest list than copy SQLite's behaviour.

The tests caught me more often than they caught the engine. The address sanitizer found a use-after-free in one of my own test helpers. Twice I wrote an expected result by hand that was wrong, and each time the engine was right.

The suite also got slow. It took over three minutes, because two tests ran a 1000-user nested loop join for real under the sanitizer. I shrank the data and ran the tests in parallel, and it dropped to 40 seconds. A slow test suite stops getting run, which is worse than a missing one.

That covers whether the answers are right. Whether the plans are good depends on knowing how big things are, and the engine can only guess.
