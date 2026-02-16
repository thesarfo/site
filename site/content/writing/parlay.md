---
title: "Building a Value-Betting Parlay Automator"
date: 2026-02-14
excerpt: "Working on a tool that auto-places parlays based on an expected value."
tags: ["engineering"]
image: "/parlay-cover.png"
---
I built a tool that logs into my sportsbook, scrapes the available matches, scores selections by expected value, and places a single parlay, either from value picks when I have probabilities, or from a simple “favorites” rule when I don’t.

Placing a parlay by hand is repetitive. I log in, browse events, compare odds to whatever I think the true chances are, pick legs, open the slip, set the stake, place. Doing that in a disciplined way, only when my edge is positive, is even more tedious. I wanted the full loop automated: one run that discovers events, scores them, builds one parlay, and places it. No manual work after the first setup.

I also wanted it to work even when I don’t have a probability model; that is, my own estimates of the true chance of each outcome (e.g. 45% home win, 30% draw, 25% away), whether from stats, a tipster, or my own analysis. So the design had to support two modes: value betting when I feed in those probabilities from a file, and a fallback that still runs end-to-end by auto-picking legs, one “favorite” per event, so the pipeline never just dies with no data. That constraint shaped a lot of the architecture.


The system is a straight pipeline. Config and credentials load first, then we log in, then we scrape events and odds, then we match those to a probability file, then we filter by expected value and build one parlay, and finally we place it via the live site. Each stage consumes the output of the previous one. The only thing that flows through the whole pipe is a list of *selections*: one kind of record that starts as “event + market + outcome + odds” and gets enriched as it goes, the scraper adds enough info to find the same odds on the page later, the probability layer attaches a probability, the value layer attaches an EV. That made reasoning about the pipeline simple: at any stage you’re just transforming a list of selections.

I kept all the browser and file I/O in three places, auth, scraper, bet slip, and left the probability matching, EV calculation, and parlay building as pure logic over that list. So the brain of the system doesn’t depend on a live site or a real file; I can test the math and the selection logic with sample data.

Here’s the pipeline as a diagram:

![architecture](/parlay-architecture.png)

Data flows top to bottom: one list of selections gets enriched at each stage, and the probability file is a side input used only in the matching step.


## Technical Choices

I used a browser-automation library. The whole pipeline runs in one flow from start to finish so I didn’t have to worry about mixing sync and async or which thread the browser lived on.

Config is split: one file for behavior (thresholds, paths, delays, max legs) and one for secrets (phone, password, base URL). No secrets in the repo; the app loads both and merges. Probabilities come from a file rather than an API. I did that on purpose: the file is easy to version, inspect, and generate from a spreadsheet or another script, and it keeps the core logic free of network calls. If I ever plug in a tipster feed or an odds API, it can write the same file (or a small adapter can), and the pipeline doesn’t need to change.


## The Math

Value betting here is just one formula. For a single selection, expected value (per unit staked) is:

$$
\text{EV} = p \cdot \text{odds} - 1
$$

where $p$ is your estimated probability (0–1) and the odds are decimal. If that’s positive, you have an edge under your model. The pipeline computes this for every selection that has a matched probability, keeps only those above a configurable threshold, sorts by EV, and then builds the parlay from that list (one leg per event, up to a max). So the “value” path is explicitly grounded in that formula, no black box.

Parlay odds are just the product of the leg odds. So for three legs at 1.80, 2.00, and 2.20, the combined odds are 7.92. I use that for logging and sanity checks; the book's slip shows the same. Stake is fixed for now (or a future "percent of balance"). I came across [Kelly criterion](https://en.wikipedia.org/wiki/Kelly_criterion) while building this, which offers a principled way to size bets based on edge, but properly sizing a parlay with Kelly means modeling the joint distribution of the legs. I wanted to ship something understandable first, so I kept stakes simple. Kelly can sit on top later as a step that takes EV and outputs a stake.

When there’s no probability file or no positive-EV selections, the fallback is an auto parlay: group scraped selections by event, take the favorite (lowest odds) per event, sort those and take the first N. I just added this so that the bot always has something to do.


## Other Decisions

**Session persistence.** I added optional cookie save so that after a successful login we can restore session on the next run and skip the login form. The trade-off is that cookies can go stale if you log out elsewhere or the site invalidates them. So the code treats “load cookies, hit the site, look for a logged-in indicator” as a best-effort shortcut; if we don’t see it, we fall back to full login. I’d keep it, fewer logins in normal use is worth the occasional re-auth.

**One parlay per run.** Each run produces at most one parlay and one “place bet.” That keeps the mental model simple: no tracking multiple slips or combinations, and exit codes map cleanly to “did we place or not.” The downside is that when there are many value legs we only use a subset (top by EV, one per event, capped). If I ever need multiple parlays or more single bets, I’d treat that as a separate design, different filters or multiple runs rather than overloading this pipeline.

**Centralized page structure.** All the rules for “where to find things on the page” live in one place: login inputs, event rows, odds buttons, slip, stake field, place bet. When the site changes, I only touch that file; the rest of the code doesn’t care about the exact rules. The cost is that nothing automatically tells you when a rule breaks, you find out when you run it (or when you add a small end-to-end check). I’m okay with that for a personal tool; for something shared I’d add a minimal smoke run or a recorded session to catch breakage earlier.

**Probability source as a file.** I already said why I like it: no network in the core, easy to test, and any upstream (spreadsheet, model, tipster) can emit the same format. The only downside is staleness if the file isn’t refreshed before a run, which is fine for a scheduled job that generates the file first or for manual runs where you control when the file is updated.

**Scraper strategy.** I prefer scraping the events listing (e.g. football) where each row has multiple odds (1X2, etc.). For each row we parse teams, league, and odds and store a bit of “where to click” (row index, odds index) so the bet slip can click the same elements later. Only when the listing doesn’t give enough do we open event detail. That keeps runs fast when the listing is enough, but it ties us to the current layout; if the site restructures, we might need to lean more on detail-page scraping. So far the flexible rules and fallbacks have been enough.


**Matching probabilities to selections.** I normalize team names, league, market, and selection (lowercase, collapse spaces) and build a composite key. We try full key first, then without league, then a linear scan for same teams + market. That tolerates small spelling and formatting differences. The risk is ambiguous matches (e.g. same team name in two leagues); for a single book and consistent naming it’s been fine. If I ever aggregate multiple sources I’d tighten that (e.g. league or competition ID in the key).


The only first-class entity in the pipeline is a *selection*: event id, event name, home/away team, league, market, selection name, odds, and then optional fields that get filled in as it moves, probability (from the file), EV (from the value step), and “where to click” (from the scraper so the bet slip knows what to click). The scraper fills the base fields and “where to click”; the probability layer attaches probability by matching on teams and market; the value layer computes EV and filters; the parlay step takes the filtered list and picks up to N legs (one per event); the bet slip uses “where to click” and stake to drive the browser. No extra data shapes or mappers, just one structure getting richer at each stage.


## What to Expect

When everything lines up, you get one parlay placed per run, either from value selections (when you have probabilities and EV above threshold) or from the auto-parlay rule. Login is automated; with cookies, most runs skip the form. Stake and leg count come from config, and combined odds are logged so you can check the slip.

Things that can go wrong: the site changes and the “where to find things” rules break (inherent to automating a third-party UI); the events page doesn’t load or returns no rows (region, maintenance, etc.) so the scraper gives you nothing and we exit without placing; or “place bet” fails because of min stake, max payout, or market suspension, we try to capture visible errors but it’s best-effort. We also filter out non-match rows (section headers, dates, times) so the parlay only uses real team-vs-team events; if the site adds new header formats we might need to extend that filter. And of course automated use may violate the book’s terms of service; I treat this as personal education and experimentation, and I don’t run it in a way that would put an account I care about at risk.


I’m happy with the pipeline as it is: one clear data structure, explicit math, and a fallback that doesn’t require a model. If I extend it, the next pieces would be Kelly (or fractional Kelly) stake sizing once I’m willing to model parlay dependence; reading balance from the UI to support “percent of balance” stakes; and maybe tipster or odds-API adapters that write the same file so the pipeline stays unchanged. I could also add a minimal end-to-end run or a recorded session to catch rule breakage earlier. For now it does what I built it for, login, scrape, score, build one parlay, place bet, and the rest is optional.

> The "SportsBook" mentioned above is Sportybet. And the use of this tool violates their Terms of Service, therefore, I will not make the code publicly available. I built it for personal experimentation and to automate a repetitive workflow; it is not a profit guarantee. 
