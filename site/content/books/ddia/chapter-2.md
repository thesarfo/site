---
title: "Data Models and Query Languages"
number: 2
book: ddia
---

*Data models are the most important part of any software system, because they determine how we think about the problem we are solving, and this chapter surveys the major families of data models, the query languages that accompany them, and the trade-offs that guide which one to choose.*

---

### 2.1 Relational Model Versus Document Model

#### The Birth of NoSQL

For decades, the relational model and SQL dominated data management so completely that alternatives were barely considered outside niche domains. Then, starting around 2010, a new generation of databases collectively labeled NoSQL emerged with a handful of driving motivations. Some teams wanted greater scalability than relational databases could provide, including very large datasets and very high write throughput. Others chafed against the rigidity of relational schemas, preferring a free and open-source software model over expensive commercial database products, or finding that their data simply did not fit neatly into tables. Finally, a growing frustration with the object-relational mismatch pushed developers toward data models that aligned more naturally with the object-oriented programming languages in which their application code was written.

#### The Object-Relational Mismatch

Most application code is written in object-oriented languages such as Java, Python, or Ruby, yet most relational databases require data to be stored in tables of rows and columns. Translating between these two representations requires an awkward translation layer, an object-relational mapping, or ORM, that consumes developer effort and runtime performance. The mismatch is especially painful when an application needs to store a complex, nested data structure such as a résumé (with its sections, positions, education entries, and contact information, all nested to varying depths). In a relational database, representing this requires many tables with foreign keys and joins, whereas a document database like MongoDB can store the entire résumé as a single JSON document that mirrors the in-memory data structure the application already uses. This one-to-one mapping between an application object and a database document removes the translation layer, improving both developer productivity and read performance for the common case where the entire document is loaded at once.

#### Many-to-One and Many-to-Many Relationships

The document model works beautifully when data relationships are tree-shaped and the entire tree is loaded together, but it stumbles when relationships become many-to-one or many-to-many. Consider a résumé that lists a person's region of residence as a plain-text string like "Greater Seattle Area." If you later want to standardize all regions, or associate metadata with each region, you encounter the problem that the same value is duplicated across thousands of documents. In a relational database you would normalize this by creating a separate regions table with a foreign key reference, making it trivial to update the region name once or to join against it. Document databases offer no native join, forcing the application to emulate joins in code, which is typically slower, more error-prone, and loses the database's ability to optimize access paths. The deeper insight is that many-to-one and many-to-many relationships are the norm in data modeling, not the exception, almost every interesting dataset contains them, and a data model that handles them poorly will eventually become a liability.

#### Are Document Databases Repeating History?

Kleppmann draws a striking historical parallel between the document databases of today and the hierarchical database model (exemplified by IBM's IMS) that dominated the 1970s. The hierarchical model represented data as nested records in a tree, exactly as document databases do, and it struggled with many-to-many relationships for exactly the same reasons. The solution proposed at the time was the network model (standardized by CODASYL), which allowed records to link to one another through pointers, enabling many-to-many relationships but at the cost of forcing developers to navigate access paths by hand, a kind of manual, low-level traversal that made code complex and brittle. The relational model, by contrast, swept these concerns away with a deceptively simple abstraction: data is stored in tuples (rows), relationships are represented by values (foreign keys), and the query optimizer automatically chooses the best access path for any given query at runtime. This separation of logical data layout from physical access paths was the relational model's greatest innovation, and it remains unmatched by document databases today.

#### Relational Versus Document Databases Today

The practical conclusion is that neither model is universally superior, and the choice depends on the shape of your data. If your application works with tree-structured, self-contained documents that are mostly loaded as a unit, a document database is an excellent fit and will simplify your code. If your data contains many many-to-many relationships that require joins, or if you expect to run ad hoc analytical queries whose patterns you cannot anticipate in advance, a relational database is the safer choice. A hybrid approach is increasingly common: a relational database with JSON column types (PostgreSQL, MySQL) that combine the schema flexibility of documents with the join power of the relational model, or a document database that is gradually adding join capabilities. The convergence of the two models suggests that the debate is less about ideology and more about pragmatism.

---

### 2.2 Query Languages for Data

Kleppmann draws a crucial distinction between imperative and declarative query languages. An imperative query tells the database exactly how to retrieve the data, step by step, looping through records, checking conditions, and maintaining state, much like writing procedural application code. A declarative query, by contrast, describes only what data you want and leaves the how entirely to the database's query optimizer. SQL is the archetypal declarative query language, and its great strength is that it lets the database choose the most efficient execution plan based on the available indexes, the distribution of data, and the current system load, all without changing a single line of application code. Declarative languages also tend to be more concise and easier to read, and because they specify only the desired outcome rather than a particular execution order, they are more amenable to parallel execution.

#### Declarative Queries on the Web

The author draws an illuminating analogy between SQL and declarative front-end programming: just as SQL hides the details of index lookups and join algorithms from the user, CSS and modern JavaScript frameworks hide the details of DOM manipulation. You declare what the page should look like, and the browser or framework figures out how to make it so. The parallel underscores a broader principle of good software architecture, that high-level, declarative interfaces produce systems that are easier to reason about, easier to optimize, and easier to change.

#### MapReduce Querying

MapReduce represents a middle ground between purely imperative and purely declarative querying. A MapReduce query consists of two user-defined functions, map and reduce, that are expressed in a general-purpose programming language and must obey certain purity and structure constraints. The map function emits key-value pairs from each input record, the framework groups all emitted pairs by key, and the reduce function processes each group to produce the final output. MapReduce sits somewhere between the flexibility of imperative code and the constrained structure of a declarative language: it gives you more power than SQL for arbitrary computation, but it forces you to contort your logic into the map-reduce pattern and often requires far more code than an equivalent SQL query would. MongoDB's built-in MapReduce support, and the later addition of a simpler aggregation pipeline, illustrate the practical trade-offs: the aggregation pipeline is declarative and optimizer-friendly, while MapReduce is powerful but verbose and hard to maintain.

---

### 2.3 Graph-Like Data Models

When many-to-many relationships become the dominant feature of a dataset, when everything is connected to everything else and the connections are as important as the data itself, neither relational nor document models are a natural fit. Graph databases are explicitly designed for this case.

#### Property Graphs

The property graph model, implemented by Neo4j, Titan, and others, structures data as vertices (nodes) and edges (relationships). Each vertex has a unique identifier, a set of outgoing edges, a set of incoming edges, and a collection of key-value properties. Each edge has a unique identifier, a label that describes the relationship type, a head vertex and a tail vertex, and its own collection of key-value properties. This uniform structure makes it trivial to model social networks (people connected by friendship, workplace, and school relationships), web graphs, recommendation engines, and any domain where the relationships between entities carry semantic weight. The power of graph databases lies not in storing this data, you could store vertices and edges in relational tables, but in the efficiency with which they traverse paths of arbitrary length across the graph, something that would require a prohibitive number of recursive joins in SQL.

#### The Cypher Query Language

Cypher, the query language of Neo4j, is a declarative language tailored to graph traversal. Queries are expressed using ASCII-art–like patterns: `(person)-[:LIVES_IN]->(city)` describes a pattern of two vertices connected by a labeled edge, and the query engine finds all matching subgraphs in the database. Cypher's design philosophy is that the syntax should visually resemble the structure of the data being queried, which makes even complex traversals, such as "find all friends-of-friends who live in London and like the same music as me", readable and compact. The same query in SQL would require multiple recursive common table expressions and would be both difficult to write and difficult to optimize.

#### Graph Queries in SQL

It is possible to query graph-structured data in a relational database using recursive common table expressions (CTEs), which the SQL:1999 standard introduced and which PostgreSQL, SQL Server, and Oracle all support. A recursive CTE can traverse an edge table by repeatedly joining it against itself until a termination condition is met. However, Kleppmann argues that the SQL syntax for this is verbose and obscures the intent of the query, and that the query optimizer struggles to generate efficient execution plans for recursive traversals of variable depth. Graph databases, by making traversal a first-class operation, achieve both greater expressiveness and better performance for these workloads.

#### Triple-Stores and SPARQL

The triple-store model is a more granular decomposition of the property graph: all data is represented as subject-predicate-object triples, where the subject is a vertex, the predicate is an edge label or a property key, and the object is either another vertex or a literal value. This model descends from the Semantic Web and RDF (Resource Description Framework) traditions and is queried using SPARQL, a declarative language that matches patterns of triples. SPARQL queries look superficially similar to Cypher but are built on a different foundation: the RDF data model assumes that every resource is identified by a URI, making it well-suited for data integration scenarios where entities from different datasets need to be merged unambiguously.

#### The Foundation: Datalog

Datalog is a declarative logic programming language that predates SQL and provides an even simpler foundation for querying data. A Datalog program consists of rules, each of which defines a new predicate as a logical conjunction of existing predicates, with variables that are implicitly joined across the rule body. A recursive rule enables transitive closure, the ability to follow a relationship any number of hops, in just a few lines of code that are far more compact and mathematically elegant than the equivalent recursive CTE in SQL. Datalog's approach of building up complex queries from small, composable rules inspired later graph query languages (Cypher's pattern matching descends from Datalog's unification), and its constraint that rules must be monotonic, new facts can only add to, never contradict, what is known, ensures termination and makes it a safe foundation for deductive databases and incremental view maintenance.

---

### Chapter Summary

Data models are not merely implementation details; they are the lens through which we see the problem domain, and the wrong model forces the developer into a constant battle against the database's fundamental abstractions. The relational model has endured for forty years because it cleanly separates logical data layout from physical access paths, handles many-to-many relationships gracefully, and supports a powerful declarative query language. The document model offers a simpler programming model when data is tree-shaped and self-contained. Graph models excel when the connections between entities are as important as the entities themselves. Each model comes with its own query language, SQL, MapReduce, Cypher, SPARQL, Datalog, that reflects and reinforces the model's assumptions. The practical engineer's task is not to declare allegiance to one model but to understand the trade-offs each embodies and to match the model to the shape of the data and the pattern of queries the application demands.

