---
title: "Partitioning"
number: 6
book: ddia
---


# Chapter 6, Partitioning

## The Core Problem

Partitioning (sharding) is the deliberate splitting of a large dataset across multiple machines. The reason is straightforward: no single machine can store an unbounded amount of data or serve an unbounded number of requests. Partitioning breaks the dataset into pieces small enough to fit on individual nodes, and by spreading the load, it enables the system to scale beyond the limits of a single box. The central challenge is that the split must be done in a way that keeps related data together, balances load evenly, and remains efficient as the dataset grows and the cluster membership changes.


## Partitioning and Replication

Partitioning and replication are orthogonal but usually deployed together. Each partition is replicated onto multiple nodes for fault tolerance, so that a given node holds some partitions as a leader and other partitions as a follower. The relationship means that a node's failure affects multiple partitions, and recovery involves redistributing leadership and catching up followers across the cluster. Understanding this interplay is essential: partitioning determines how data is spread, and replication determines how each chunk survives failure.



## Partitioning of Key-Value Data

The fundamental question is how to decide which record goes on which partition. For key-value data, the answer is a function of the key.

### Partitioning by Key Range

The simplest approach assigns a contiguous range of keys to each partition, like an encyclopedia: A–F on partition 1, G–M on partition 2, and so on. This makes range scans efficient, a query for all keys between C and E naturally lands on a single partition. But it risks severe skew when keys are not uniformly distributed or when access patterns concentrate on a narrow range. A sensor application logging by timestamp, for instance, would direct all writes to the partition holding today's date, creating a hot spot that defeats the purpose of partitioning.

### Partitioning by Hash of Key

A hash function applied to the key scatters records uniformly across partitions, eliminating hot spots. The hash is deterministic (same key always maps to the same partition) but destroys ordering: records with adjacent keys land on different partitions, making range queries expensive because the query must be sent to every partition. This is the dominant strategy in practice (Cassandra, MongoDB, Riak, DynamoDB) because it solves the skew problem definitively. Some systems compromise with compound primary keys: the first part is hashed for distribution, and the second part is kept in order within the partition, enabling efficient range queries within a single hash bucket.

### Skewed Workloads and Hot Spots

Hashing eliminates skew from data distribution but cannot fix skew from access patterns. If a celebrity on a social network generates a disproportionate volume of writes and reads, that single key becomes a hot spot regardless of how perfectly the hash function spreads the rest of the data. The remedy is application-level: split the hot key into multiple sub-keys (e.g., `celebrity_1`, `celebrity_2`, ..., `celebrity_N`), distribute them across partitions, and have reads aggregate across all sub-keys. This is awkward and manual, and Kleppmann notes that truly eliminating hot spots remains an open problem.



## Partitioning and Secondary Indexes

Secondary indexes, indexes on columns other than the primary key, complicate partitioning because a record and the index entries that point to it may live on different partitions. There are two strategies.

### Partitioning by Document (Local Indexes)

Each partition maintains an independent secondary index covering only the records stored on that partition. A query on an indexed column must be sent to every partition (scatter-gather), and the results are combined. This keeps writes local and fast, inserting a record only updates the index on its own partition, but makes reads expensive and introduces tail-latency amplification, because the slowest partition determines the query's overall response time. MongoDB, Cassandra, and Elasticsearch use this approach. It works well when queries also include the partition key (restricting the scatter-gather to a single partition), but poorly for global queries across all partitions.

### Partitioning by Term (Global Indexes)

A global secondary index is itself partitioned, but independently of the primary data. All entries for a given indexed term (e.g., `color: red`) are stored together on a single partition, regardless of where the corresponding records live. This makes reads efficient,a query for red items hits exactly one partition, but makes writes expensive because inserting a record now requires updating a secondary index that may reside on a different partition, involving a distributed transaction or at least a two-phase write. Most databases that offer global secondary indexes (such as DynamoDB's global secondary indexes) update them asynchronously, meaning the index can briefly lag behind the primary data.



## Rebalancing Partitions

As machines are added or removed, partitions must be redistributed, a process called rebalancing. The requirements are: the load should be evenly spread after rebalancing, the database should continue serving reads and writes during the move, and only the minimum necessary data should be relocated.

### Strategies for Rebalancing

**Fixed partitions** assign a large, pre-configured number of partitions at cluster creation, far more than the number of nodes. When a new node joins, it takes over a few partitions from existing nodes. The number of partitions never changes, so the mapping from key to partition is stable, and only entire partitions move between nodes. This is simple and widely used (Riak, Elasticsearch, Couchbase). The trade-off is that the number of partitions must be chosen up front and is hard to change later, so it must be large enough to accommodate future growth without being so large that the management overhead becomes burdensome.

**Dynamic partitioning** lets partitions split and merge automatically as they grow or shrink. When a partition exceeds a size threshold, it splits in two; when partitions become small (after many deletions), they merge. This is the approach of HBase and MongoDB. It adapts to the data volume but means that at startup, when the dataset is small, the system may begin with a single partition, concentrating all load on one node.

**Partitioning proportionally to nodes** fixes a constant number of partitions per node. Each node gets the same number of partitions regardless of the dataset size. When a new node joins, it takes a proportional share of partitions from existing nodes. This keeps partition sizes roughly constant as the cluster grows and is used by Cassandra and the original Dynamo paper. The advantage is that partition size scales naturally with cluster size; the disadvantage is that adding a node requires data movement and that the hash-to-partition mapping changes.

### Automatic or Manual Rebalancing

Fully automatic rebalancing, where the system detects imbalance and begins moving partitions without human intervention, is seductive but dangerous. A node that is merely slow (due to a heavy query, not a fault) can be mistaken for a failed node, triggering an unnecessary rebalance that compounds the overload and can cascade into a total cluster outage. Kleppmann recommends that rebalancing be triggered manually by an administrator, with the actual partition movement automated. The human provides judgment about whether the cluster is genuinely stable enough to rebalance; the system handles the mechanical work of relocating data safely.



## Request Routing

Once data is partitioned, a client must know which node holds the partition for a given key. There are three approaches. In the simplest, each node knows the partitioning scheme and any node can forward a request to the correct destination, a gossip protocol disseminates cluster membership changes, and clients just contact any node. Alternatively, a dedicated routing tier (like a load balancer) sits between clients and nodes and directs requests. In the most sophisticated approach, clients themselves maintain the mapping and contact the correct node directly. ZooKeeper is frequently used to maintain the authoritative mapping of partitions to nodes; each node registers itself in ZooKeeper, and clients or routing tiers subscribe to changes, so that when partitions move, the mapping is updated within seconds and stale routing causes at most a transient error that can be retried. The trade-off is straightforward: client-side routing eliminates a network hop (and the routing tier as a scalability bottleneck), but requires more complexity in the client library.



## Parallel Query Execution

For simple key-value reads and writes, a query touches exactly one partition and the routing problem is solved by any of the methods above. But analytical queries that aggregate across the entire dataset, sums, counts, averages, joins, must touch every partition. This is where the massively parallel processing (MPP) architecture of data warehouses enters: the query is broken into a query plan, each partition executes a portion of the plan on its local data, and the results are combined. The same principle underlies MapReduce and Spark, which partition computation alongside data. The distinction is that MPP databases (like Teradata or Vertica) do this within a SQL engine optimized for interactive analytical queries, while batch processing frameworks (like MapReduce) do it with a more general-purpose execution model at higher latency.



## Synthesis

Partitioning is the primary mechanism by which databases scale beyond a single machine. The key decision is the partitioning strategy: range-based enables efficient range scans at the risk of skew, while hash-based eliminates skew at the cost of range query efficiency. Secondary indexes add another dimension: local indexes keep writes fast but make reads a scatter-gather operation; global indexes make reads fast but complicate writes. Rebalancing is the operational heart of a partitioned system: fixed partitions trade flexibility for simplicity, dynamic partitions adapt to data volume, and node-proportional partitioning keeps sizes constant as the cluster grows, but all require a human in the loop for the final decision to rebalance. Request routing is solved by any of three patterns, node-level forwarding, a routing tier, or smart clients, with ZooKeeper as the standard coordination backbone. The chapter's overarching lesson is that partitioning is a mechanical optimization, not a semantic one: it should be invisible to the application, but achieving that invisibility requires careful choices about the partition key, the indexing strategy, and the rebalancing discipline.