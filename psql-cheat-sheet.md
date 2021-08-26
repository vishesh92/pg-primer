# psql cheat sheet
psql can be a little bit intimidating in the begining, following this doc should help you get more familiar.

## Exit psql
```
\q
```

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

## Configure using `.psqlrc`
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
