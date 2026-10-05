---
title: "Estimating row counts"
date: 2026-10-05
excerpt: "How the engine estimates how big each step of a query is, and the experiment where I broke the guesses on purpose."
tags: ["engineering"]
series: query-optimizer
part: 3
---
Ask a database which of two plans is faster and it can't just run both to find out. It has to guess how many rows each step will produce, and pick based on that.

The optimizer I'm building does the same. This part is about how it guesses, and about the table where I made the guesses wrong on purpose. Before anything used them, I wanted to measure them.

`ANALYZE` reads every row of a table and writes down facts about each column: how many NULLs, how many different values, the smallest and largest, and the values that show up most. For number columns it also keeps a rough picture of how the values are spread out, called a histogram. It reads everything instead of sampling, because my tables are small and I wanted numbers I could check exactly.

The histogram cuts the values into 32 groups that each hold about the same number of rows. To guess how many values are below 50, find the group 50 falls in and assume the values are spread evenly inside it. The very common values are kept out. A value that makes up 30% of the table would swamp everything else, so those are listed exactly.

From there, every kind of condition gets a rule of thumb:

- `col = value`: if the value is common, use its exact share. Otherwise share out what's left evenly among the rarer values.
- `col > value`: count the common values that match, then read the rest off the histogram.
- `A AND B`: multiply the two shares, which assumes the two conditions have nothing to do with each other.
- `A OR B`: `a + b - a×b`.

Two cases needed their own handling. `x >= 300 AND x <= 600` is one range, not two conditions. Multiplying 0.70 by 0.60 gives 0.42 when the real answer is 0.30, so a lower and an upper bound on the same column are combined as a single range. And `x = 1 OR x = 2` can't both be true for one row, so those shares just add.

`EXPLAIN ANALYZE` prints the guess next to the real count for every step, with a number I call the q-error: how many times off the guess was. Ten against a hundred scores 10, and so does a hundred against ten. Too high and too low are equally wrong.

On evenly spread data the guesses were boringly good. So I broke them on purpose.

I built a table where the city decides the country, so every Accra row is in Ghana. Each column on its own was guessed almost perfectly. Together they weren't:

| Query | Independent data | City decides country |
|---|---:|---:|
| `city = 'Accra'` | 1.00 | 1.02 |
| `country = 'Ghana'` | 1.00 | 1.00 |
| `city = 'Accra' AND country = 'Ghana'` | 1.05 | 10.39 |
| `city = 'Accra' AND country = 'Nigeria'` | 1.10 | 94.49 |

Those are q-errors. The third row is off by ten, almost exactly the number of countries, because the estimator multiplies 1/30 by 1/10 as if the columns had nothing to do with each other.

![Bar chart of the guess error for four queries. Unrelated columns stay near 1×. When the city decides the country, the guess is off 10× for Accra AND Ghana and 94× for Accra AND Nigeria.](/blog/query-optimizer/qerror.svg)

The last row is the one I keep thinking about. Nobody in Accra is in Nigeria, so the real answer is zero rows. The estimator guesses 94. When I made one city dominate the table, it guessed over a thousand rows for a query that returns nothing.

I left it broken. The tests pin those numbers, so they can't get better by accident. Fixing it properly means keeping statistics on pairs of columns, which is a project of its own. For now it's a measured failure, and that's more useful to me than a hidden one.

With guesses in hand, the engine can finally choose between plans.
