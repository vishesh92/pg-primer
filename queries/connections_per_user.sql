SELECT usename, state, COUNT(*) AS number_of_connections, MAX(CURRENT_TIMESTAMP-query_start) AS max_running_time
FROM pg_stat_activity
GROUP BY usename, state
ORDER BY state, max_running_time, number_of_connections DESC;
