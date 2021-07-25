SELECT slot_name, database, active, pg_size_pretty(pg_xlog_location_diff(pg_current_xlog_insert_location(), restart_lsn)) AS retained_bytes
FROM pg_replication_slots
ORDER BY active;
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(),restart_lsn)) as replicationSlotLag, active
FROM pg_replication_slots
ORDER BY active;

