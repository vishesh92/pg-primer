# Intro - What is this doc?
Its hard trying to manage a postgresql database by yourself especially when you have little experience with databases.
We will discuss
- a little bit of postgresql internals like storage structure on disk
- routine operations?
- moving around postgres using psql
- our monitoring & reporting setup
- and finally finding out & resolving common issues using


# A little brief of MVCC and basic architecture/internals of postgres.
## What is MVCC?
PostgreSQL is a relational database. To provide concurrent access to the database, MVCC is used. Without this, if someone is writing to database, someone else accesses this data during the same time, he would see missing or inconsistence piece of data. MVCC helps you provide *Isolation* which gurantees concurrent access to data.

## How postgresql implements MVCC?
https://medium.com/learning-with-diagrams/learning-w-diagrams-handling-contention-with-postgresql-109798b8ad54
** Create a simple diagram to explain how MVCC basically works in postgres.
https://www.youtube.com/watch?v=GtQueJe6xRQ

## VACUUM
Because of how MVCC is implemented, tuples that are updated & deleted in a table are not physically deleted from their table. This results in increase in size of tables if vacuum is not run frequently on that table. To handle this increasing storage, you can run `VACUUM` manually or make sure `autovacuum` is running. `VACUUM` goes through each table and marks the older versions of tuples for deletion. `VACUUM` doesn't free up disk space, but can be reused for future inserts on this table. To free up disk space and completely remove bloat from that table, you can run `VACUUM FULL` but it takes an exclusive lock on that. Its not recommended to run `VACUUM FULL` on a production database.

# psql cheat sheet
psql is the official CLI shipped with postgresql. Its really important to know how to move around a database and psql is a perfect tool for that.

## List users & roles
```
\du
```

## List databases & their size
```
-- for listing databases
\l

-- for listing databases with additional info including size
\l+
```
You can also list databases which match a pattern. For example, the below command will list add databases which have `abc` as part of their name.
```
\l *abc*
```

## Change database
```
\c[onnect] {[DBNAME|- USER|- HOST|- PORT|-] | conninfo}
```
You can use this to connect to another postgresql host or even another database on that host. For example, the command below will connect to `pg_bench` database on the same host.
```
\c pg_bench
```

## List tables & their size
```
-- for listing tables
\dt

-- for listing tables with additional info including size
\dt+
```
Similar to databases, pattern search works here as well.
```
\dt+ *abc*
```

## Toggle expanded output
Sometimes, the output of query doesn't fit the window and its hard to read/understand the result. Expanded output helps in these cases.
```
\x
```
If you want to make this switch between expanded view automatically, use this.
```
\x auto
```

## Describe table, view, sequence, or index
A lot of times, while debugging an issue, you need to know the schema of a table or a view.
```
\d {name}
```

## Edit, query execution and query output
```
-- execute commands from a file
\i {file_path}
-- send query's outputs to file
\o {file_path}
-- to revert back to stdout
\o
-- edit last query in buffer
\e
-- show last query in buffer
\p
-- save last query in buffer to file
\w file_path
-- show query history
\s
-- to save history to file
\s {file_path}
-- execute last query periodically (default: 2s)
\watch {period_in_seconds}
-- query execution time
\timing
```

## .psqlrc
You can place a .psqlrc file at `~/.psqlrc` to customize psql.
```
\set QUIET 1

-- print null as "[null]" in output. Its useful while debugging since empty string & null show up as same in output
\pset null '[null]'

-- autocomplete words are in upper case
\set COMP_KEYWORD_CASE upper

-- print time taken by query for execution
\timing on

\set HISTSIZE 2000

-- switch to expanded output depending on output length
\x auto

\set VERBOSITY verbose

\set HISTCONTROL ignoredups

\set QUIET 0

```
More details here: https://wiki.postgresql.org/wiki/Psqlrc

## Help page for syntax of SQL commands
```
\h SELECT
```

It is a little hard to remember all the slash commands when starting out. Use `\?` to get a list of all slash commands in psql even the ones not covered above.

# Monitoring, observability & reporting
## pgbadger
Its a tool which parses logs and generates a report from them. You can use this to find out slow queries and fix those by creating indexes or tuning postgresql parameters.

## RDS Performance Insights
This is a feature of RDS which shows you running queries in real time.

## Grafana dashboard
- CPU (CPU Credits)
- Memory
- Connections
- Burst Balance & IOPS

# Identifying common issues using above
Run [queries/connections_per_user.sql](queries/connections_per_user.sql) and check if `max_running_time` is high for `state` - `active` and `idle in transaction`. There is a problem if:
 - Number of connections or `max_running_time` for queries in `active` or `idle in transaction` state is high. `high` is subjective here and depends on the database size and type of workload. In my experience, number of `active` connections should be less than number of database's cpu cores and `max_running_time` should be less than 1 second.

## Debugging further
 * If time for `idle in transaction` queries is high, then
    - either your application is taking time to commit transactions because its under heavy load or is doing some time consuming task before committing. Or application is not handling transactions properly.
    - some dev started a transaction and didn't commit it and left the connection open
 * If time for `active` queries is high, then
    - Queries are in waiting state. Queries can be in waiting state for multiple reasons. In [queries/active_running_queries.sql](queries/active_running_queries.sql) output, check `wait_event_type` and `wait_event` to figure out why the query is in waiting state. Reference: https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE (Its better to check documentaton for postgres version you are workng with). Most of the time, its because:
      - two or more connections are working (lock) on the same row.
      - Someone executed some migrations and because of an `idle in transaction` or `active` query, this DDL query took a lock on that table preventing queries on table.
    - Query is expensive and is taking time. In this case `wait_event_type` and `wait_event` is null or its taking time to read data from disk (`wait_event_type` is `IO`). If the number of queries is also high, your database is probably under high CPU Utilisation. Fix for this is:
      - check if an index is missing. You can use `EXPLAIN` and `EXPLAIN ANALYZE` (NEVER USE `EXPLAIN ANALYZE` for a query which will modify data. This actually executes the query.)
      - providing more memory so that indexes can fit into memory or data can be cached into memory. For this, check disk reads. If its high, tune params (work_mem, shared_buffers, effective_cache_size) or increase memory for the instance.
      - increase CPU because the number of queries executed per second is high.

Having queries in `idle in transaction` state can cause a lot of issues in the long run. Because a query is in `idle in transaction` state and that connection holds a lock on a table, `VACUUM` won't run on that table because of which the size of that table will keep on growing.

# Performance Tuning?
- connection pooling
Every postgresql connection is a forked process on postgresql. Lots of connections & disconnections can result in increased CPU Utilization of your database. Setting up a connection poolers like pgbouncer can create a lot of impact in performance.
- indexes?
One of most common problems which can result in low performance is the missing indexes. Using pgbadger you can identify slow queries and identify tables which are missing indexes. Postgresql provides a variety of indexes (btree, brin, gin, etc.).
- parameter tuning
I have seen people vertically scale postgres to without even understand the root cause. Its really important to tune your parameters to gain significant performance benefits. You can generate a default configuration using https://pgtune.leopard.in.ua/.
