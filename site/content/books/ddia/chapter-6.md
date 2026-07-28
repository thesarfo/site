---
title: "Partitioning"
number: 6
book: ddia
---

Partitioning (sharding) splits a dataset across machines so no single node must hold everything. The hard part: keeping related data together, balancing load, and handling growth.

**Key-value partitioning.** Two strategies:
- Range-based: assign key ranges to partitions. Efficient range scans, but vulnerable to hot spots (timestamps in logs all hit one partition).
- Hash-based: hash the key to distribute uniformly. Eliminates skew but kills range queries. The compromise: compound keys, first part hashed for distribution, second part ordered within each partition.

Hot spots from access patterns (a celebrity on social media) can't be fixed by hashing. Workaround: split the hot key into sub-keys manually.

**Secondary indexes.** Local indexes (per-partition): writes are fast, but reads scatter-gather across all partitions. Global indexes: reads hit exactly one partition, but writes need distributed coordination (usually async).

**Rebalancing.** Three approaches:
- Fixed partitions: pick a large number up front, never change it. Simple, but you must guess right.
- Dynamic: partitions split and merge as data grows. Adapts automatically, but starts with one partition.
- Node-proportional: constant partitions per node. Scales naturally, but rebalancing moves data.

Automatic rebalancing sounds nice but is dangerous: a slow node can trigger a cascade. Kleppmann recommends automated mechanics with manual triggers.

**Request routing.** Three patterns: any-node forwarding, dedicated routing tier, or smart clients with embedded partition map. ZooKeeper is the standard coordination backbone for keeping the map consistent.

Parallel query execution (MPP) for analytical queries that hit every partition. Same principle as MapReduce/Spark but within a SQL engine at lower latency.

Takeaway: partitioning should be invisible to the application. Make it invisible by choosing the right partition key, indexing strategy, and rebalancing discipline.
