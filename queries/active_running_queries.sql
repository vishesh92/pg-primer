SELECT CURRENT_TIMESTAMP - query_start AS running_time, *
FROM pg_stat_activity
WHERE state = 'active'
ORDER BY running_time DESC;
