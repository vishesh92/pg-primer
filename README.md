# Intro - What is this doc?
It's hard trying to manage a postgresql database by yourself especially when you have little experience with databases. I started by writing simple queries which were required for analytics. But the systems were also facing other issues which pushed me to delve deeper into postgres. The majority of the issues were quite simple and were there due to the lack of a DBA/DBRE. During my journey with postgres, I came across [Accidental DBA](https://github.com/pgexperts/accidentalDBA/). This helped me quite a bit at that time but there were still a few things that I picked up over the years. I wanted to write this document to share what I have learned over the years and make it a little easier for another Accidental DBA to work with postgres. Since I have primarily worked with RDS Postgres (managed postgres service provided by AWS), there might be a few things related to postgres setup missing here.

# Setting up postgres
To connect to postgres, you need psql or any other client which supports postgres. You can download psql (part of postgresql-client package) from [here](https://www.postgresql.org/download/) according to your operating system.

If you just want to play around with postgres, you can easily set it up on your local using [docker](https://docker.com/). You can install docker by following it's official documentation [here](https://docs.docker.com/engine/install/).

After setting up docker, run this command in your terminal to run a postgres container in the background.
```bash
docker run --name postgres-playground -d postgres
```
You can run this command connect to postgres once the container is ready.
```bash
docker exec -it postgres-playground psql -U postgres postgres
```
Stop and remove the container.
```bash
docker stop postgres-playground
docker rm postgres-playground
```

> The above setup is only for playing with postgres and is not for production use.

# A little brief of MVCC and architecture/internals of postgres.
## What is MVCC?
PostgreSQL provides concurrent access to the database using MVCC. Without this, if someone writes a row to a database and someone else accesses the same row simultaneously, they would see missing or inconsistent data.. MVCC helps you provide *Isolation* which guarantees concurrent access to the data.

![Isolation](./assets/isolation.svg)

Let's assume that a bank has only two users having 50$ each, the total balance in the bank being 100$. Now, user *A* transfers 50$ to user *B*. At T1, the bank manager would see 100$ as bank balance. At T3, the output would still be 100$ in this case because postgres provides isolation and both the transactions have a different view of that table.

## How PostgreSQL implements MVCC?
Every table in postgres has some additional [system columns](https://www.postgresql.org/docs/current/ddl-system-columns.html). *ctid* is one such column that stores the physical location of that row. You can use a query like this to get the ctid of a row.
```sql
SELECT ctid, * FROM <table name> LIMIT 10;
```
![MVCCImplementation](./assets/mvcc-implementation.svg)

Deleting a row updates the system columns for that row so that it's not visible for future transactions. Updating a row creates a new copy of the row and updates the previous row so that it's not visible for future transactions.

## VACUUM
Because of how MVCC is implemented, tuples that are updated & deleted in a table are not physically deleted from their table. This increases the size of tables if `VACUUM` is not run frequently on that table. To handle this increasing storage, you can run `VACUUM` manually or make sure `autovacuum` is running. `VACUUM` goes through each table and marks the older versions of tuples for deletion. `VACUUM` doesn't free up disk space, but can be reused for future inserts on this table. To free up disk space and completely remove bloat from that table, you can run `VACUUM FULL` but it takes an exclusive lock on the table.

> It's not recommended to run `VACUUM FULL` on a production database.

### MVCC Exercise
1. Create an empty table.
```sql
CREATE TABLE tbl (id bigserial primary key, col text);
```
2. Insert two rows and check their physical location.
```sql
INSERT INTO tbl(col) VALUES ('a'), ('b');
SELECT ctid, * FROM tbl;
```
3. Delete the row where col value is `a` and check their physical location.
```sql
DELETE FROM tbl WHERE col = 'a';
SELECT ctid, * FROM tbl;
```
4. Update the row where col value is `b` and check their physical location.
```sql
UPDATE tbl SET col = 'c' WHERE col = 'b';
SELECT ctid, * FROM tbl;
```
You will notice that the physical location of that row has now changed.

5. Run VACUUM FULL and check physical location of rows.
```sql
VACUUM FULL tbl;
SELECT ctid, * FROM tbl;
```
You will notice that the physical location has changed again after running `VACUUM FULL`.

## Additional Resources
* MVCC Unmasked by Bruce Momjian - [Slides](https://momjian.us/main/writings/pgsql/mvcc.pdf) | [Video](https://www.youtube.com/watch?v=gAE_MSQtqnQ)
* Postgres, MVCC, and you or, Why COUNT(*) is slow by David Wolever - [Slides](https://speakerdeck.com/wolever/pycon-canada-2017-postgres-mvcc-and-you) | [Video](https://www.youtube.com/watch?v=GtQueJe6xRQ)

# psql
psql is the official CLI shipped with PostgreSQL. It's good to know how to move around a database, especially during an incident and psql is a perfect tool for that. Check this [cheat sheet](./psql-cheat-sheet.md) to get familiar with psql.

# Query Optimisation
To fix the slow and poorly written queries to ensure optimal performance for your database, `EXPLAIN` and `EXPLAIN ANALYZE` are used to identify bottlenecks in query execution. Check [this](./sql-query-analysis.md) to get an idea of how queries get executed. After identifying the issue, you can create an index, rewrite the query, or add more resources depending on the use case.

# Monitoring, Observability & Reporting

## Opensource monitoring tools
You can set up one of these tools to get better visibility into your database:
* [pgwatch](https://pgwatch.com/)
* [pgMonitor](https://github.com/CrunchyData/pgmonitor)
* [Percona Monitoring and Management](https://www.percona.com/doc/percona-monitoring-and-management/)

You can also set up [pgbadger](https://github.com/darold/pgbadger), a tool that parses logs and generates a report on database usage and workload. You can use this to find out slow queries that need fixing or tune postgresql parameters for your workload. Since pgbgadger works on logs, you won't get a real-time view of your database instance.

## System metrics
There are a lot of metrics you might want to track, but these are one of the most important ones
- CPU
- Memory
- Connections
- IOPS

## Performance Insights in [AWS RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)

Performance Insights is a feature of RDS which shows you running queries in real-time.

# Index Types
Most of the time, the performance problems in a database are due to a missing index. There are different types of indexes available. And some might give good performance gains depending on the use case. By default, postgres creates a B-Tree index.

While creating an index, I try to follow these rules:
 * Don't create an index if it's not going to be used. Unnecessary indexes will slow down your writes.
 * `Multi-column indexes`: If your queries have multiple conditions, a [multi-column index](https://www.postgresql.org/docs/current/indexes-multicolumn.html) can help. The order of columns is matters here. Let's assume you have a table with the below structure with a B-Tree index on (col1, col2).
 ```sql
                           Table "public.tbl1"
 Column |  Type   | Collation | Nullable |             Default
--------+---------+-----------+----------+----------------------------------
 id     | integer |           | not null | nextval('tbl1_id_seq'::regclass)
 col1   | integer |           |          |
 col2   | integer |           |          |
Indexes:
    "tbl1_col1_col2_idx" btree (col1, col2)
```
If you make a query like:
   * `SELECT * FROM tbl1 WHERE col1 = 10 AND col2 = 20` - Index scan
   * `SELECT * FROM tbl1 WHERE col1 = 10` - Index scan
   * `SELECT * FROM tbl1 WHERE col2 = 20` - Sequential scan. Depends on the data distribution and the `WHERE` clause.
 * *Partial indexes*: If you know that a part of the `WHERE` clause would have a fixed condition. e.g. `WHERE active = TRUE AND col1 = ?` where `active = TRUE` is the only condition on the `active` column in your queries, you can create a [partial index](https://www.postgresql.org/docs/current/indexes-partial.html). Partial indexes are smaller in size and are more performant as well.
 * *Indexes on expressions*: You can create an index on an expression as well (e.g. `lower(textcol1)`). If queries on a table have some expressions, it's a good idea to create an index on that expression.

## Additional Resources
* [Index Types](https://www.postgresql.org/docs/current/indexes-types.html)
* [Get rid of your unused indexes!](https://www.cybertec-postgresql.com/en/get-rid-of-your-unused-indexes/)

# Identifying ongoing issues
Run [queries/connections_per_user.sql](queries/connections_per_user.sql) and check if `max_running_time` is high for `state` - `active` and `idle in transaction`. There is a problem if the number of connections or `max_running_time` for queries in `active` or `idle in transaction` state is high. `high` is subjective here and depends on the database size and type of workload. In my experience, number of `active` connections should be less than number of database's cpu cores and `max_running_time` should be less than 1 second.
 * If time for `idle in transaction` queries is high, then
    * either your application is taking time to commit transactions because its under heavy load or is doing some time consuming task before committing. Or application is not handling transactions properly.
    * some dev started a transaction and didn't commit it and left the connection open
 * If time for `active` queries is high, then
    * Queries are in waiting state. Queries can be in waiting state for multiple reasons. In [queries/active_running_queries.sql](queries/active_running_queries.sql) output, check `wait_event_type` and `wait_event` to figure out why the query is in waiting state. Reference: https://www.postgresql.org/docs/current/monitoring-stats.html#WAIT-EVENT-TABLE (Its better to check documentaton for postgres version you are workng with). Most of the time, its because:
      * two or more connections are working (lock) on the same row.
      * Someone executed some migrations and because of an `idle in transaction` or `active` query, this DDL query took a lock on that table preventing queries on table.
    * Query is expensive and is taking time. In this case `wait_event_type` and `wait_event` is null or its taking time to read data from disk (`wait_event_type` is `IO`). If the number of queries is also high, your database is probably under high CPU Utilisation. Fix for this is:
      * check if an index is missing. You can use `EXPLAIN` and `EXPLAIN ANALYZE` (NEVER USE `EXPLAIN ANALYZE` for a query which will modify data. This actually executes the query.)
      * providing more memory so that indexes can fit into memory or data can be cached into memory. For this, check disk reads. If its high, tune params (work_mem, shared_buffers, effective_cache_size) or increase memory for the instance.
      * increase CPU because the number of queries executed per second is high.

Having queries in `idle in transaction` state can cause a lot of issues in the long run. Because a query is in `idle in transaction` state and that connection holds a lock on a table, `VACUUM` won't run on that table because of which the size of that table might keep on increasing.

# Performance Tuning
* **Connection pooling** - every postgresql connection is a forked process on postgres. Lots of connections & disconnections can result in increased CPU utilization of your database. Setting up a connection pooler can create a lot of impact in performance. Most web frameworks provides connection pooling out of the box, but you can also setup external connection poolers like [pgbouncer](https://www.pgbouncer.org/) or [pgpool-II](https://www.pgpool.net).

* **Indexes** - one of most common problems which can result in low performance is missing indexes. Using pgbadger you can identify slow queries and identify tables which are missing indexes. Postgresql provides a variety of indexes (btree, brin, gin, etc.).

* **Parameter tuning** - I have seen people vertically scale postgres without attempting to understand bottlenecks causing performance problems. It is really important to tune your parameters for your workloads to gain desired performance. You can generate a default configuration using [PGTune](https://pgtune.leopard.in.ua/). But don't forget to understand more about your workloads and tune accordingly.

* **Partitioning** - Partitioning can help you achieve easier archiving and better performance of large tables. You can partition tables either using declarative partitioning or inheritance based partitioning. Simple log or event tables are generally good candidates for partitioning. For more details, check [Postgresql documentation](https://www.postgresql.org/docs/current/ddl-partitioning.html)

# Common questions while chosing data type
Postgres offers a lot of data types. While designing schema for a table, its quite useful to know about them and where to use them. These are some of the questions I come across:

## int vs bigint (serial vs bigserial)
Its better to use int when you know that won't exceed the limit of int. Changing a column from int to bigint can result in a massive downtime because postgres will need to rewrite the entire column.

## json vs jsonb
json is just like a text column with a json validation whereas in case of jsonb column, data is stored in a binary format. Because of which insert and update operations are a little slower for jsonb as compared to json.
If data in the column is just going to be logs and are not going to be queried, its better to use a json column. For more details check [this article](https://www.compose.com/articles/faster-operations-with-the-jsonb-data-type-in-postgresql/).

## char vs varchar vs text
char(n) is fixed length with blanks padded whereas varchar(n) is a variable length string with a limit. Text on other hand has no limits. Most of the time, its better to use text data type. If a check on length is required, you can add a constraint for that on a text column. For more information check postgres documentation [here](https://www.postgresql.org/docs/9.1/datatype-character.html).

# Additional Tips
## Backups
Always keep backups enabled and test them regularly. Gitlab faced an issue with backups in the past which resulted in a data loss. You can check their postmortem [here](https://about.gitlab.com/blog/2017/02/10/postmortem-of-database-outage-of-january-31/).

## Upgrades
Minor version upgrades just require a restart where as a major version upgrade will need to update data on disk which can take quite some time. Its recommended to test the upgrade and the application with the newer version before actually doing it in production.
