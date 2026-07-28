---
title: "Replication"
number: 5
book: ddia
---

Replication = copies of the same data on multiple machines. Purpose: lower latency, fault tolerance, more read throughput. The tension: network is slow and unreliable, so every scheme is a tradeoff between consistency, availability, and latency.

**Single-leader.** One node takes all writes; followers apply them in order. Synchronous replication guarantees followers are current but breaks if a follower is down. Asynchronous is fast but loses writes on leader crash. Semi-synchronous (one sync follower, rest async) is the practical compromise.

Failover is hard. Detecting dead leader, electing a new one, preventing split-brain, all fraught. Replication log options: statement-based (breaks on non-deterministic functions), WAL shipping (tight coupling to storage format), logical/row-based (portable, best for change data capture), trigger-based (flexible but slow).

**Replication lag.** Async replication means followers lag behind. Three anomalies:
- Reading your own writes: user writes, then reads from a lagging follower and doesn't see it. Fix: route self-reads to leader for a short window.
- Monotonic reads: user sees data move backward by hitting different replicas. Fix: sticky sessions.
- Consistent prefix reads: user sees a reply before the original comment because writes arrived out of order. Fix: route causally related writes to the same partition.

**Multi-leader.** Multiple nodes accept writes. Useful for multi-datacenter, offline apps, collaborative editing. The pain is write conflicts. Avoid them when possible (route all writes for a record to the same leader). When unavoidable: last-write-wins (simple but loses data), CRDTs (mathematically convergent for specific types), custom merge logic. Topologies: circular (fragile), star (fragile), all-to-all (robust but needs dedup and ordering).

**Leaderless (Dynamo-style).** Any replica accepts writes. Consistency via quorum: write to N nodes, wait for W acks; read from N nodes, wait for R. If W+R > N, reads see the latest write. But edge cases (sloppy quorums, hinted handoff, concurrent writes) erode confidence. Version vectors detect concurrent writes; application must resolve them.

Takeaway: single-leader is simplest. Multi-leader adds latency at the cost of conflict resolution. Leaderless adds availability at the cost of consistency. None of them eliminate lag; the question is which anomalies your application can tolerate.
