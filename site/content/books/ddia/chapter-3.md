---
title: "Storage and Retrieval"
number: 3
book: ddia
---

**Hash indexes**, simplest index: an in-memory hash map from key to byte offset in an append-only log. Fast writes, no range queries. Bitcask (Riak) uses this.

**SSTables and LSM-trees**, sorted key-value pairs. Merging is trivial (mergesort). Sparse in-memory index + compressed blocks between entries is enough. LSM-trees combine an in-memory memtable (red-black tree) with on-disk SSTables. Writes are sequential → fast even on spinning disks. Bloom filters avoid expensive reads for missing keys. LevelDB/RocksDB use leveled compaction; Cassandra uses size-tiered. The tradeoff: great writes, but compaction can starve foreground operations.

**B-trees**, the standard. Fixed-size pages (4 KB), balanced tree, update in place. Write-ahead log (WAL) for crash safety. Better reads than LSM-trees, worse writes. Write amplification from rewriting pages is a problem for both.

**Other indexes:** secondary, clustered (row stored inside index), covering (index has enough columns to answer the query). Multi-column, geospatial (R-trees), full-text (inverted indexes, Lucene).

**In-memory databases** (Redis, VoltDB), speed comes from avoiding serialization overhead, not from avoiding disk (a cached B-tree also reads from memory). Durability via snapshots or replication.

**OLTP vs OLAP**, fundamentally different access patterns. OLTP: short reads/writes by key. OLAP: large scans with aggregations. Mixing them kills performance. Solution: data warehouse with ETL.

**Column-oriented storage**, write each column contiguously, not each row. Analytical queries touch 3-4 columns out of hundreds, so I/O drops by orders of magnitude. Compression is excellent (bitmaps + run-length encoding). Sorting by a frequently-filtered column makes compression even better. Writes are expensive; in practice they batch in memory and merge periodically (like LSM).

**Materialized views and data cubes.** Precomputed query results. Data cubes are grids of aggregations across every dimension combination, fast drill-down but huge storage and no flexibility for unplanned queries.

Takeaway: no universal storage engine. Log-structured (LSM) for write-heavy, page-oriented (B-tree) for read-heavy, columnar for analytics.
