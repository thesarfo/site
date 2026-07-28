---
title: "Data Models and Query Languages"
number: 2
book: ddia
---

**Relational vs Document.** NoSQL emerged around 2010 driven by scalability limits, schema rigidity, and the object-relational mismatch. Document model (MongoDB) maps naturally to nested objects like résumés. But it struggles with many-to-one and many-to-many relationships, exactly the problem the hierarchical model (IBM's IMS) had in the 1970s. The relational model solved that by separating logical data layout from physical access, and it's still the right call when you need joins and ad-hoc queries.

Neither is universally better. Use documents for tree-shaped self-contained data. Use relational for anything with joins. Hybrid approach (PostgreSQL with JSON columns) is increasingly common.

**Query languages.** Declarative (SQL, CSS) says *what* you want; the system figures out *how*. Imperative says every step. Declarative is shorter, easier to read, and parallelizable. MapReduce is a messy middle ground, more flexible than SQL, but verbose and hard to maintain.

**Graph models.** When connections are as important as the data itself, reach for a graph database (Neo4j). Property graphs have vertices and labeled edges, each with key-value properties. Cypher queries look like ASCII-art patterns. Recursive CTEs in SQL can do the same thing but are painful. Triple-stores (RDF/SPARQL) come from the Semantic Web and are optimized for merging datasets. Datalog is the cleanest foundation of all, small, composable rules that can express recursive queries elegantly.
