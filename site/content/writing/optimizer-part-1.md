---
title: "What an optimizer does"
date: 2026-10-05
excerpt: "What a query optimizer is, why NULL makes it hard, and the rule everything else bends around: change how a query runs, never what it returns."
tags: ["engineering"]
series: query-optimizer
part: 1
---
I've spent most of my time this year trying to understand how databases work underneath. Storage, query planning, optimizations, pretty much all the things you never see when you write a simple query. And obviously, reading only gets me so far. At some point it's either you've built something, or you just keep nodding at the diagrams.

If you're not sure what happens between typing a query and getting rows back, I wrote about that in [PostgreSQL Query Processing Pipeline](/writing/postgres-query-pipeline). It's a good place to start before this series.

So I set myself a little project checkpoint: build a small SQL database and make the optimizer the focus. It's mostly for fun, but it's also something I'm trying to actively learn from and build on. This series covers the first usable version, one idea per part, and I'll keep adding parts as the project grows. This first part is the basics: what an optimizer is, and the one rule it can't break.

So first of all, what is an optimizer?

SQL queries tell the database what you want, but they never really say how to get it. Take this query, for example:

```sql
SELECT u.name
FROM users u JOIN orders o ON u.id = o.user_id
WHERE u.country = 'Ghana' AND o.amount > 100
```

The engine inside the database turns it into a plan, which is a tree of steps. The plan that follows the query word for word looks something like this:

```
Project[name]
  Filter[country = 'Ghana' AND amount > 100]
    Join[users.id = orders.user_id]
      Scan[users]
      Scan[orders]
```

If you read it from the bottom, right, it pairs every user with every order, and then it throws away the pairs that don't pass the filter. That's a lot of pairing. A better plan should filter first, like this:

```
Project[name]
  Join[users.id = orders.user_id]
    Filter[country = 'Ghana']
      Scan[users]
    Filter[amount > 100]
      Scan[orders]
```

It's the same answer, but far less work. Finding plans like the second one is the optimizer's job.

![The same query as two plans. Run as written, the join pairs 1,000 users with 4,000 orders, 4,000,000 pairs. With the filters moved below the join, it pairs 50 users with 400 orders, 20,000 pairs.](/blog/query-optimizer/plans.svg)

The optimizer sits in the middle of a longer trip. Here's the whole thing, with the parts that are the optimizer's job in orange:

![A query's trip: parse, bind, plan, rewrite, estimate, choose, run.](/blog/query-optimizer/pipeline.svg)

Now, an optimizer may change how a query runs, but it must never change what the query returns.

It sounds obvious until you write the rules. Almost every decision in this project bends around that one sentence, so I tried to build a safety net before I built the optimizer, and most of this series is about the net.

The first trap is how SQL handles NULL. In SQL, comparing anything to NULL doesn't really give you true or false, it gives you unknown, and a `WHERE` clause throws away the rows that are unknown.

So `x = x` is not always true. If `x` is NULL, it's unknown. An optimizer that sees `x = x` and replaces it with `TRUE` has quietly changed the results. I've known this for years, and it still felt like a trick question the first time a rule actually had to respect it.

The first thing I wrote for the expression evaluator was the truth tables for `AND`, `OR` and `NOT` with three values. Then I made two lists. First, rewrites that stay true even when a value is NULL:

- `x AND FALSE` is `FALSE`, whatever `x` is.
- `x OR TRUE` is `TRUE`.
- `x AND x` is just `x`.

And rewrites that look reasonable and are wrong:

- `x = x` is not `TRUE`.
- `x AND NOT x` is not `FALSE`.
- `x OR NOT x` is not `TRUE`.

Each wrong one has a test that checks the rule leaves it alone. Tests for what a rule must not do turned out to be as useful as tests for what it does.

There's a tradeoff about errors too. Here's a smaller question that took me a while: should `FALSE AND (1/0 = 1)` raise a division error?

I decided yes, because technically both sides of an `AND` are always evaluated. The reason is order. If only the left side is evaluated, whether a query fails depends on which order the optimizer puts the conditions in, and I don't want a rewrite to decide that.

But then I wrote a rule that turns `x AND FALSE` into `FALSE`. That throws `x` away, and the error inside `x` goes with it. Real databases do this too. When a query has an answer, the answer never changes. I'd rather say that plainly than pretend it doesn't happen.

One early decision saved me a lot of pain later. Binding is the step that turns names into things. `u.id` becomes "the first column of the users table". I gave every column in a query its own number, and after binding the query never mentions a name again.

The reason is a table joined to itself:

```sql
FROM users a JOIN users b ON a.id = b.id
```

`a.id` and `b.id` are the same column of the same table, but they mean different things in the query. If rewrites track names, they mix the two up, and the bugs only appear on self-joins. With numbers, `a.id` is column 0 and `b.id` is column 3 and nothing can get confused.

Then there's the rule that made the demo query fast. It splits a filter at its `AND`s and moves each part as low in the plan as it can go. `country = 'Ghana'` only needs the users, so it goes to the users side. `amount > 100` only needs the orders. A part that needs both tables, like `users.age > orders.amount`, has to stay above the join.

Two things I had to be careful about.

**Outer joins.** There's no `LEFT JOIN` yet, but I wrote the rule to refuse any join type it doesn't know. With a left join, users with no orders stay in the result, filled with NULLs. A filter on the orders side behaves differently before the join than after it. A test builds a join with a made-up type to check the rule refuses.

**Errors again.** A filter that runs before the join now sees rows the join would have dropped. If it can fail, like `1 / x`, it can now fail on a row that never joined. The rows a query returns don't change, but this is something I wrote down instead of hoping nobody notices.

A second rule gave it trouble. It drops columns nothing above needs, so the join copies narrower rows. It does this by adding a step between a filter and its join. But the pushdown rule only recognises a filter sitting directly on a join. Run together, the column rule could hide the join and block the pushdown on queries with three tables.

The fix wasn't clever. I split the optimizer into stages. Each stage runs until nothing changes, then the next one starts. The column rule runs last, after everything else has settled.

A promise like "never change the answer" doesn't mean much unless you can check it. Checking it turned out to be the bigger job.
