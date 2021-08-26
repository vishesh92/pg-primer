# SQL Query Analysis

Slow or poorly performing queries are one of the biggest reasons for outages or poor user experience. While building new features or optimizing existing ones for scale, it becomes imperitive that we optimize how our data is stored and queried. To optimize our usage of databases, we need to understand how databases work and tune our queries.

## How does postgres decide a query plan?
When you execute a query, postgres can fetch the results in different ways (sequential scan, index scan, etc.). Postgres generates multiple plans and if feasible, calculates cost for each plan based on postgres's [configuration parameters](https://www.postgresql.org/docs/current/runtime-config-query.html) and table's statistics which are gathered using ANALYZE. The plan which is expected to run the fastest is selected. Selected plan might not actually be the fastest plan in some cases. That is where you might want to tune configuraion parameters and make sure that your tables are getting analyzed frequently by autovacuum.

### Additional Resources
* [An Overview of the Various Scan Methods in PostgreSQL](https://severalnines.com/database-blog/overview-various-scan-methods-postgresql)
* [Planner Optimizer](https://www.postgresql.org/docs/devel/planner-optimizer.html)
* Explaining the Postgres Query Optimizer - Bruce Momjian: [Talk](https://www.youtube.com/watch?v=svqQzYFBPIo) | [Slides](https://momjian.us/main/writings/pgsql/optimizer.pdf)

## `EXPLAIN` vs `EXPLAIN ANALYZE`
`EXPLAIN` command can be used to see which plan has been decided by postgres to execute query. `EXPLAIN` just shows the plan but doesn't show how much time it actually takes. To know the time taken at each step of the plan, you can use `EXPLAIN ANALYZE`. `EXPLAIN ANALYZE` actually executes the query, so it should be used carefully.

> ⚠️ Using `EXPLAIN ANALYZE` with `INSERT`, `UPDATE` or `DELETE` will update your data. To safely try `EXPLAIN ANALYZE` with such queries, you can start a transaction (using `BEGIN`), use `EXPLAIN ANALYZE` and then `ROLLBACK` that transaction.

## Structure of a query plan
Running `EXPLAIN` on a query generates a query plan which is a tree of plan nodes(basically a step in the process of executing the query). This is the query plan for a `SELECT` command on a table:

```sql
EXPLAIN SELECT * FROM tenk1;

                         QUERY PLAN
------------------------------------------------------------
 Seq Scan on tenk1  (cost=0.00..483.00 rows=7001 width=244)
```

In this output,
 * *cost*
   * *estimated startup cost* (0.00) - the time before that node of the plan can begin
   * *estimated total cost* (483.00) - total time taken assuming that plan node will be run to completion (actual cost might be low in case of `LIMIT`).
 * *rows* (7001) - estimated number of rows that will be returned by this plan node assuming that node will be run to completion (actual cost might be low in case of `LIMIT`).
 * *width* (244) - estimated average width of rows in bytes for this plan node

Cost and rows above are calculated based on postgres's [configuration parameters](https://www.postgresql.org/docs/current/runtime-config-query.html). You can tune these params (cpu_tuple_cost, random_page_cost, etc.) at runtime to test out changes before deploying them.

Since the generated plan is based on relatives costs so actual time taken might be quite different. You can run `ANALYZE` on a table to update postgresql's statistics for that table so that plans have better estimates.

Since the costs are relative, you can compare costs between different nodes to identify the areas for optimization.

I generally try to follow these rules to speed up queries:
 * No plan node is doing a Seq Scan. And in case its happening, you can create an index to speed that up. Sometimes if the table is small, postgres would do a sequential scan even if an index is present.
 * If your queries have multiple conditions, you might see bitmap scans or an index scan with a filter. In cases like these, it might be useful to have a multi-column index or a partial index.

 ```sql
 EXPLAIN SELECT * FROM tenk1 WHERE unique1 < 100 AND unique2 > 9000 LIMIT 2;

                                     QUERY PLAN
-------------------------------------------------------------------​------------------
 Limit  (cost=0.29..14.48 rows=2 width=244)
   ->  Index Scan using tenk1_unique2 on tenk1  (cost=0.29..71.27 rows=10 width=244)
         Index Cond: (unique2 > 9000)
         Filter: (unique1 < 100)
```

Sometimes, the query plan can get really complicated to understand. In cases like this, you can use [pev2](https://explain.dalibo.com/).

### Additional Resources
* [Using Explain](https://www.postgresql.org/docs/current/using-explain.html)
* PostgresOpen 2019 Explain Plans And You: [Talk](https://www.youtube.com/watch?v=OO-CHEXAX4o) | [Slides](https://postgresql.us/events/pgopen2019/sessions/session/695/slides/31/ExplainPlansAndYouPostgresOpen2019.pdf)
* https://public.dalibo.com/exports/conferences/_archives/_2012/201211_explain/understanding_explain.pdf

# Excercises
## Setup
```bash
docker run --name explain-exercise-postgres -d postgres:13.3-alpine3.14
cat sql/explain-exercise.sql | docker exec -it explain-exercise-postgres psql -U postgres postgres
```

## Exercise
`tbl1` is a table with 10000 rows having `id` as a primary key and `col1` as `bigint` type column containing randomly generated numbers from 0 to 1000000.
```sql
test=# \d tbl1
                            Table "public.tbl1"
 Column |  Type  | Collation | Nullable |             Default              
--------+--------+-----------+----------+----------------------------------
 id     | bigint |           | not null | nextval('tbl1_id_seq'::regclass)
 col1   | bigint |           |          | 
Indexes:
    "tbl1_pkey" PRIMARY KEY, btree (id)
```

`SELECT` query with a filter on col1 will result in a sequential scan.
```sql
test=# EXPLAIN ANALYZE SELECT * FROM tbl1 WHERE col1 < 100;
                                           QUERY PLAN                                            
-------------------------------------------------------------------------------------------------
 Seq Scan on tbl1  (cost=0.00..180.00 rows=1 width=16) (actual time=2.019..2.986 rows=2 loops=1)
   Filter: (col1 < 100)
   Rows Removed by Filter: 9998
 Planning Time: 0.871 ms
 Execution Time: 3.018 ms
(5 rows)
```

Table `tbl2` is a copy of `tbl1` but with an index on col1.
```sql
test=# \d tbl2
                            Table "public.tbl2"
 Column |  Type  | Collation | Nullable |             Default              
--------+--------+-----------+----------+----------------------------------
 id     | bigint |           | not null | nextval('tbl1_id_seq'::regclass)
 col1   | bigint |           |          | 
Indexes:
    "tbl2_pkey" PRIMARY KEY, btree (id)
    "tbl2_col1_idx" btree (col1)
```

Executing the same query now uses an index scan instead of a sequential scan and the cost has also decreased for the plan now.
```sql
test=# EXPLAIN ANALYZE SELECT * FROM tbl2 WHERE col1 < 100;
                                                     QUERY PLAN                                                      
---------------------------------------------------------------------------------------------------------------------
 Index Scan using tbl2_col1_idx on tbl2  (cost=0.29..8.30 rows=1 width=16) (actual time=0.051..0.061 rows=2 loops=1)
   Index Cond: (col1 < 100)
 Planning Time: 1.027 ms
 Execution Time: 0.127 ms
(4 rows)
```

If we switch the condition, it will go back to a sequential scan since it will have to go through most of the rows and index scan might be slower.
```sql
test=# EXPLAIN ANALYZE SELECT * FROM tbl2 WHERE col1 > 100;
                                              QUERY PLAN
-------------------------------------------------------------------------------------------------------
 Seq Scan on tbl2  (cost=0.00..180.00 rows=9998 width=16) (actual time=0.023..4.361 rows=9998 loops=1)
   Filter: (col1 > 100)
   Rows Removed by Filter: 2
 Planning Time: 0.337 ms
 Execution Time: 6.178 ms
(5 rows)
```

`small_tbl2` has the schema as `tbl2` but with only 10 rows. Since the data is small, it will do a sequential scan only.
```sql

test=# \d small_tbl2
                         Table "public.small_tbl2"
 Column |  Type  | Collation | Nullable |             Default
--------+--------+-----------+----------+----------------------------------
 id     | bigint |           | not null | nextval('tbl1_id_seq'::regclass)
 col1   | bigint |           |          |
Indexes:
    "small_tbl2_pkey" PRIMARY KEY, btree (id)
    "small_tbl2_col1_idx" btree (col1)

test=# EXPLAIN ANALYZE SELECT * FROM small_tbl2 WHERE col1 < 100;
                                             QUERY PLAN
-----------------------------------------------------------------------------------------------------
 Seq Scan on small_tbl2  (cost=0.00..1.12 rows=1 width=16) (actual time=0.014..0.015 rows=0 loops=1)
   Filter: (col1 < 100)
   Rows Removed by Filter: 10
 Planning Time: 0.205 ms
 Execution Time: 0.032 ms
(5 rows)

test=# EXPLAIN ANALYZE SELECT * FROM small_tbl2 WHERE col1 > 100;
                                              QUERY PLAN
-------------------------------------------------------------------------------------------------------
 Seq Scan on small_tbl2  (cost=0.00..1.12 rows=10 width=16) (actual time=0.021..0.027 rows=10 loops=1)
   Filter: (col1 > 100)
 Planning Time: 0.309 ms
 Execution Time: 0.057 ms
(4 rows)
```