---
title: "What I Learned after building my own ORM"
date: 2025-10-14
excerpt: "What I learned building an ORM library."
tags: ["engineering"]
---
A few months back, I started working on an ORM library called Dozer, and it turned out to be one of the most educational projects I've done in a while

## Why I Did This

I've been using Entity Framework Core for a while now, and honestly, it always felt a bit much? It's very simple to use, you define some classes, add some attributes, write some LINQ queries, call `SaveChanges()`, and somehow your data ends up in the database. But honestly I had no idea how any of it actually worked.

What happens when you call `SaveChanges()`? How does it know which properties changed? How does it turn my LINQ expression into SQL? These questions kept ringing in my head, so I decided to find out by building my own version from scratch, albeit a dumbed down one.

My goal wasn't to build something production-ready or to "compete" with EF Core. I just wanted to understand the core concepts well enough that I could look at EF Core and think "oh yeah, I know why they did that."

## Starting Simple: Attributes and Reflection

I started with the basics - custom attributes. You know those `[Table]` and `[Key]` attributes you put on your entity classes? I needed to create my own versions and then use reflection to actually read them.

This was my first real dive into reflection in C#. I'd used it before for small things, but never this extensively. Learning how to scan a class for properties, read their attributes, and dynamically get/set their values was eye opening. 

I realized that at runtime, classes are just data structures you can inspect and manipulate. Once you wrap your head around that, reflection becomes less mysterious.

## Turning Classes into SQL

The next thing was generating SQL from these entity classes. I needed to take a `User` object and turn it into `INSERT INTO Users (UserName, Email) VALUES (@UserName, @Email)`.

This is where I learned about parameterized queries the hard way. My very first version just concatenated values into the SQL string, which worked until I tried inserting a user with a quote in their name. Then it broke, and I got why SQL injection is such a big deal. I rewrote this part with ADO.NET's parameter system, which was very tedious but necessary. Each property value becomes a parameter with a name like `@Email`, and you bind the actual value separately. It's verbose, but it's safe. I also had to handle different data types - mapping C# types like `int`, `string`, `DateTime`, and `decimal` to their SQL equivalents. This seems straightforward until you hit edge cases like nullable types or enums.

## Building a Query API

Writing raw SQL strings obviously felt primitive, so I wanted something nicer. So I built a fluent query API where you could chain methods together:

```csharp
var users = db.Query<User>()
    .WhereEquals("UserName", "john")
    .OrderBy("Email")
    .Limit(10);
```

Which translates to:

```sql
SELECT * FROM Users 
WHERE UserName = @UserName 
ORDER BY Email 
LIMIT 10;
```

Each method returns the query builder itself, so you can keep chaining. Internally, I'm just collecting all these conditions and building up the SQL string piece by piece.

This was fun to build because it feels so clean to use, but it's still just string manipulation behind the scenes. I didn't implement full LINQ support (that would require parsing expression trees, which I'll get to later), but even this simpler version taught me a lot about API design.

## The Hard Part: Change Tracking

This is where things became very challenging. When you load a user, modify their email, and call `Update()`, how exactly does the ORM know that only the email changed? You don't want to update every single column when only one changed.

I had to implement a change tracking system. The approach I took:
- When an entity is loaded, store a snapshot of all its property values
- When you call `Update()`, compare current values to the snapshot
- Only generate SQL for properties that actually changed

Before settling on this, I considered a few other approaches:

**Proxy-based tracking**: I generate dynamic proxy classes that inherit from my entities and override property setters to track changes automatically. This is what EF Core does with lazy loading proxies. I decided against this because creating dynamic types at runtime felt too complex for my first attempt, and debugging would be too much of a chore.

**Dirty flags**: I add a boolean flag to each property that marks it as "dirty" when changed. Simple in concept, but it meant modifying all my entity classes or using a base class, which felt invasive? Plus, it doesn't work well with plain POCOs (Plain Old CLR Objects), which was one of the things I wanted to support.

**INotifyPropertyChanged**: Or I just use the standard .NET event pattern where entities raise events when properties change. I suppose this is clean and also follows established patterns, but it means all entities have to implement the interface and raise events manually. Too much boilerplate for users of the ORM.

I went with snapshot comparison because it's non-invasive(I don't have to do too much) - entities don't need to inherit from base classes, implement interfaces, or follow any special patterns. They're just plain classes. The downside is memory overhead (storing two copies of data), but for a learning project, the simplicity is worth it.

This approach meant that I store original values in a dictionary, implement proper equality comparisons, and manage entity states (Added, Modified, Deleted, Unchanged).

The tricky part was handling entity states correctly. An entity just inserted is "Added", one loaded from the database is "Unchanged", one you've modified is "Modified", and so on. Getting all the state transitions right took some trial and error.

Over here I understood why EF Core makes you call `SaveChanges()` - it needs a single point where it can examine all tracked entities, figure out what changed, and generate the appropriate SQL. Without that, it would need to hit the database on every property change, which would be terribly slow.

## Preventing Duplicate Entities

The next pattern I learned about was the identity map. The idea is simple: if you load the same user twice, you should get back the exact same object instance, not two different copies.

```csharp
var user1 = db.FindById<User>(1);
var user2 = db.FindById<User>(1);
// user1 and user2 point to the same object
```

I implemented this with a cache - a `Dictionary<object, T>` keyed by the primary key. Before querying the database, check the cache. If the entity is there, return it. Otherwise, load it and add it to the cache.

This pattern prevents memory bloat (no duplicate objects) and maintains consistency. If you change `user1.Email`, the change is visible through `user2` because they're the same object. It's a clever solution to referential integrity within a single context.

## Supporting Async

Adding async/await support was more straightforward than I expected. ADO.NET has synchronous methods like `ExecuteReader()`, so I wrapped them in `Task.Run()` to make them awaitable.

The bigger lesson was getting why async matters for database operations. Databases are I/O-bound - your code spends most of its time waiting for the database to respond, not actually processing data. With async, you free up threads to handle other requests while waiting, which is important for web applications that need to scale.

## Some Unexpected Scenarios

A few things surprised me during this project:

The amount of edge case handling required was way more than I expected. Null values, missing primary keys, entities without parameterless constructors, connection management - there are just so many things that can go wrong.

How much ORMs do automatically that I never think about. EF Core handles relationship cycles, lazy loading, proxy generation, connection pooling, retry logic, and so much more. My version made me appreciate all that hidden complexity.

The performance implications of different design choices. Reflection is slow, so caching is essential. Round trips to the database add up, so batching matters. These aren't theoretical concerns - they directly impact whether your ORM is usable or not.

## What I Didn't Build

I intentionally skipped some features that would have been too complex for a learning project:

**LINQ Expression Trees**: Parsing `Where(u => u.Age > 18)` requires walking the expression tree, extracting the property access (`u.Age`), the operator (`>`), and the value (`18`), then translating all of that to SQL. It's doable, but it's a whole project on its own. So mybe next time.

**Navigation Properties**: Handling relationships between entities - foreign keys, joins, lazy loading, eager loading - is where ORMs get really complex. I stuck with single-table operations to keep things manageable.

**Migrations**: A proper migration system requires comparing database schemas, generating diff scripts, tracking which migrations have been applied, and handling rollbacks. Skill issue.

## What I Learnt

The takeaway is that ORMs are just code that:
- Uses reflection to read class metadata
- Generates SQL strings based on that metadata
- Manages a cache of loaded entities
- Tracks what changed and generates appropriate UPDATE statements

It's clever engineering, but it's not magic. Understanding this makes me better because now I can make informed decisions about when to use an ORM and when to drop down to raw SQL.

I also learned to appreciate abstractions more. Yes, you can write raw SQL for everything, and sometimes you should. But for standard CRUD operations, having an ORM generate that boilerplate for you is genuinely valuable.

Another insight: building something from scratch teaches you way more than reading about it. I could have read articles about how ORMs work, but actually implementing change tracking myself made it click in a way that reading never would have.


If you're curious about how anything works, absolutely build one. You don't need to build the next big thing, a simple version with basic functionality is enough to learn the fundamentals.


I published Dozer to NuGet as `Dozer.Core`, mostly as a milestone for myself. It's functional and could work for simple projects, but it's definitely a learning tool rather than a production ORM.

I might add LINQ expression tree support next because that seems like the natural next challenge. Or I might dive into migrations because schema evolution is such a common pain point. Either way, I'm glad I built this. The next time someone asks "how do ORMs work," I can actually explain it.

If you've ever wondered how your favorite tools work under the hood, I highly recommend building simplified versions. You'll never look at them the same way again.

And hey, if you want to check out the code, it's [open source](https://github.com/thesarfo/dozer) and on NuGet. Fair warning though - it's an educational project, not a replacement for Entity Framework Core. But it might help you understand why EF Core does things the way it does.