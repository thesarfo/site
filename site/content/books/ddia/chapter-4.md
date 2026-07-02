---
title: "Encoding and Evolution"
number: 4
book: ddia
---


## The Core Problem

Data outlives code. An application writes data today that will be read by a future version of itself, by a different service, or by a consumer that cannot be upgraded on the same schedule. Old and new versions coexist constantly, in databases, in APIs, in message queues, and the system must function correctly despite this heterogeneity. Encoding (serialization) translates in-memory data structures into a transmissible byte sequence; evolution is the set of rules that allows that encoding to change over time without breaking readers or writers.

---

## Encoding Formats

### Language-Specific Formats

Languages provide built-in serialization (Java's `java.io.Serializable`, Python's `pickle`, Ruby's `Marshal`), but Kleppmann rejects these for any long-lived data system. They lock you into a single language, carry serious security risks (deserializing attacker-crafted payloads can execute arbitrary code), and handle forward or backward compatibility poorly because they assume the same code version will both write and read the data.

### JSON, XML, and Binary Variants

JSON and XML dominate as textual formats because they are human-readable, broadly supported across languages, and self-describing, field names are embedded in the document, so partial interpretation is possible without an external schema. Their weaknesses are significant: JSON's number type is a double-precision float that cannot exactly represent integers beyond approximately 2^53, neither format natively supports binary data (forcing Base64 encoding with a roughly 33% space overhead), and optional schema languages like JSON Schema are inconsistently adopted, meaning most JSON is exchanged with no formal contract. Both are also verbose and relatively slow to parse. Binary JSON variants (BSON, MessagePack, etc.) achieve modest space savings but still carry field names in every record and lack a rigorous schema system.

### Thrift and Protocol Buffers

Apache Thrift and Protocol Buffers (protobuf) represent a decisive advance. Both require a schema written in an interface definition language (IDL), from which a compiler generates encoding and decoding code in multiple languages. Each field is assigned a numeric tag; the wire format carries the tag, not the field name, which dramatically reduces size and is the mechanism that enables evolution. A decoder encountering an unfamiliar tag simply skips it and supplies a default value for missing fields. This gives both formats robust forward compatibility (new code reads old data) and backward compatibility (old code reads new data) as long as field tags are never changed or reused, fields are only added with fresh tags, and removed fields' tags are permanently reserved. Thrift offers two wire formats (BinaryProtocol and CompactProtocol), while protobuf uses a single variable-length encoding. In both cases, the schema *is* required to interpret the bytes; no field names appear on the wire.

### Avro

Apache Avro takes a fundamentally different approach: the schema is not compiled into the code. Instead, the writer's schema (the schema used to encode) and the reader's schema (the schema expected by the decoder) are both available at runtime, and Avro resolves differences dynamically. The wire format carries no field tags at all, just a sequence of values in the order specified by the writer's schema. The reader must therefore have access to the writer's schema to decode. In a file, the writer's schema is stored once at the beginning; in a database, it can be stored alongside each row; in an RPC, it can be negotiated at connection setup. Avro matches fields by name rather than position or tag, which allows fields to be reordered freely and makes the system more flexible for schema changes, though field names must remain unique and stable (aliases are supported). Avro's particular strength is dynamically generated schemas: if you need to dump a database table to files, Avro can generate the schema from the table definition at runtime without any code-generation step, making it ideal for ETL pipelines and bulk data transfer.

### Why Schemas Matter

Kleppmann argues explicitly that schema-based binary formats are superior to schema-less textual formats for serious data systems. A schema provides compactness (numeric tags instead of field names), a machine-checkable documentation artifact, and a precise, statically-checkable evolution contract. The common objection, that schemas are rigid, is mistaken: an explicit, versioned schema is more flexible than the implicit, undocumented, and inconsistently enforced expectations that arise when teams exchange JSON without any formal contract.

---

## Modes of Data Flow

### Through Databases

When an application writes to a database, it encodes in-memory data into the database's storage format. Over years, different application versions write rows with slightly different schemas, and the database becomes a repository of schema history. The critical requirement is *fidelity preservation*: if a new version adds a field and writes it, an old version reading that row must decode it without crashing (backward compatibility). If the old version then writes the row back after updating an unrelated column, it must preserve the unknown field intact rather than dropping it. Many ORMs fail this test by decoding a row into an object with only currently-known fields and re-encoding only those fields, silently destroying unknown data. The solution is an encoding layer that stashes unknown fields in an opaque container and re-serializes them verbatim. Relational databases enforce a single schema per table, requiring migrations (ALTER TABLE) to be carefully sequenced, add the column first, then deploy the code that writes to it. Document databases without a fixed schema avoid this sequencing but force the application to handle data that may be missing expected fields or contain unexpected ones.

### Through Services: REST and RPC

**REST** is a design style using HTTP, where resources identified by URLs are manipulated through a constrained set of verbs (GET, POST, PUT, DELETE). Its evolution strength lies in statelessness, HTTP content negotiation (clients request a version via Accept headers), and the discipline of never removing fields that existing clients depend on. REST suits public, long-lived APIs where client evolution is outside the provider's control.

**RPC** tries to make a remote call look like a local function call. Kleppmann catalogs why this analogy is fundamentally broken: a network call can time out, be duplicated, or lose requests or responses; latency is unpredictable (milliseconds to seconds versus nanoseconds for local calls); arguments must be marshaled by value, making large object graphs expensive; and caller and callee may run different versions simultaneously. Frameworks like gRPC (using protobuf) and Finagle (using Thrift) mitigate these issues with timeouts, retries, and circuit breakers, but the truth remains that a remote call is not a local call. RPC fits internal services within a single organization where both sides can evolve in a coordinated way. SOAP, the over-engineered XML-based RPC protocol of the early 2000s, serves as a cautionary tale of what happens when a protocol tries to solve every problem at once.

### Through Message Brokers

Asynchronous message passing (Kafka, RabbitMQ, ActiveMQ) decouples sender from receiver along three axes: the producer does not need to know which process will consume the message, the two do not need to run simultaneously, and the producer does not wait for the consumer because the broker buffers messages. This is the most demanding evolution scenario because a single topic can contain messages encoded with many different schema versions simultaneously, consumed by multiple consumers running different code versions. Schema registries, centralized services that store schema versions and enforce compatibility rules, have become the standard solution in Kafka architectures and integrate naturally with Avro's runtime schema resolution. Kleppmann deliberately blurs the line between message brokers and databases: both store data over time, both are shared across processes, and both demand the same disciplinary approach to schema evolution.

---

## Synthesis

Every design decision about encoding and data flow is ultimately a decision about coupling. Language-specific serializers couple data to a language. RPC frameworks that hide network failures couple the caller to the illusion of locality. Databases that drop unknown columns couple every reader and writer to the same application version. The antidote is an explicit, well-defined encoding layer that acknowledges the separation between processes, versions, and time, and is designed to let each side evolve independently. Use schema-based binary formats (protobuf, Thrift, Avro) when compactness and evolution rigor matter; use JSON when human-readability and interoperability take priority. Prefer Avro when schemas are dynamically generated or when producers and consumers are loosely coordinated; prefer protobuf or Thrift when compile-time type-checking is more valuable. Treat REST as the default for public APIs, RPC for internal services, and message brokers as databases with a pub-sub access pattern, applying the same schema-evolution discipline to all three.

