---
title: "PostgreSQL Query Processing Pipeline"
date: 2026-06-21
excerpt: "On what happens in the 3ms before PostgreSQL returns your result."
tags: ["engineering"]
image: "/og-postgres-pipeline.png"
---
You type `SELECT name FROM users WHERE id = 1` and hit Enter. A moment later, you have your result. It often feels like an instant process but PostgreSQL passed that string through five different subsystems before a single row came back. 

When you connect to PostgreSQL, it spins up a full dedicated OS process just for you, forked from the master process called the [postmaster](https://www.postgresql.org/docs/current/app-postgres.html). This is a deliberate design choice: if your backend crashes, everyone else keeps going. The downside is that each connection consumes real memory, typically 5-10 MB baseline, before any query data. This is why connection poolers like [PgBouncer](https://www.pgbouncer.org/) matter so much. For apps opening a new connection per request, that overhead adds up quickly.

That backend process sits in a loop, waiting for queries, and when one arrives, it runs it through five stages in sequence:

**Parser, Analyzer, Rewriter, Planner and Executor**

Each stage takes what the previous one produced and transforms it into something more useful. Let's follow our query through.



### The Parser

The parser only cares about one thing: whether the query it received is valid SQL. It does not touch the database at all.

First of all, a [**lexer**](https://en.wikipedia.org/wiki/Lexical_analysis) splits the query string into tokens. `SELECT name FROM users WHERE id = 1` becomes a stream of recognized pieces: `SELECT`, `name`, `FROM`, `users`, `WHERE`, `id`, `=`, `1`. Each token is classified, keyword, identifier, integer constant and operator.

Then a **parser** takes that token stream and checks whether those pieces fit together according to PostgreSQL's grammar rules. If they do, it builds a [parse tree](https://en.wikipedia.org/wiki/Parse_tree), a structured object representing the shape of the query: a target list, a FROM clause and a WHERE clause.

The key point is that the parser would happily produce a valid parse tree for `SELECT name FROM users` without complaining. It doesn't know whether `users` exists. The parse tree just records that you asked for a column called `name` from something called `users`.

This is probably why PostgreSQL errors split so cleanly. `syntax error at or near "X"` is the parser complaining about structure. `column "X" does not exist` comes from the next stage.



### The Analyzer

The analyzer walks the parse tree and consults the [system catalogs](https://www.postgresql.org/docs/current/catalogs.html) which are internal tables that describe everything in your database, to resolve every name to something concrete.

It builds something called a **range table**: a numbered list of every relation the query touches. `users` (a string) becomes entry #1 in that list, with the actual internal object ID of that table. From here on, the string "users" disappears. Everything is an ID.

Column references get the same treatment. `name` in the parse tree is just a string. The analyzer looks it up, finds it's column #2 in relation #1, and records what type it is. This produces a `Var` node, not "name", but "column 2 of relation 1, type text."

It also does type checking. If you write `id = 'hello'` when `id` is an integer, the analyzer looks for a compatible cast. If one exists, it inserts it silently. If not, you get `operator does not exist: integer = text`.

Functions and aggregates get resolved here as well. Something like `count(*)` has to be identified as an aggregate rather than a regular function, because aggregates behave differently throughout planning and execution. The analyzer makes that call.

The output is a richer version of the parse tree: same shape but with resolved names, typed expressions and numeric references instead of strings.



### The Rewriter

This stage applies transformation rules stored in a system catalog called [`pg_rewrite`](https://www.postgresql.org/docs/current/catalog-pg-rewrite.html).

The most common use is **views**. A view is just a SELECT rule stored in `pg_rewrite` with the special name `_RETURN`. When you create a view:

```sql
CREATE VIEW active_users AS
SELECT * FROM users WHERE active = true;
```

PostgreSQL stores a rule that says "when someone queries `active_users`, substitute this SELECT instead." When you later query the view, the rewriter sees `active_users` in the range table, finds its rule, and swaps the view reference out for the underlying query, all before the planner ever gets involved.

This means views have **zero inherent overhead**. After rewriting, the planner sees a query against the base table, the same as if you'd written it directly. It can use indexes, push filters down, do everything it would do otherwise.

There are two rule types beyond views:
- **INSTEAD rules** replace the original operation entirely, useful for making non-updatable views accept writes
- **ALSO rules** add additional operations alongside the original, used for things like audit logging (INSERT into the log table whenever something is INSERTed into the main table)

[**Row-level security**](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) also happens here. If a table has RLS policies enabled, the rewriter injects those conditions directly into the WHERE clause before the planner sees anything. By the time the planner is involved, security rules are already wired in as if you'd written them yourself.

However, views can hurt you when their structure prevents optimization. If a view contains an aggregation, filters applied after the view can't reach inside it, the aggregation has to run first. Similarly for views with DISTINCT or LIMIT. The planner optimizes what the rewriter gives it; it can't un-aggregate something.



### The Planner

The planner then takes the query tree and has to decide the best way to retrieve the data. For a primary key lookup, there's not much to decide. But for a join of several tables with filters and aggregations, there can be hundreds of thousands of possible execution strategies. The planner has to pick one.

It works in two phases. First, it generates **paths**, lightweight candidate strategies for each relation and join. Paths just store cost estimates and key properties. For scanning `users`, it might generate three paths: a sequential scan, an index scan on the primary key, and a bitmap index scan. For each path, it calculates a cost.

Then it converts the cheapest path into a full **plan** which will be the detailed execution tree the executor actually runs.

**The cost model**

Costs are unitless numbers built from configurable parameters:

- Sequential page read costs **1.0** (the baseline)
- Random page read costs **4.0** (seeking to random pages is slower)
- Processing one row costs **0.01**

So reading a million-row table sequentially might cost `10,000 (pages) + 10,000 (rows at 0.01)` = 20,000. An index scan on the same table for 15 matching rows might cost 50, so the index wins.

Every cost has two parts: **startup cost** (work before the first row appears) and **total cost** (work to return all rows). A sequential scan has zero startup cost, it can start returning rows immediately. A hash join has high startup cost because it needs to build the hash table before returning anything. This distinction matters for `LIMIT` queries: if you only need 10 rows, a plan with low startup cost is often better even if its total cost is higher.

**Statistics**

All of this only works if the planner knows something about your data. It reads statistics from [`pg_statistic`](https://www.postgresql.org/docs/current/catalog-pg-statistic.html), updated by `ANALYZE`, to answer questions like: how many distinct values does `customer_id` have? What's the distribution of values in `total`? Are values in `created_at` correlated with their physical storage order and so on

These statistics directly determine row count estimates. If the planner thinks a filter matches 15 rows but it actually matches 80,000, it'll choose completely the wrong strategy. This is the #1 cause of bad query plans.

**Access methods**

Three main ways to read a table:

- **Sequential scan**: Read every page in order. Cheap per page. Good when you need most of the rows, or the table is tiny.
- **Index scan**: Use a [B-tree](https://en.wikipedia.org/wiki/B-tree) index to find matching row locations, then fetch each row from the heap. Good for selective conditions where only a small fraction of rows match. Each fetch is a random I/O, which is why the planner penalizes random reads at 4×.
- **Bitmap index scan**: Build a [bitmap](https://en.wikipedia.org/wiki/Bitmap) of which pages contain matching rows, then scan just those pages in order. Sits between the two: more selective than seq scan, more sequential than index scan. Especially useful when multiple indexes can be combined (OR conditions).

**Join algorithms**

When two tables need to be joined, the planner picks among three algorithms:

- [**Nested loop**](https://en.wikipedia.org/wiki/Nested_loop_join): For each row in the outer table, scan the inner table for matches. It is simple, but O(N×M) without an index. If the inner table has an index on the join key, it's O(N × log M), often perfect when the outer table is small.
- [**Hash join**](https://en.wikipedia.org/wiki/Hash_join): Build a hash table from the inner table, then probe it for each outer row. O(N+M) time. Requires memory (work_mem) for the hash table. Falls back to disk-based batching if too large. Best for equi-joins on large tables.
- [**Merge join**](https://en.wikipedia.org/wiki/Sort-merge_join): Both inputs sorted on the join key, then merged. O(N log N + M log M) if sorting is needed, O(N+M) if already sorted. Good when both sides can be sorted cheaply or come pre-sorted from an index.



### The Executor

The executor does the actual work by taking the plan tree and running it.

It uses what's called the [**Volcano model**](https://en.wikipedia.org/wiki/Volcano_(database)) (also called the iterator or demand-pull model). Each node in the plan tree is an iterator: it can be initialized, asked for the next row, and cleaned up. The root node asks its child for a row. The child asks its child. This cascades down until a leaf node, a table scan, fetches real data from disk and passes it back up. So data flows up and control flows down.

Execution happens in three phases:

1. **Init**: Traverse the whole plan top-down, calling `ExecInitNode` on each node. Allocate memory, open relations, set up hash tables and acquire locks. Nothing is read yet.

2. **Execute**: Call `ExecProcNode` on the root. This pulls a tuple, which cascades down the tree. Then it repeats untila there are no more rows or the client stops asking.

3. **Cleanup**: Traverse top-down again, calling `ExecEndNode`. It frees sort buffers, close relations and release locks.

The volcano model is naturally lazy. A `LIMIT 5` stops after 5 rows. The part of the plan tree below never processes row 6. This is why index scans are so efficient for `LIMIT` queries, they stop as soon as enough rows come back.


It is also worth noting that some nodes need to hold everything before they can return anything. Every node cannot pass rows up as it goes. Sort needs all the input before it can return the first row in order. HashJoin needs the full hash table built before it can probe anything. Aggregate has to see every row before it can produce a count. These nodes all consume [`work_mem`](https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-WORK-MEM), a per-operation memory budget that defaults to 4MB.

When a node's data grows past that limit, PostgreSQL spills to disk using temporary files. The query still finishes, just much slower.

One thing to keep in mind: `work_mem` is per operation, not per query. A query with three sorts running can use up to 3× `work_mem` at once. Raising it helps sort-heavy queries, but across many concurrent connections the memory adds up fast.


### Now look inside it

Every node you just traced through the pipeline shows up in `EXPLAIN` output. The plan tree the planner built is exactly what the executor ran, and `EXPLAIN` lets you read it.

`EXPLAIN` shows you the plan without running the query:

```
Index Scan using users_pkey on users  (cost=0.29..8.30 rows=1 width=32)
  Index Cond: (id = 1)
```

That `cost=0.29..8.30` is startup..total. `rows=1` is the estimated row count. `width=32` is average row size in bytes.

`EXPLAIN ANALYZE` actually runs it and layers real timing on top:

```
Index Scan using users_pkey on users  (cost=0.29..8.30 rows=1 width=32)
                                      (actual time=0.025..0.031 rows=1 loops=1)
```

When estimated rows and actual rows diverge, that's the planner making decisions off bad statistics. Running `ANALYZE` refreshes them.

You can also pass `EXPLAIN (ANALYZE, BUFFERS)` to see how many pages were read from disk vs. the buffer cache, which is useful for separating I/O problems from CPU problems.

One more thing to watch: if `EXPLAIN ANALYZE` shows `Rows Removed by Filter: 79,843`, the executor read and threw away 79,843 rows looking for matches. That's real work that produced nothing. A high number there, combined with high time on that node, usually means a missing index.



### The point of all this

All what I have stated above are probably useless to you on face value, but knowing the five stages give you a framework for reading error messages and slow queries.

Syntax errors are from the parser, "Does not exist" is from the analyzer. Wrong data coming back from a view might be a rewriter artifact, you can check `pg_rewrite` to see what rules exist on the relation. Slow queries however are almost always the planner or executor.

For slow queries, `EXPLAIN ANALYZE` is the primary tool. Look at:
- **Estimated rows vs. actual rows**, large divergence means stale statistics, run `ANALYZE`
- **Which join algorithm was used**, if it picked nested loop on a large table, it probably underestimated row counts
- **Which access method**, sequential scan on a large table with a selective filter usually means a missing index
- **Rows removed by filter**, lots of discarded rows means work is being done that an index could avoid
- **Time per node**, where is the actual time going?

Understanding this pipeline won't fix every problem of yours but at least it will tell you where to look.

END.
