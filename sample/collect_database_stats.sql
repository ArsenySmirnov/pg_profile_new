CREATE FUNCTION collect_database_stats(IN server_properties jsonb, IN sserver_id integer, IN ssample_id integer
) RETURNS jsonb AS $$
declare
    server_query text;
    pg_version int := (get_sp_setting(server_properties, 'server_version_num')).reset_val::integer;
    qres record;
begin
    server_properties := log_sample_timings(server_properties, 'collect database stats', 'start');
    -- Construct pg_stat_database query
    CASE
      WHEN pg_version >= 180000 THEN
        server_query := 'SELECT '
            'dbs.datid, '
            'dbs.datname, '
            'dbs.xact_commit, '
            'dbs.xact_rollback, '
            'dbs.blks_read, '
            'dbs.blks_hit, '
            'dbs.tup_returned, '
            'dbs.tup_fetched, '
            'dbs.tup_inserted, '
            'dbs.tup_updated, '
            'dbs.tup_deleted, '
            'dbs.conflicts, '
            'dbs.temp_files, '
            'dbs.temp_bytes, '
            'dbs.deadlocks, '
            'dbs.checksum_failures, '
            'dbs.checksum_last_failure, '
            'dbs.blk_read_time, '
            'dbs.blk_write_time, '
            'dbs.session_time, '
            'dbs.active_time, '
            'dbs.idle_in_transaction_time, '
            'dbs.sessions, '
            'dbs.sessions_abandoned, '
            'dbs.sessions_fatal, '
            'dbs.sessions_killed, '
            'dbs.parallel_workers_to_launch, '
            'dbs.parallel_workers_launched, '
            'dbs.stats_reset, '
            'pg_database_size(dbs.datid) as datsize, '
            '0 as datsize_delta, '
            'db.datistemplate, '
            'db.dattablespace, '
            'db.datallowconn '
          'FROM pg_catalog.pg_stat_database dbs '
          'JOIN pg_catalog.pg_database db ON (dbs.datid = db.oid) '
          'WHERE dbs.datname IS NOT NULL';
      WHEN pg_version >= 140000 THEN
        server_query := 'SELECT '
            'dbs.datid, '
            'dbs.datname, '
            'dbs.xact_commit, '
            'dbs.xact_rollback, '
            'dbs.blks_read, '
            'dbs.blks_hit, '
            'dbs.tup_returned, '
            'dbs.tup_fetched, '
            'dbs.tup_inserted, '
            'dbs.tup_updated, '
            'dbs.tup_deleted, '
            'dbs.conflicts, '
            'dbs.temp_files, '
            'dbs.temp_bytes, '
            'dbs.deadlocks, '
            'dbs.checksum_failures, '
            'dbs.checksum_last_failure, '
            'dbs.blk_read_time, '
            'dbs.blk_write_time, '
            'dbs.session_time, '
            'dbs.active_time, '
            'dbs.idle_in_transaction_time, '
            'dbs.sessions, '
            'dbs.sessions_abandoned, '
            'dbs.sessions_fatal, '
            'dbs.sessions_killed, '
            'NULL as parallel_workers_to_launch, '
            'NULL as parallel_workers_launched, '
            'dbs.stats_reset, '
            'pg_database_size(dbs.datid) as datsize, '
            '0 as datsize_delta, '
            'db.datistemplate, '
            'db.dattablespace, '
            'db.datallowconn '
          'FROM pg_catalog.pg_stat_database dbs '
          'JOIN pg_catalog.pg_database db ON (dbs.datid = db.oid) '
          'WHERE dbs.datname IS NOT NULL';
      WHEN pg_version >= 120000 THEN
        server_query := 'SELECT '
            'dbs.datid, '
            'dbs.datname, '
            'dbs.xact_commit, '
            'dbs.xact_rollback, '
            'dbs.blks_read, '
            'dbs.blks_hit, '
            'dbs.tup_returned, '
            'dbs.tup_fetched, '
            'dbs.tup_inserted, '
            'dbs.tup_updated, '
            'dbs.tup_deleted, '
            'dbs.conflicts, '
            'dbs.temp_files, '
            'dbs.temp_bytes, '
            'dbs.deadlocks, '
            'dbs.checksum_failures, '
            'dbs.checksum_last_failure, '
            'dbs.blk_read_time, '
            'dbs.blk_write_time, '
            'NULL as session_time, '
            'NULL as active_time, '
            'NULL as idle_in_transaction_time, '
            'NULL as sessions, '
            'NULL as sessions_abandoned, '
            'NULL as sessions_fatal, '
            'NULL as sessions_killed, '
            'NULL as parallel_workers_to_launch, '
            'NULL as parallel_workers_launched, '
            'dbs.stats_reset, '
            'pg_database_size(dbs.datid) as datsize, '
            '0 as datsize_delta, '
            'db.datistemplate, '
            'db.dattablespace, '
            'db.datallowconn '
          'FROM pg_catalog.pg_stat_database dbs '
          'JOIN pg_catalog.pg_database db ON (dbs.datid = db.oid) '
          'WHERE dbs.datname IS NOT NULL';
      WHEN pg_version < 120000 THEN
        server_query := 'SELECT '
            'dbs.datid, '
            'dbs.datname, '
            'dbs.xact_commit, '
            'dbs.xact_rollback, '
            'dbs.blks_read, '
            'dbs.blks_hit, '
            'dbs.tup_returned, '
            'dbs.tup_fetched, '
            'dbs.tup_inserted, '
            'dbs.tup_updated, '
            'dbs.tup_deleted, '
            'dbs.conflicts, '
            'dbs.temp_files, '
            'dbs.temp_bytes, '
            'dbs.deadlocks, '
            'NULL as checksum_failures, '
            'NULL as checksum_last_failure, '
            'dbs.blk_read_time, '
            'dbs.blk_write_time, '
            'NULL as session_time, '
            'NULL as active_time, '
            'NULL as idle_in_transaction_time, '
            'NULL as sessions, '
            'NULL as sessions_abandoned, '
            'NULL as sessions_fatal, '
            'NULL as sessions_killed, '
            'NULL as parallel_workers_to_launch, '
            'NULL as parallel_workers_launched, '
            'dbs.stats_reset, '
            'pg_database_size(dbs.datid) as datsize, '
            '0 as datsize_delta, '
            'db.datistemplate, '
            'db.dattablespace, '
            'db.datallowconn '
          'FROM pg_catalog.pg_stat_database dbs '
          'JOIN pg_catalog.pg_database db ON (dbs.datid = db.oid) '
          'WHERE dbs.datname IS NOT NULL';
    END CASE;

    -- Execute the version-specific pg_stat_database query locally.
    FOR qres IN EXECUTE server_query
      LOOP
        INSERT INTO last_stat_database (
          server_id,
          sample_id,
          datid,
          datname,
          xact_commit,
          xact_rollback,
          blks_read,
          blks_hit,
          tup_returned,
          tup_fetched,
          tup_inserted,
          tup_updated,
          tup_deleted,
          conflicts,
          temp_files,
          temp_bytes,
          deadlocks,
          checksum_failures,
          checksum_last_failure,
          blk_read_time,
          blk_write_time,
          session_time,
          active_time,
          idle_in_transaction_time,
          sessions,
          sessions_abandoned,
          sessions_fatal,
          sessions_killed,
          parallel_workers_to_launch,
          parallel_workers_launched,
          stats_reset,
          datsize,
          datsize_delta,
          datistemplate,
          dattablespace,
          datallowconn
        ) VALUES (
          sserver_id,
          ssample_id,
          qres.datid::oid,
          qres.datname::name,
          qres.xact_commit::bigint,
          qres.xact_rollback::bigint,
          qres.blks_read::bigint,
          qres.blks_hit::bigint,
          qres.tup_returned::bigint,
          qres.tup_fetched::bigint,
          qres.tup_inserted::bigint,
          qres.tup_updated::bigint,
          qres.tup_deleted::bigint,
          qres.conflicts::bigint,
          qres.temp_files::bigint,
          qres.temp_bytes::bigint,
          qres.deadlocks::bigint,
          qres.checksum_failures::bigint,
          qres.checksum_last_failure::timestamp with time zone,
          qres.blk_read_time::double precision,
          qres.blk_write_time::double precision,
          qres.session_time::double precision,
          qres.active_time::double precision,
          qres.idle_in_transaction_time::double precision,
          qres.sessions::bigint,
          qres.sessions_abandoned::bigint,
          qres.sessions_fatal::bigint,
          qres.sessions_killed::bigint,
          qres.parallel_workers_to_launch::bigint,
          qres.parallel_workers_launched::bigint,
          qres.stats_reset::timestamp with time zone,
          qres.datsize::bigint,
          qres.datsize_delta::bigint,
          qres.datistemplate::boolean,
          qres.dattablespace::oid,
          qres.datallowconn::boolean
        );
    END LOOP;

    EXECUTE format('ANALYZE last_stat_database_srv%1$s',
      sserver_id);
    server_properties := log_sample_timings(server_properties, 'collect database stats', 'end');
    return server_properties;
end;
$$ LANGUAGE plpgsql;
