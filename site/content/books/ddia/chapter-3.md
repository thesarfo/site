---
title: "Storage and Retrieval"
number: 3
book: ddia
---

## Chapter 3, Storage and Retrieval

*Databases must store data and retrieve it on demand, and this chapter explains the internal data structures and algorithms that make that possible, while showing why no single storage engine excels at both transactional and analytical workloads.*

---

### 3.1 Data Structures That Power Your Database

#### Hash Indexes

The simplest imaginable index is an in-memory hash map that maps every key to the exact byte offset of its value in an append-only log file on disk. Writes are extremely fast because they involve nothing more than appending to the end of the file and updating the in-memory hash map, and reads require only a single disk seek to the correct byte offset to retrieve a value. The fatal limitation of this approach is that the entire hash map must fit in RAM, which restricts the dataset size, and range queries over consecutive keys are impossible because the hash map scatters entries randomly. To prevent the log file from growing without bound, storage engines break it into fixed-size segments and periodically run a compaction process that merges several segments together, discarding duplicate keys so that only the most recent value for each key survives. Once merging is complete, old segment files can be deleted safely. Deletion of a key is handled by writing a special tombstone record, and the compaction process will eventually discard both the tombstone and all previous values for that key. The Bitcask engine (Riak's default storage backend) is a well-known real-world implementation of this design.

#### SSTables and LSM-Trees

An SSTable, or Sorted String Table, improves on the basic hash index by requiring that key-value pairs within each segment file are sorted by key. This simple change brings several major advantages. First, merging segments becomes trivially efficient because you can use a mergesort algorithm that reads multiple input segments in parallel and writes the merged output sequentially. Second, you no longer need a full index of every key; a sparse in-memory index that maps a few keys per segment to their offsets is sufficient, because you can scan forward from the nearest indexed key to find the exact key you want. Third, you can compress the blocks of key-value data between sparse index entries, saving both disk space and I/O bandwidth.

The LSM-tree, or Log-Structured Merge-tree, generalizes this idea into a complete storage engine by combining an in-memory balanced tree (called a memtable, typically implemented as a red-black tree) with on-disk SSTables. Every write first goes into the memtable, and when the memtable reaches a size threshold, it is flushed to disk as a new SSTable segment. Reads search the memtable first, then the most recent SSTable, then progressively older SSTables, stopping as soon as the key is found. To avoid expensive disk reads when a key does not exist, LSM-tree implementations use Bloom filters, which are memory-efficient probabilistic data structures that can definitively say "this key is not present" without touching the disk. A background compaction process continually merges older SSTable segments to discard overwritten values and reclaim space. LevelDB and RocksDB use leveled compaction, in which SSTables are organized into a hierarchy of levels of exponentially increasing size, and segments are merged from lower levels into higher ones as they overflow. Cassandra and HBase use size-tiered compaction, in which segments of similar size are merged together in batches. The defining operational characteristic of LSM-trees is that all writes are sequential, which allows them to saturate disk throughput even on spinning magnetic drives, making them spectacularly write-optimized.

#### B-Trees

The B-tree is the most widely deployed indexing structure in relational databases and remains the standard point of comparison for all other storage engines. A B-tree organizes data into fixed-size pages (typically 4 KB) arranged in a balanced tree, with each page containing a sorted array of keys and references to child pages at the next level. The tree remains balanced because all leaf pages are at the same depth, and the branching factor is high, meaning the tree is shallow and the number of disk seeks to find a single key is small. Unlike LSM-trees, B-trees update pages in place: when a new key is inserted into a page that is already full, the page is split into two half-full pages and the split is propagated up the tree. To survive crashes, B-trees write every modification to a write-ahead log (WAL) before applying it to the actual tree pages, ensuring that after a crash the database can replay the log and restore the B-tree to a consistent state. Concurrency is managed with latches, lightweight reader-writer locks on individual pages, that prevent threads from seeing the tree in an inconsistent state during modifications.

When comparing LSM-trees to B-trees, the central trade-off is that LSM-trees are faster for writes and B-trees are faster for reads. LSM-trees write sequentially and therefore achieve much higher write throughput, but they suffer from write amplification during compaction (the same data is rewritten multiple times as it moves through levels) and from the risk that an expensive compaction will starve foreground read and write operations. B-trees also experience write amplification because they must write entire pages to the WAL and to the tree for every modification, and they can suffer from fragmentation as pages become partially empty after many updates.

#### Other Indexing Structures

A secondary index maps from values of a non-primary column to a set of row identifiers, enabling queries on columns other than the primary key. In a heap-file organization (used by PostgreSQL), the index points to a location in a heap file where the full row resides, whereas in a clustered index (MySQL InnoDB's primary key), the row data is stored directly within the index itself, eliminating one level of indirection. A covering index stores a subset of the row's columns within the index, so that certain queries can be satisfied entirely from the index without ever consulting the heap file.

Beyond simple single-column indexes, databases provide multi-column indexes, including concatenated indexes that sort by the first column and then by subsequent columns for tie-breaking, R-trees for geospatial bounding-box queries, and inverted indexes for full-text search. Specialized engines like Lucene provide fuzzy, edit-distance-aware search indexes.

#### In-Memory Databases

It is now economically feasible to keep entire databases in RAM, which has sparked a renaissance of in-memory databases such as Memcached, Redis, VoltDB, and MemSQL. The performance advantage of these systems comes less from avoiding disk reads, after all, a traditional database with a large enough page cache will serve reads from memory too, and more from avoiding the overhead of encoding in-memory data structures into a disk-friendly wire format and then decoding them again on reads. Durability can be added through periodic snapshots, append-only change logs, or replication to other machines, and some in-memory databases provide full ACID guarantees.

---

### 3.2 Transaction Processing vs. Analytics

A fundamental schism exists in the database world between online transaction processing (OLTP) and online analytical processing (OLAP). OLTP workloads consist of vast numbers of short, low-latency reads and writes, looking up a customer's order, adding an item to a shopping cart, recording a payment, and are typically indexed by primary key. OLAP workloads consist of a small number of large, read-only queries that scan millions of rows, compute aggregations, and answer business-intelligence questions such as "total revenue by product category in Q3." These two workloads are so antagonistic in their access patterns that running analytical queries directly on the live OLTP database cripples transaction performance. The industry's response was the data warehouse: a separate database, optimized exclusively for analytics, that is populated by an Extract–Transform–Load (ETL) process that periodically extracts data from the OLTP systems, transforms it into a query-friendly schema, and loads it into the warehouse.

#### Star and Snowflake Schemas

Data warehouses typically organize data into a star schema, in which a central fact table records individual events (each row is an immutable sale, page view, or sensor reading) and contains foreign keys pointing to dimension tables that describe the who, what, where, and when of each event. A snowflake schema is a more normalized variant in which dimensions are further broken into sub-dimensions, reducing redundancy at the cost of more joins.

#### Column-Oriented Storage

The signature innovation of analytical databases is column-oriented storage. Instead of storing all the columns of a row contiguously on disk (as row-oriented OLTP databases do), a column store writes all values of a single column together across many rows. Since a typical analytical query touches only three or four columns out of a table that may have hundreds, columnar storage ensures that only the relevant columns are read from disk, which reduces I/O by one to two orders of magnitude. Rows are reconstructed by taking the nth entry from each column file, because all column files preserve the same row ordering.

Columnar compression is remarkably effective because columns often contain only a small number of distinct values. The canonical compression technique is bitmap encoding: for a column with N distinct values, you create N bitmaps, where each bitmap has a 1 at position i if row i holds that value, and a 0 otherwise. These bitmaps can be compressed with run-length encoding to dramatic effect (a column with 10 million rows and only 3 distinct values becomes tiny). Furthermore, bitmaps enable vectorized processing: filtering conditions can be evaluated with bitwise AND and OR operations, which modern CPUs can perform on wide SIMD registers, processing hundreds of rows in a single instruction.

The order in which rows are sorted in a column store is a powerful knob. Sorting by a frequently-filtered column clusters identical values into contiguous runs, which makes compression far more effective for that column. The first sort key yields the largest benefit; subsequent sort keys break ties but produce shorter and less compressible runs. In systems like C-Store and Vertica, different replicas can maintain different sort orders, and the query planner routes each query to the replica whose sort order is most advantageous.

Writing to a column store is significantly more expensive than writing to a row store. Inserting a single row would, in a naive implementation, require rewriting every column file, which is unacceptable. The solution is to adopt an LSM-tree–style approach in which writes are batched in memory using a row-oriented write-optimized store and then periodically merged onto disk in bulk with the columnar data.

#### Materialized Views and Data Cubes

A materialized view is a precomputed result of a query, stored on disk so that subsequent identical queries can be answered instantly without scanning the raw data. The challenge is keeping the materialized view up to date when the underlying data changes. A data cube is a generalization of this idea: a grid of precomputed aggregations across every combination of several dimensions (product, date, region, and so on), allowing drill-down queries to run in near-constant time. The trade-off is severe: data cubes consume enormous storage space and lose the flexibility to query dimensions that were not pre-aggregated.

---

### Chapter Summary

Storage engines fall into two broad families. Log-structured engines like LSM-trees are optimized for writes by turning all writes into sequential appends and deferring the hard work of merging and compaction to background processes. Page-oriented engines like B-trees are optimized for reads by maintaining a balanced, update-in-place tree structure with a write-ahead log for crash safety. Orthogonal to this distinction is the split between OLTP and OLAP: OLTP workloads demand row-oriented storage that can efficiently read and write individual rows, while OLAP workloads demand column-oriented storage that can efficiently scan millions of rows while touching only a handful of columns. The overarching lesson of the chapter is that there is no universal storage engine; every choice entails trade-offs, and understanding those trade-offs is what allows an engineer to select the right tool for a given access pattern, tune it correctly, and reason about its behavior in production.
