---
title: "Reliable, Scalable, and Maintainable Applications"
number: 1
book: ddia
---


> "The Internet was done so well that most people think of it as a natural resource like the Pacific Ocean, rather than something that was man-made.", Alan Kay

Modern apps are data-intensive, not compute-intensive. Bottlenecks come from data volume, complexity, and change rate.

**Reliability** = the system keeps working when things break. Faults fall into three buckets:
- Hardware: disks die, networks partition. Mitigation used to be redundancy; today it's software fault-tolerance.
- Software: correlated bugs that crash every node at once. No fix, only mitigation (testing, isolation, monitoring).
- Human: config errors cause most outages. Fix by making the right thing easy and recovery fast.

**Scalability** = can it handle more load? Load is described with parameters (requests/sec, read/write ratio, etc.). Twitter's timeline is the canonical example: pull-on-read is simple but expensive at scale; push-on-write (fan-out) reverses the cost but chokes on celebrities with millions of followers. They do both.

For performance, ignore averages. Use percentiles. p99 matters because one slow backend can hold up everything behind it (tail latency amplification).

Ways to cope: scale up (bigger box), scale out (more boxes), elastic (auto). Stateless services are easy to scale; databases are not.

**Maintainability** is where most money goes. Three principles:
- Operability: ops teams need visibility, automation, and boring predictability.
- Simplicity: accidental complexity kills velocity. Abstractions are the weapon.
- Evolvability: requirements change. Make it easy to change the system.

Back-of-envelope numbers worth remembering: RAM is ~1000× faster than disk seek. Intra-DC round trip is 0.5 ms. Cross-continent is 150 ms.
