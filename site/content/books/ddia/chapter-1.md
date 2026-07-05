---
title: "Reliable, Scalable, and Maintainable Applications"
number: 1
book: ddia
---


> "The Internet was done so well that most people think of it as a natural resource like the Pacific Ocean, rather than something that was man-made.", Alan Kay

## Core Idea

Modern applications are **data-intensive**, not compute-intensive. The bottlenecks are usually:
- Amount of data
- Complexity of data
- Speed at which data changes

A data-intensive application is typically built from standard building blocks:

| Building Block | Purpose |
|---|---|
| **Databases** | Store data so it can be found again later |
| **Caches** | Remember expensive operations to speed up reads |
| **Search indexes** | Allow filtering/searching by keyword |
| **Stream processors** | Send messages to another process asynchronously |
| **Batch processors** | Periodically crunch large amounts of accumulated data |

---

## Thinking About Data Systems

Traditionally, databases, queues, and caches are thought of as distinct categories, but the lines are blurring:
- Redis is a datastore *also* used as a message queue
- Kafka is a message queue with database-like durability

Modern applications often stitch multiple tools together with application code, making the developer both an **application developer** and a **data system designer**.

The chapter focuses on three concerns that matter in most systems:
1. **Reliability**, working correctly even when things go wrong
2. **Scalability**, reasonable ways to handle growth
3. **Maintainability**, easy for people to work on over time

---

## Reliability

**Reliable** = the system continues to work correctly even in the face of faults.

- **Fault** = one component deviating from its spec
- **Failure** = the whole system stops working for users
- Goal: build **fault-tolerant** systems that prevent faults from becoming failures

### Types of Faults

#### Hardware Faults
- Hard disks have an MTTF of 10–50 years → a 10,000-disk cluster loses ~1 disk/day
- Traditional fix: **redundancy** (RAID, dual power supplies, backup generators)
- Modern shift: software fault-tolerance over hardware redundancy (rolling upgrades, no downtime)

#### Software Errors (Systematic Faults)
- Harder to anticipate than hardware faults; correlated across nodes → cause more failures
- Examples:
  - A bug crashing every app server on a bad input (e.g. the 2012 Linux leap-second bug)
  - A runaway process consuming shared resources
  - A dependency returning corrupted responses
  - Cascading failures
- No silver bullet, mitigations: careful thinking about assumptions, thorough testing, process isolation, crash-and-restart, monitoring

#### Human Errors
- Studies show operator config errors are the *leading cause* of outages (hardware faults only 10–25%)
- Mitigations:
  - Design APIs/interfaces that make the right thing easy and wrong thing hard
  - Provide sandbox/non-production environments with real data
  - Test thoroughly (unit → integration → manual)
  - Make recovery fast (quick rollback, gradual rollouts, data recomputation tools)
  - Set up detailed monitoring (metrics, error rates = "telemetry")

### Key Insight
> Counterintuitively, it can make sense to *increase* fault rates deliberately (e.g. Netflix Chaos Monkey) to ensure fault-tolerance machinery gets exercised.

---

## Scalability

**Scalable** = a system's ability to cope with increased load.

Scalability isn't a binary label, it's about answering: *"If load grows in this way, what are our options?"*

### Describing Load, Load Parameters

Load is described by **load parameters** (the right choice depends on the system):
- Requests per second (web server)
- Ratio of reads to writes (database)
- Active users in a chat room
- Cache hit rate

**Twitter example (Nov 2012):**

| Operation | Rate |
|---|---|
| Post tweet | 4.6k req/sec avg, 12k peak |
| Read home timeline | 300k req/sec |

Two approaches to home timeline:
1. **Pull on read**, query all people you follow at read time (simple writes, expensive reads)
2. **Push on write (fan-out)**, precompute timeline into each follower's cache at write time (cheap reads, expensive writes: ~345k writes/sec)

Twitter moved from approach 1 → 2 because read rate >> write rate. But celebrities with 30M followers created a problem (30M writes per tweet). **Final approach: hybrid**, fan-out for normal users, pull-on-read for celebrities merged at read time.

### Describing Performance

Two ways to look at load increase:
- Keep resources fixed → how does performance degrade?
- Keep performance fixed → how much do resources need to grow?

**Batch systems** → care about **throughput** (records/sec)  
**Online systems** → care about **response time** (latency the client sees)

> **Latency ≠ Response time.** Response time = service time + network delays + queueing. Latency = time a request is *waiting* to be handled.

#### Percentiles (better than averages)

| Metric | Meaning |
|---|---|
| p50 (median) | Half of requests are faster than this |
| p95 | 95 out of 100 requests are faster than this |
| p99 | 99 out of 100 requests are faster than this |
| p999 | 99.9 out of 100 requests are faster |

**Tail latencies** (p99, p999) matter because:
- Amazon's most valuable customers have the most data → slowest requests → Amazon measures p999 for internal services
- A 100ms increase in response time → 1% drop in sales
- A 1-second slowdown → 16% drop in customer satisfaction

**Head-of-line blocking**: a few slow requests can hold up all subsequent ones behind them → measure response time *client-side*.

**Tail latency amplification**: if a single user request fans out to multiple backend calls, *one* slow backend makes the whole request slow.

#### Approaches for Coping with Load

| Approach | Description |
|---|---|
| **Scale up** (vertical) | More powerful single machine, simpler, but expensive |
| **Scale out** (horizontal) | Distribute load across many smaller machines (shared-nothing) |
| **Elastic** | Auto-add resources when load increases |
| **Manual scaling** | Humans analyze and add capacity, simpler, fewer surprises |

> Stateless services are easy to distribute. Stateful (databases) are much harder, this is why "keep DB on one node until forced otherwise" was conventional wisdom.

Architecture is always application-specific, there's no magic scaling sauce. The right architecture depends on the mix of: read volume, write volume, data size, data complexity, response time requirements, access patterns.

---

## Maintainability

The majority of software cost is **ongoing maintenance**, not initial development. Three design principles:

### Operability, Making Life Easy for Operations

A good operations team:
- Monitors system health and restores service quickly
- Tracks down causes of failures
- Keeps software/platforms up to date
- Anticipates future problems (capacity planning)
- Manages configuration, deployment, security

**Good operability means:**
- Visibility into runtime behavior (monitoring)
- Good automation support
- No dependency on individual machines
- Good documentation and predictable operational model
- Sensible defaults with admin overrides
- Predictable behavior, minimal surprises

### Simplicity, Managing Complexity

As systems grow, complexity slows everyone down and increases the risk of introducing bugs.

Symptoms of complexity:
- State space explosion
- Tight coupling
- Tangled dependencies
- Inconsistent naming
- Performance hacks and special-casing

**Accidental complexity** = complexity not inherent in the problem, but arising from the implementation.

Best tool against accidental complexity: **abstraction**
- Hides implementation details behind a clean façade
- Examples: high-level languages (hide machine code), SQL (hides on-disk data structures)

### Evolvability, Making Change Easy

Requirements never stay the same. Systems must adapt to:
- New facts, new use cases, business priority changes
- New platforms replacing old
- Legal/regulatory changes
- Growth-driven architectural changes

**Agile** at the code level = TDD, refactoring.  
**Evolvability** = agility at the *data system* level, the ease of modifying the system as requirements change. Closely linked to simplicity and good abstractions.

---

### Back-of-Envelope Estimation

> "A crude but efficient quantitative analysis can help you to narrow down the design space considerably.", Martin Kleppmann

These are rough numbers to sanity-check designs before writing code:

#### Latency Numbers Every Programmer Should Know

| Operation | Time | Relative |
|---|---|---|
| L1 cache reference | 0.5 ns | — |
| L2 cache reference | 7 ns | 14× L1 |
| Main memory reference | 100 ns | ~200× L1 |
| Compress 1 KB with Snappy | 3 µs | — |
| Read 1 MB sequentially **from memory** | 3 µs | — |
| Send 1 KB over 1 Gbps network | 10 µs | — |
| Read 1 MB sequentially **from SSD** | 1 ms | ~20× HDD |
| **Round trip within same datacenter** | 0.5 ms | — |
| Read 1 MB sequentially **from HDD** | 20 ms | — |
| **Round trip CA → Netherlands → CA** | 150 ms | — |

Key ratios to remember:
- **Memory vs disk:** RAM is ~1000× faster than seek. Read 1 MB sequentially from RAM in 3 µs vs 20 ms from spinning disk; you can do ~6,700 sequential memory reads in the time of one HDD read.
- **Network within DC ~ SSD:** A round trip in the same datacenter (~0.5 ms) is half the time of reading 1 MB from SSD (~1 ms). Local network is fast, but treat remote calls as roughly as expensive as local disk I/O.
- **Cross-DC is punishing:** 150 ms is 300× the latency of an intra-DC round trip, which changes the entire architecture (async replication, multi-leader, etc.).
- **Seek vs sequential on HDD:** Random HDD seeks are ~10 ms each. Sequential HDD throughput can be ~50–100 MB/s, so you get ~50× more throughput sequentially. This is why LSM-trees write sequentially.

#### How to Use These Numbers

1. **Know the scale of numbers**, not just their values. Is something nanoseconds, microseconds, or milliseconds? Being off by 3 orders of magnitude means the architectural decision is probably wrong.
2. **Estimate with powers of 10.** Don't reach for a calculator. 10^3, 10^6, 10^9 is usually good enough to rule designs in or out.
3. **Use queuing theory intuitions.** If requests arrive at rate λ and each take time S to process, the system can handle throughput up to 1/S. Approaching that limit makes queueing delays explode.
4. **Ask "what is the bottleneck?"** CPU, memory, disk I/O, or network? The bottleneck determines where to spend optimization effort. Everything else is noise.
5. **Amortize.** One expensive operation spread over a million cheap operations may be acceptable. A single disk seek (~10 ms) in a 100 µs request budget dominates; if you can batch or avoid it, everything gets faster.

> Worked example: You want to serve 100,000 req/sec. Each request reads ~100 KB from disk and does ~1 ms of CPU. Disk throughput needed: 100,000 × 100 KB = 10 GB/s → ~100 HDDs or ~10 SSDs (seq read). CPU time: 100,000 × 1 ms = 100 CPU-seconds per second → ~100 cores. Sanity-check passes: you'll need a cluster, not a laptop, but a modest one.

---

## Summary

| Property | Core Idea |
|---|---|
| **Reliability** | Systems work correctly even when faults occur (hardware, software, human) |
| **Scalability** | Strategies to keep performance good as load increases, describe load, measure performance, add capacity |
| **Maintainability** | Operability + Simplicity + Evolvability, make it easy for people to work with the system over time |

No easy fixes exist for any of these, but patterns and techniques recur across systems. The rest of the book explores them layer by layer.
