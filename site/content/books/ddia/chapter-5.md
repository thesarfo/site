---
title: "Replication"
number: 5
book: ddia
---


## The Core Problem

Replication means keeping copies of the same data on multiple machines connected by a network. It serves three purposes: to keep data geographically close to users (reducing latency), to keep the system available even when some machines fail (increasing fault tolerance), and to scale out read throughput by serving queries from multiple replicas. The fundamental tension is that any change to the data must be propagated to every replica, and the network is slow, unreliable, and introduces lag, so every replication scheme is a negotiation between consistency, availability, and latency.

---

## Leaders and Followers

The most common replication architecture is leader-based (also called master–slave or active–passive). One replica is designated the leader; all writes go to it. The leader logs each write to its local storage and then sends the change to its followers as a replication log. Followers apply the same writes in the same order, eventually converging to an identical copy. Reads can be served from any replica, leader or follower, though reading from followers risks returning stale data.

### Synchronous Versus Asynchronous Replication

The leader can propagate changes either synchronously or asynchronously. In synchronous replication, the leader waits for confirmation from a follower before reporting the write as successful; this guarantees the follower has an up-to-date copy but makes writes intolerably slow if any follower is down or unreachable. In asynchronous replication, the leader reports success immediately after writing locally and sends changes to followers afterward; this keeps writes fast but means a leader crash can lose any writes not yet propagated. The practical compromise is semi-synchronous replication: exactly one follower is synchronous (so there is always at least one up-to-date backup), and the rest are asynchronous.

### Setting Up New Followers

Adding a follower requires a consistent point-in-time snapshot of the leader's data, taken without pausing writes. The follower captures the snapshot, applies it, then requests all changes that occurred after the snapshot's log position. Once the backlog is caught up, the follower joins the stream of ongoing replication.

### Handling Node Outages

Follower failure is simple: the follower keeps a record of the last transaction it processed and, on recovery, reconnects to the leader and requests all changes since that point. Leader failure, a failover, is harder. Followers must detect the leader's unavailability (via timeouts), elect a new leader (typically through a consensus algorithm), reconfigure all clients to send writes to the new leader, and ensure the old leader does not accept writes after it recovers (a "brain split" scenario). Failover is fraught with danger: if the old leader had writes not yet replicated, those writes are lost; if two nodes both believe they are leader, conflicts are difficult to unwind; and a badly-tuned timeout can trigger unnecessary failovers.

### Implementation of Replication Logs

The replication log itself can take several forms. Statement-based replication sends the SQL statements themselves, but this breaks on nondeterministic functions like `NOW()` or `RAND()`. Write-ahead log (WAL) shipping sends the raw bytes of the database's internal log, coupling replication tightly to the storage engine's on-disk format, which means upgrading to a new database version requires downtime. Logical (row-based) replication decouples the log from the storage format by describing changes at the row level: an inserted row's new values, an updated row's old and new values, a deleted row's identity. Logical logs are more portable across versions and easier to parse for downstream consumers (change data capture). Trigger-based replication runs application-level code on every write, giving maximum flexibility at the cost of performance and error-proneness.

---

## Problems With Replication Lag

Asynchronous replication inevitably introduces lag: followers are microseconds to seconds behind the leader, sometimes minutes during overload or network problems. This lag creates three distinct anomalies that application developers must either tolerate or work around.

### Reading Your Own Writes

A user writes data and then immediately reads it back. If the read is served from a lagging follower, the user sees the state from before their write, which is deeply confusing in user-facing applications. The solution is *read-after-write consistency*: ensure that in certain contexts, reads go to the leader or to a follower known to be sufficiently caught up. Techniques include routing reads for a user's own data to the leader for a short window after a write, tracking the timestamp of the last write and querying only followers that have replicated past that point, or sending the user's writes and immediate reads to the same replica if the replica can serve reads.

### Monotonic Reads

A user reads from one follower and sees a recent change, then refreshes and reads from a different, more lagging follower, and the change disappears. This backward-moving time is a violation of *monotonic reads*, the guarantee that a user will never see data go backward. The fix is to route each user to a consistent replica, either always the same replica (sticky sessions) or always a replica sufficiently up to date.

### Consistent Prefix Reads

If writes happen in a causal order, a comment is inserted, then a reply references it, a reader might see the reply (applied from a caught-up follower) without seeing the original comment (from a lagging follower), violating causality. *Consistent prefix reads* guarantee that a reader sees writes in the order they were written, even if reading from different replicas. Partitioned databases are especially vulnerable because different partitions replicate at different speeds. The solution is to ensure that causally related writes are routed to the same partition, so they are always read in order.

### Solutions for Replication Lag

The broader lesson is that eventual consistency is a deliberately vague promise, it says replicas will converge eventually but says nothing about when or what readers will see in the interim. Stronger guarantees (read-after-write, monotonic reads, consistent prefix reads) are properties the application can request, and databases increasingly expose them as tunable knobs. Transactions are an alternative: they provide a stronger, simpler model for the developer at the cost of performance. Ultimately, Kleppmann argues that hiding replication lag entirely is impossible; the application must either tolerate the anomalies or pay the performance and availability cost of stronger consistency.

---

## Multi-Leader Replication

In multi-leader (master–master) replication, more than one node accepts writes, and each leader simultaneously replicates its changes to all other leaders. This is substantially harder than single-leader replication because writes can conflict.

### Use Cases

Multi-leader replication is rare inside a single datacenter, where single-leader suffices and avoids conflict complexity. It becomes compelling in three scenarios. First, **multi-datacenter deployments**: placing a leader in each datacenter allows local writes with low latency, and replication between datacenters happens asynchronously over the wide-area network. Second, **offline-capable applications**: a calendar app on a phone is a local database that accepts writes while offline and syncs with a remote server when connectivity returns; each device is a leader. Third, **collaborative editing**: Google Docs and similar tools allow multiple users to edit a document simultaneously, which is fundamentally a multi-leader replication problem with a conflict-resolution layer.

### Handling Write Conflicts

Conflicts arise when two leaders accept writes to the same record concurrently. The simplest approach is **conflict avoidance**: architecture the application so that all writes for a given record always go to the same leader, turning the problem back into single-leader per record. When avoidance is impossible, conflicts must be resolved. **Last-write-wins (LWW)** is the simplest method, each write carries a timestamp, and the one with the highest timestamp wins, but it silently discards data and is only safe when losing writes is acceptable. **Convergent conflict resolution** uses data-type-specific merge logic: a counter increments, a string concatenates, a set unions. **Custom conflict resolution** lets the application define arbitrary logic, executed either on write (the database calls a merge handler immediately) or on read (conflicting versions are stored and the application resolves them when reading). **Automatic conflict resolution** with CRDTs (Conflict-free Replicated Data Types) provides mathematically guaranteed convergence for specific data structures. The broader point is that there is no one-size-fits-all solution; conflict resolution is deeply application-specific.

### Topologies

The paths by which replication flows between leaders form a topology. A circular topology (A→B, B→C, C→A) is simple but fragile: a single node failure breaks the ring. A star topology (one central node relays all writes) is equally fragile. An all-to-all topology is robust but requires each node to avoid forwarding a write it has already received, typically by tagging each write with the identifier of the originating leader. All topologies must handle the risk that network delays cause writes to arrive at some leaders out of order, which can produce conflicts even on records that were never genuinely edited concurrently.

---

## Leaderless Replication

Leaderless replication abandons the leader–follower distinction entirely. Any replica can accept writes, and the protocol, most famously Dynamo-style quorum replication, coordinates consistency through the client or through a coordinator node.

### Writing When a Node Is Down

In a quorum system with N replicas, a write is sent to all N nodes but waits for acknowledgement from only W of them (the write quorum). A read is sent to all N nodes and waits for at least R responses (the read quorum). If W + R > N, every read is guaranteed to see the most recent write because at least one node in the intersection of the write and read quorums holds the up-to-date value. The system tolerates up to N − W unavailable nodes for writes and N − R unavailable nodes for reads. This allows tuning: W = N and R = 1 gives fast reads but fragile writes; W = 1 and R = N gives the reverse; W = R = (N+1)/2 (a majority quorum) balances both.

When a node is temporarily down and misses writes, it must catch up when it returns. Two mechanisms handle this: **read repair**, where a client reading from multiple replicas detects a stale response and writes the up-to-date value back to the stale replica, and **anti-entropy**, a background process that continually compares replicas and copies missing data.

### Limitations of Quorum Consistency

Kleppmann is careful to point out that W + R > N guarantees that a value, once written, will be seen by subsequent reads, but this is weaker than it sounds. The guarantee assumes that N, W, and R are fixed and that all nodes agree on which writes succeeded, but in practice many edge cases undermine it. If a write succeeds on fewer than W replicas and the coordinator does not retry, the write is effectively lost. If a node that missed a write is included in a read quorum, it may return a stale value; the read coordinator can mask this by requesting multiple versions per node and resolving them, but not all databases do. If a node is restored from an incorrectly configured backup, it can regress and serve arbitrarily stale data. Concurrent writes with conflicting updates can produce a situation where no single "most recent" value exists. The lesson is that quorum consistency is not a silver bullet; it provides a probabilistic, not absolute, guarantee, and stronger guarantees require additional coordination.

### Sloppy Quorums and Hinted Handoff

In a large cluster, network partitions can make it impossible to reach W designated home nodes for a given key. **Sloppy quorum** relaxes the constraint: the write coordinator sends the write to any W available nodes, not necessarily the home nodes, and those nodes store the data tagged with the intended home. When the home nodes become reachable, the data is handed off to them (**hinted handoff**). This dramatically increases write availability during network partitions but means that W + R > N no longer guarantees that reads will see the most recent writes, because the values are stored on the wrong nodes. Sloppy quorum is therefore not a consistency guarantee at all, it is a durability and availability optimization.

### Detecting Concurrent Writes

Leaderless replication requires a way to reconcile writes that arrive at different replicas in different orders. **Last-write-wins (LWW)** uses a timestamp or a unique, incrementing version number and discards any write that carries an earlier version. It is simple and deterministic but fundamentally unsafe: it drops data without notifying the application, and it relies on synchronized clocks or consistent version counters, neither of which is reliable in distributed systems.

The more sophisticated approach is **version vectors** (also called vector clocks). Each replica maintains a version number per replica, and each write carries the set of version numbers it has seen. When a write arrives, the system can determine whether it is strictly newer than another, strictly older, or concurrent (neither supersedes the other). Concurrent versions are not resolved automatically; they are either returned to the client for application-level resolution or merged using data-type-specific rules. Version vectors grow with the number of replicas that have ever accepted writes for a given key, which is bounded in practice, and they provide a precise, causality-preserving foundation for conflict detection.

---

## Synthesis

Replication is a matter of trade-offs, not absolutes. Single-leader replication is the simplest programming model, all writes flow through one node, conflicts are impossible, and consistency is straightforward, but it limits write scalability and availability. Multi-leader replication enables local writes across datacenters and offline operation, at the cost of conflict resolution. Leaderless replication maximizes write availability during failures, at the cost of a weaker and more complex consistency model. The common thread across all three architectures is **replication lag** and the anomalies it creates: read-your-own-writes violations, non-monotonic reads, and causal inversion. Each architecture offers tools to manage these anomalies, from sticky sessions to quorum tuning to version vectors, but none eliminates them entirely without sacrificing performance or availability. The engineer's task is to understand which anomalies the application can tolerate and to choose the replication strategy whose failure mode aligns with what the business can accept.

