---
title: "Designing a MapReduce Framework"
date: 2025-10-18
excerpt: "Building a MapReduce framework from scratch"
tags: ["engineering"]
---
Inspired by Google’s *MapReduce* paper, I set out to design a simplified framework of my own. I chose build a word count algorithm (the "hello world" of MapReduce) that could scale from running on my laptop to hopefully running across multiple machines. It took three major iterations (milestones) to get there, and it was pretty fun doing all that.

## Milestone 1: The Sequential Model

Before worrying about clusters and threads, I started with the simplest version possible, a single-threaded MapReduce running on my laptop. Nothing running in parralel, no distributed stuff, just the core algorithm:

1. **Map Phase**: Read the input file line by line, split each line into words, and emit `(word, count)` pairs
2. **Shuffle Phase**: Group all the values by key (word)
3. **Reduce Phase**: Aggregate all values for each key to produce the final result
4. **Output**: Write the results to a file

Standard stuff. I created interfaces for the mapper and reducer to keep things extensible. The mapper would take each line of text and spit out key-value pairs, and the reducer would aggregate them.

Here's something I almost missed: my very first mapper implementation used a hash map to store the results. It seemed reasonable, But I later noticed when a word appeared multiple times on the same line, it would just overwrite the previous entry. So for instance if a line had "the cat and the dog", my hash map would only count "the" once instead of twice.

The fix was simple though: use a list of key-value pairs instead, so every word occurrence gets its own entry. This is actually how MapReduce is supposed to work - the mapper emits multiple values for the same key, and the shuffle phase groups them together.

## Milestone 2: Parallelization

After getting the firt version working, it was time to make it faster, and what better way than by running multiple map and reduce tasks in parallel.

Conceptually, every map task can run independently on different chunks of data. The only synchronization happens during the shuffle and reduce phases. So, I extended the framework to support multithreading, essentially a miniature version of what Hadoop will do on a single machine.

My plan was to:

- Split the input into chunks (like Hadoop's Distributed File System does with 16-64mb blocks)
- Parallel Map Tasks: Each chunk gets processed by a separate thread
- Hash Partitioning: Use a hash function modulo the number of reducers to distribute keys evenly
- Parallel Reduce Tasks: Each reducer processes its partition independently

Based on the above, I implemented:
- **Input Splitter** - breaks files into manageable chunks
- **Map Tasks** - runs map operations on separate threads and writes partitioned output to disk
- **Reduce Tasks** - reads partition files, groups by key, and reduces
- **Job Orchestrator** - coordinates everything and manages the thread pool

I added timing statistics to both the sequential and parallel versions so I could see the speedup. Ubtil I ran it...

**Parallel was SLOWER.** 

Like, significantly slower. This is what I saw:

**Sequential**: 204ms total
- Map: 119ms
- Shuffle: 45ms  
- Reduce: 4ms

**Parallel**: 373ms total (83% SLOWER!)
- Map: 170ms
- Shuffle: 77ms
- Reduce: 126ms

The map phase was a bit faster, but the reduce phase was 32x slower, making the parralel implementation 83% slower overall. So clearly something was wrong.

### Understanding the Problem

After some debugging, the problem became clear:

1. **Small dataset**: My test file was tiny (just 2 lines, 20K words). I originally copied these words from the internet but by text editor couldn't wrap them into multiple lines. This wasn't enough to justify parallelism.
2. **No parallelization benefit**: It only created 1 chunk, so the map phase didn't even parallelize
3. **Overall overhead**: The parallel version had to:
   - Create 62 map tasks × 8 partitions = 496 intermediate files
   - Each reducer reads from 62 files over disk I/O. Synchronization and task management took a huge part of the runtime.


A thing I picked from this was that parallelization has overhead, and it only pays off when your data is big enough to amortize that cost.

## Creating Realistic Test Data

I needed to see this thing actually work, so I wrote a bash script to generate a million lines of text:

```bash
#!/bin/bash
# Generate 1 million lines with 10-20 random words each
words=(
    "the" "quick" "brown" "fox" "computer" "algorithm" 
    "data" "function" "parallel" "distributed" ...
)
# Pick random words, generate lines
```

The script used a vocabulary of 90 programming-related words and generated about 11 million words total. The file size was about 62 MB, which was alright for testing.


But here's another thing I discovered: *the characteristics of your test data also affect your results*. My generated file had only 90 unique words, repeated randomly. After running MapReduce, I got 500 unique keys in the output. The reduce phase was basically:

```
"the" -> appears 250,000 times
"data" -> appears 180,000 times
"computer" -> appears 195,000 times
...
```

A few keys with massive value lists. This wasn't really realistic. Real text has way more vocabulary diversity. So I ditched my generated data and found a [real text](https://github.com/atomicmooseca/onemil) online, a million-line file with actual diverse English text. Now my output had **504,605 unique words**. Completely different workload:

```
"the" -> appears 12,000 times
"obsolete" -> appears 3 times
"serendipitous" -> appears 1 time
...
```

I got thousands of keys with varied frequencies which stressed the system differently:
- More memory for the grouping phase (hundreds of thousands of unique keys to track)
- Better load balancing across reducers (keys distributed more evenly)
- More shuffle overhead, since there were many small groups instead of a few giant ones.

**Takeaway**: Test data matters. Don't just generate random repetitive data - use realistic datasets that match your production workload. The distribution of your data will significantly impact performance.

So with the million-line input:

**Sequential**: 16,712ms
- Map: 7992ms
- Shuffle: 7816ms
- Reduce: 501ms

**Parallel**: 22,580ms
- Map: 5237ms **(1.5x faster)**
- Reduce: 16138ms **(32x slower)**

The map phase finally showed parallelization. 62 chunks processed across 8 CPU cores. Beautiful. But that reduce phase was still killing me.

I later learnt that word counting with disk-based shuffle isn't ideal because:

- Reading and writing 11 million records to disk is expensive

- Counting words is too cheap computationally to mask I/O delays

- File operations for each partition added massive overhead

I read that in systems like Spark, they use in-memory shuffles to avoid this. But hey, I'm building a learning project here, so whatever.

## Milestone 3: Distribution

This is where it got really fun. Time to build a true distributed system where mappers and reducers can run on different machines.

### Architecture

I went with a master-worker architecture as described in the paper:

**Master Node:**
- Tracks available workers
- Assigns tasks (map/reduce)
- Collects status updates
- Serves intermediate files via HTTP

**Worker Nodes:**
- Request tasks from master
- Execute map/reduce code
- Report completion
- Send heartbeat signals

**Communication:**
I used RPC with simple REST endpoints:
- `POST /api/master/request-task` - Workers ask for work
- `POST /api/master/submit-task` - Workers report results
- `POST /api/master/heartbeat` - Workers say "I'm alive"
- `GET /files/{jobId}/{taskDir}/{fileName}` - Download intermediate data

### How It Actually Works

Let me break down the distributed execution flow because this is where things get interesting:

**1. Job Initialization**

When you start the master, it:
- Reads the input file and splits it into chunks (each 1-16 MB)
- Creates map task objects for each chunk - these contain the actual lines of text
- Creates reduce task objects (one per partition) - these initially just know which partition they handle
- Registers all tasks with status "pending"
- Starts the HTTP server and waits

**2. Worker Registration & Task Polling**

Each worker starts up and:
- Sends a heartbeat to master every 5 seconds saying "I'm alive"
- Continuously polls `POST /request-task` asking "got any work for me?"
- The master looks through pending tasks, finds one, marks it as "assigned", and sends the task data back
- If there are no tasks available, worker gets a 204 No Content and waits 2 seconds before asking again

**3. Map Task Execution**

Worker receives a map task containing:
- The actual text lines to process
- Number of reducers (for partitioning)
- A task ID

The worker:
- Runs the mapper on each line, getting `(word, 1)` pairs
- For each output pair, calculates `partition = hash(key) % num_reducers`
- Writes each pair to the appropriate partition file: `map_task_X/partition_Y.txt`
- All files go to `/tmp/mapreduce/` on the worker's local disk

When done, worker calls `POST /submit-task` with:
- Task ID
- Success/failure status
- Number of records processed

**4. Intermediate Data Transfer**

A tricky one I worked through was when map tasks complete, their output is on the worker's local disk. But reduce tasks might run on different workers, so how do they get the data?

My solution:
- The master knows which worker completed each map task
- When creating reduce tasks, the master generates URLs like:

```
http://localhost:5000/files/job_123/map_task_0/partition_2.txt
http://localhost:5000/files/job_123/map_task_1/partition_2.txt
```

- Each reduce task gets a list of URLs for its partition number
- The master serves these files via HTTP (acting as a file server)

**5. Reduce Task Execution**

Worker receives a reduce task containing:
- List of intermediate file URLs
- Partition ID

The worker:
- Downloads each intermediate file
- Parses all the `(word, 1)` pairs from all files
- Groups by key: `{"hello": [1,1,1], "world": [1,1]}`
- Runs the reducer: count the values for each key
- Writes final output to `reduce_task_X/output.txt`

**6. Job Completion**

The master continuously monitors task status. When all tasks are complete:
- Master reads all reduce output files
- Merges them into a single final output file
- Job done!

### Challenges with Coordination

Now, the flow I went with above hides a lot of complexity

**Race Conditions**: What if two workers request tasks simultaneously? I used locks on the master side to ensure each task is assigned to exactly one worker.

**Failed Tasks**: If a worker crashes after accepting a task, that task is stuck "assigned" forever. Real systems have timeouts - if no heartbeat for N seconds, reassign the task.

**Data Locality**: In my implementation, reducers fetch data over HTTP. This is fine for localhost testing but terrible at scale. Hadoop's HDFS co-locates data with computation. Moving computation is cheaper than moving data.

**Intermediate Data Storage**: I'm writing everything to `/tmp/mapreduce` which works for single-machine testing. Workers write intermediate files to their own `/tmp/mapreduce/`, and the master serves files from its own `/tmp/mapreduce/`. This only works because I'm testing on localhost where both paths point to the same physical disk, so they share the same filesystem.

In a real distributed system across different machines, you need:
- Shared storage (NFS, HDFS, S3)
- Or workers serve their own data (each worker is also a file server)
- Or a distributed file system where any node can access any data

I went with a simplified "master serves everything" approach (Option 3 from the challenges section below). Workers write to their local disk, master serves from its local disk, which only works because "local" means the same machine during localhost testing. For true distribution across separate machines, you'd need one of the approaches above.

The cool part about all this was that I could now run mapreduce across multiple processes:

**Terminal 1 - Master Node:**
Start the HTTP server, split the input file, and register all tasks. The master sits there waiting for workers to connect.

**Terminals 2, 3, 4... - Worker Nodes:**
Each worker connects to the master, identifies itself with a unique ID, and starts polling for tasks.

Workers pick up tasks, process them, and report back. The master tracks everything and merges the final output. It's like watching a mini Hadoop cluster on your laptop!

## Challenges and Lessons

### 1. Task Assignment

What happened when multiple workers simultaneously hit `/request-task`? My initial version had a race condition where two workers could get assigned the same task.

The issue: 
```
Worker A: Check for pending tasks → Find task X
Worker B: Check for pending tasks → Find task X (still pending)
Worker A: Mark task X as assigned
Worker B: Mark task X as assigned (overwrites A's assignment)
Both workers: Start processing task X
```

So I basically wrapped the entire "check-assign-return" operation in a lock. Only one worker can be in this section at a time. This serializes task assignment (making it slightly slower) but ensures correctness.

### 2. Intermediate Data Transfer

Another hard part of distributed MapReduce is getting data from map tasks to reduce tasks. For instance, if a map task completes on Worker-1, its output files are on Worker-1's local disk. But the reduce task might run on Worker-2. How does Worker-2 get those files?

**Option 1: Shared Storage** (NFS, HDFS, S3)
- Pros: Simple, workers don't need to serve files
- Cons: Single point of failure, network bottleneck, need to set up shared storage

**Option 2: Workers as File Servers**
- Pros: No shared storage needed, data locality possible
- Cons: Every worker needs an HTTP server, complex networking

**Option 3: Master Serves Everything**
- Pros: Simple centralized architecture
- Cons: Master becomes bottleneck, doesn't scale

I went with Option 3 for simplicity. In my implementation, workers write intermediate files to their local disk at `/tmp/mapreduce/`, and the master's HTTP file server reads from `/tmp/mapreduce/` to serve those files to reducers. This works fine for localhost testing where all processes share the same filesystem,"local disk" is literally the same physical disk for everyone.

But, in a real multi-machine distributed deployment, this approach breaks down because the master can't read files from worker disks. You'd need to either switch to Option 1 (shared storage like NFS) or Option 2 (each worker runs its own file server).

### 3. Heartbeats

Workers send heartbeats every 5 seconds. But what should the master do with this information?

**If a worker stops sending heartbeats:**
- Maybe it crashed → need to reassign its tasks
- Maybe it's just slow → reassigning would waste work
- Maybe a network messup → reassigning would duplicate work

I punted on this, my implementation doesn't handle dead workers. A proper solution needs:
- Timeout threshold (e.g., no heartbeat for 30 seconds = dead)
- Task retry logic (reassign failed tasks)
- Duplicate detection (if original worker comes back and completes the task)


### 4. Serialization and Network Overhead

To send a map task to a worker, I need to serialize:
- Task ID (string)
- Chunk of input text (potentially megabytes)
- Configuration data

Using JSON for this is... questionable. JSON is text-based and verbose. For my million-line input file, I'm sending huge JSON payloads over HTTP.

Better solutions I read online would be to use Protobufs or just don't send the data at all, you could send a file location and let workers read it themselves or you also just compress the payload.



### 5. Fault Tolerance

In my current implementation:
- If a worker crashes mid-task, the task is lost forever
- If the master crashes, the entire job is lost
- If there's a corrupted intermediate file, the reduce task fails so the entire job fails

Avoiding the above would mean I have to consider:
- **Task retries**: If a task fails, try it again on a different worker
- **Speculative execution**: If a task is taking too long, start a duplicate and use whichever finishes first
- **Checkpointing**: Save job state so master can recover from crashes
- **Data replication**: Store intermediate data in multiple locations

Adding fault tolerance would definitely double the code complexity, so I chose not to dive into that.


### 7. Overhead

This one applies to both parallel and distributed implementations: coordinaation is expensive

Every time you add distribution, you add:
- Network latency (HTTP requests aren't free)
- Serialization overhead (JSON encoding/decoding)
- Coordination logic (task assignment, heartbeats)
- Failure modes (network issues, crashed workers)

My sequential version is simple and fast, which works.
My parallel version is faster for large data, but slower for small data due to thread overhead. My distributed version scales horizontally, but adds even more overhead.

So start simple and distribute only when needed. If your data fits on one machine, a parallel implementation is probably enough. Distribution is for when you have more data than one machine can handle, not just because it sounds cool.

### 8. Data Placement

One thing I really understood through implementation was that data locality matters.

In my distributed version:
- Map tasks run wherever, on data sent from master
- Intermediate files written by workers are accessible to master only via shared filesystem on localhost
- Reduce tasks download data over HTTP from master

Every piece of data moved over the network costs time. At scale, this dominates computation time.

I read that Hadoop's HDFS stores data in blocks across machines. So when you run a map task, Hadoop schedules it on the machine that already has the data which essentially means there's zero network transfer for input.

This is impossible in my implementation because I'm using a centralized master with local disk. Distributed file systems solve this, but they're complex to build.

This project gave me a deep appreciation for what other distributed systems handle:

- **Fault tolerance**: What happens when workers die?
- **Stragglers**: Some tasks take way longer - how do you handle it? (speculative execution)
- **Data locality**: Moving computation to data instead of vice versa
- **Memory management**: Spilling to disk, compression, serialization
- **Resource management**: YARN, Mesos, Kubernetes integration

Reading the Google paper, everything sort of makes sense. But implementing it yourself is where you discover all the subtle details they didn't explicitly mention. The algorithm itself is straightforward. Making it actually work efficiently at scale is the hard part.

Key takeaways:
1. Start simple - Sequential first, then parallel, then distributed
2. Measure everything - You can't optimize what you don't measure
3. Understand bottlenecks - In my case, disk I/O in the reduce phase
4. Scale matters - Algorithms perform differently at different scales


Obviously, all of this is over-engineered for word count. That's the point. It's a learning project, a playground for distributed computing concepts. The MapReduce paper gives you the blueprint, all of this is to give myself the understanding.

*Note: My implementation is in C#/.NET, but the concepts and architecture apply to any language. The same approach works in Python, Java, Go, or whatever you're comfortable with. The core algorithms and distributed systems patterns are language-agnostic.*

## References

If you want to dive deeper:
- **MapReduce: Simplified Data Processing on Large Clusters** (Google, 2004) - The original paper that started it all. Read this first.
- **Designing Data-Intensive Applications** by Martin Kleppmann - Excellent chapter on batch processing systems

The Google MapReduce paper is surprisingly readable and much shorter than you'd expect (13 pages).If you haven't read it yet, grab it.