CREATE FUNCTION query_pg_stat_archiver(IN server_properties jsonb, IN sserver_id integer, IN ssample_id integer
) RETURNS jsonb AS $$
declare
    server_query text;
    pg_version int := (get_sp_setting(server_properties, 'server_version_num')).reset_val::integer;
begin
    server_properties := log_sample_timings(server_properties, 'query pg_stat_archiver', 'start');
    -- pg_stat_archiver data
    CASE
      WHEN pg_version > 90500 THEN
        server_query := 'SELECT '
          'archived_count,'
          'last_archived_wal,'
          'last_archived_time,'
          'failed_count,'
          'last_failed_wal,'
          'last_failed_time,'
          'stats_reset '
          'FROM pg_catalog.pg_stat_archiver';
      ELSE
        server_query := NULL;
    END CASE;

    IF server_query IS NOT NULL THEN
      EXECUTE format($query$
          INSERT INTO last_stat_archiver (
            server_id,
            sample_id,
            archived_count,
            last_archived_wal,
            last_archived_time,
            failed_count,
            last_failed_wal,
            last_failed_time,
            stats_reset
          )
          SELECT $1, $2, archived_count, last_archived_wal,
            last_archived_time, failed_count, last_failed_wal,
            last_failed_time, stats_reset
          FROM (%s) AS rs
        $query$, server_query)
      USING sserver_id, ssample_id;
    END IF;
    server_properties := log_sample_timings(server_properties, 'query pg_stat_archiver', 'end');
    return server_properties;
end;
$$ LANGUAGE plpgsql;
