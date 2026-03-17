---
title: "Backtesting"
date: 2026-03-17
excerpt: "Building a tool that tests trading strategies against historical data"
tags: ["engineering"]
---
I've had a gut feeling about a trade, acted on it, and lost money. Or sometimes, had a great idea, talked myself out of it, and watched it play out exactly the way I imagined?

Both situations share the same root problem. I was making decisions without evidence.

I had been exploring various trading ideas, and I wanted a way to take any trading idea, no matter how simple or complex, and find out, based on historical data, whether it would have actually worked. Which would also free me from a backtest on some paid platform with a black-box algorithm I don't understand. 

So I built one.


### What Even Is Backtesting?

Backtesting means taking a trading strategy and running it against historical price data to see how it would have performed in the past. You're essentially asking: *"If I had followed this exact set of rules every day for the last two years, would I have made money?"*

> Think of it like a flight simulator. A pilot doesn't learn to fly by jumping into a real cockpit on day one, they simulate thousands of hours first. Backtesting is your trading simulator.

The key word there is **rules**. A proper backtest doesn't involve feelings. It's basic logic: IF the price does X, THEN I buy. IF the price does Y, THEN I sell. 

Anyone can look at an old chart and say "I would've bought here and sold there." That's called hindsight bias, and our brains are dangerously good at it. A real backtest forces you to commit to your rules upfront, then shows you the honest results.


### What I Actually Built

The tool I built connects directly to two data sources, Binance for crypto, and Yahoo Finance for stocks, and pulls historical price data for any asset you want. Bitcoin, Ethereum, Solana, Apple, Nvidia, Tesla, the S&P 500 index. If it trades on a major exchange, this tool can test a strategy on it.

It then simulates trading that data across four different strategies simultaneously, as if you had actually been trading in real-time over that period. It tracks every trade, every win, every loss, every fee paid, and at the end, it opens a full visual dashboard in your browser.

For crypto, the tool fetches historical prices directly from Binance, the same prices traders traded at, hour by hour, going back years. For stocks, it pulls directly from Yahoo Finance, daily closes, going back as far as the company has been publicly listed.


### The Four Strategies I Tested

I chose four strategies that represent four fundamentally different ways of thinking about the market. Here's each one in plain English, and importantly, all four work exactly the same whether you're testing crypto or stocks.

### Strategy 1: The Trend Follower

This strategy watches two moving averages of the price, one that reacts quickly to price changes, and one that reacts slowly. When the fast one crosses above the slow one, it's a signal that momentum is building upward, so we buy. When it crosses back down, we sell.

The idea is simple: don't fight the trend. If prices are moving up, be in. If they're moving down, be out.

It works beautifully in markets that trend clearly in one direction(like the Ghana stock exchange). It struggles in choppy, sideways markets where prices keep crossing back and forth with no real direction, racking up fees on false signals.

### Strategy 2: The Contrarian

This strategy uses something called the Relative Strength Index, a number between 0 and 100 that measures how overbought or oversold the market is at any moment.

When the number drops below 30, it means the market has been beaten down hard and fast, possibly too hard. That's our buy signal. When it climbs above 70, the market is running hot and may be due for a pullback, that's our sell signal.

In short: buy when everyone's panicking, sell when everyone's euphoric. Classic contrarian thinking. It works well when markets are bouncing around a range. It gets destroyed in a strong, sustained bull run where "overbought" just keeps getting more overbought.

### Strategy 3: The Range Trader

This one draws a band around the price, an upper boundary and a lower boundary, based on how volatile the market has been recently. When the price falls to the lower edge of the band, it's considered statistically cheap. Buy. When it rises to the upper edge, it's statistically expensive. Sell.

The width of the band automatically adjusts to the market's volatility. In calm markets, the bands are tight. In wild markets, they widen. It's a smart, adaptive approach that assumes prices tend to revert to their average over time.

### Strategy 4: Buy and Hold (The Baseline)

This one does exactly what it sounds like. Buy on day one, hold forever, never sell. No signals, no timing, no cleverness.

I included this because its the baseline every other strategy has to beat. If your fancy strategy returned 30% but Apple stock returned 55% over the same period, you underperformed by doing more work. That's important to know.


### Measuring Performance

After each backtest run, the tool produces six numbers.

| What We Measured | What It Means in Real Life |
|------------------|---------------------------|
| Total Return | Did the strategy make money overall, and how much? |
| Max Drawdown | What's the worst paper loss you'd have sat through? |
| Sharpe Ratio | Was the return worth the stress and risk involved? |
| Win Rate | Out of every trade, how many actually made money? |
| Profit Factor | For every dollar lost, how many dollars were won? |

The metric I pay the most attention to is **Max Drawdown**, because it's the one that tells you whether you'd have had the stomach to stick with the strategy.

A 60% return sounds incredible. But if you lost 45% of your money at the low point before recovering, would you have held on? Or would you have sold in panic at the worst possible moment, locking in a massive loss and missing the recovery entirely? Most people would have sold. The drawdown number forces you to be honest with yourself about that.



After every run, the tool automatically opens a visual dashboard in your browser. One that looks like this

![Dashboard](../../../public/backtester.png)

The dashboard shows equity curves for all four strategies plotted on the same chart, so you can see exactly where each one pulled ahead or fell behind. A comparison table with every metric side by side. A return vs. drawdown bar chart that makes the risk/reward trade-off immediately visual. And a trade log showing every entry and exit from your best-performing strategy.

The equity curve is the most useful thing on it. Instead of just reading that one strategy returned 18% and another returned 23%, you can see the actual journey, how they behaved during dips, how quickly they recovered, where they diverged. That context changes how you feel about the numbers.

The buy & hold line runs as a dashed grey baseline across the whole chart. Every other strategy is always being measured against it. If a strategy's line stays above that baseline for the entire period, it genuinely outperformed doing nothing. If it dips below, you have your answer.


Each of the four strategies had periods where it was the clear winner, and periods where it was the worst performer. The market environment matters enormously. And it requires zero effort. This is both humbling and useful to know, and it applies just as much to Apple stock as it does to Bitcoin. I noticed that the contrarian strategy had the most consistent results across different conditions. It wasn't always the best, but it was rarely the worst. That kind of reliability has real value. The same strategy that works well on Bitcoin's volatile swings can completely fall apart on a slow-moving blue chip stock. Testing both side by side makes this immediately clear.

Also, past performance genuinely does not predict future performance. I cannot stress this enough. A strategy that crushed it from 2022 to 2023 may be completely wrong for 2025 market conditions. This tool helps you understand *why* a strategy works, so you can judge for yourself whether those conditions still apply.


Before you act on any trading idea, whether it's a tip from a friend, something you saw on social media, or your own gut feeling, ask yourself: has anyone actually tested this? Is there evidence that this approach works over time, across different market conditions?

If the answer is no, then you're gambling instead of trading.

A backtester doesn't guarantee future profits. Markets change, and what worked yesterday may not work tomorrow. But it does give you something invaluable: the ability to ask hard questions of your own ideas before the market asks them for you.

The traders who consistently do well over the long run aren't necessarily smarter than everyone else. They're more systematic. They test before they trade. They know why their strategy works, not just that it worked last month. And when it stops working, they notice quickly because they're paying attention to the right numbers.

That's the mindset this tool has reinforced for me, more than anything the numbers themselves showed.