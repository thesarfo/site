---
title: "Encoding and Evolution"
number: 4
book: ddia
---

Data outlives code. Old and new versions coexist in databases, APIs, and message queues. Encoding is how you turn in-memory data into bytes; evolution is how you change that encoding without breaking readers or writers.

**Formats.** Language-specific serialization (Java Serializable, Python pickle) locks you into one language and is a security risk. JSON/XML are human-readable but have real problems: no binary strings, no integers beyond 2^53, no enforced schema. Thrift and protobuf fix this with numeric field tags and a compiled schema, smaller, faster, and evolution-friendly (never reuse or rename a tag). Avro goes further: no tags at all, just values in schema-defined order. Writer and reader schemas are resolved at runtime. Best for dynamically generated schemas (ETL pipelines).

**Data flow.** Through databases: old and new code read the same rows. The hard requirement is fidelity, old code rewriting a row must not drop fields it doesn't know about. Most ORMs fail this. Through services: REST is best for public APIs (stateless, content negotiation). RPC makes remote calls look local, which is a lie (timeouts, duplication, unpredictable latency). gRPC and Finagle mitigate the worst of it, but the lie remains. Through message brokers (Kafka, RabbitMQ): the hardest scenario because a topic can hold messages from many schema versions consumed by many code versions. Schema registries solve this.

**Synthesis.** Every encoding decision is about coupling. Schema-based binary formats when you need evolution rigor; JSON when human-readability matters. REST for public APIs, RPC for internal services, message brokers as databases with pub-sub. Be explicit about the contract.
