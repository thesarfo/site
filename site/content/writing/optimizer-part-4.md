---
title: "Choosing a join method"
date: 2026-10-05
excerpt: "A cost model, a hash join, and the benchmarks that surprised me: hashing wins at three rows, and calibrating the constants barely mattered."
tags: ["engineering"]
series: query-optimizer
part: 4
---
A join can run two ways, and which one is faster depends on how big the tables are. The small SQL engine I'm building now picks between them using its own row guesses, and I wanted to know if it picks well.

The rewrites were always safe. Choosing a join method isn't, because it depends on size. So I gave the engine a cost model, which turns a plan into one number for how much work it expects, using the row guesses. The numbers it multiplies by, like what reading a row costs, I copied from PostgreSQL and wrote down that I'd copied them. Only the order of the costs matters, not the values.

Then I wrote the second join method. The simple one, a nested loop, checks every row of one table against every row of the other. A hash join builds a lookup table from one side first, then looks up each row of the other side. It's like indexing a phone book once instead of reading it end to end for every name.

The planner prices both for each join and keeps the cheaper one. It also remembers the loser, so `EXPLAIN VERBOSE` can show what it turned down. A test grows the tables and checks that the choice flips exactly once.

Then the uncomfortable question: are those prices any good for my engine? I ran 30 joins, each three ways, and compared what the model predicted with how long they really took. Checking one pair of rows turned out to cost about the same as handling one row. PostgreSQL's numbers say a row costs four times as much. In my engine, checking a pair builds a new combined row in memory before it tests anything, so it's just as heavy. I changed the number.

The honest part is that it barely mattered. The old, wrong number picked almost as well as the fitted one. The method the model liked best was within 10% of the fastest in 28 of 30 queries. The methods usually differ by so much that the exact numbers only matter when two of them are close, and few of my queries are. I'd have liked a story where calibration fixed everything. This isn't that story, so I wrote it up the way it came out.

The first result surprised me. I expected hashing to need hundreds of rows before it beat the simple join. It needs three. After that the gap grows with the size of the smaller table. With 1000 users against 100,000 orders, hashing is 190 times faster. With 10 users it's only about 3 times, and with a single user the two stay level all the way to a million orders.

![Line chart on a log scale. The nested loop grows with the orders table and reaches about 5 seconds at 100,000 orders. The hash join reaches 27 milliseconds at the same size.](/blog/query-optimizer/e4.svg)

It also matters which side you build the lookup table from. Building it from 1000 users took 259 ms. Building it from a million orders took 357 ms. The model got the direction right, but it understated how much the difference was.

My first experiment was the pushdown. Moving the filter below the join made the demo query 590 times faster. But that was with the slow join. Run it again with a hash join and pushdown is worth about 2 times. Choosing the right join mattered far more than moving the filter, and I only found that out because I went back and ran the first experiment a second time.

Right now it parses SQL, plans it, rewrites the plan, joins tables, keeps statistics, guesses how many rows each step produces, prices the ways to run a join and picks the cheapest. It checks itself against random queries and against SQLite. That's a usable first version, and I've tagged it. About 60% of the planned work is done.

What's missing is the next set of choices. Joins run in the order I wrote them, and every scan reads the whole table. Choosing the join order is the interesting one: with four tables there are many orders, and the wrong one can be slow. Indexes are the other. I'm going to reread the plan before picking, because I'd rather choose than drift into it.

I'll add to this as I go.
