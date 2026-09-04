CREATE FUNCTION query_pg_stat_slru(IN server_properties jsonb, IN sserver_id integer, IN ssample_id integer
) RETURNS jsonb AS $$
declare
    server_query text;
    pg_version int := (get_sp_setting(server_properties, 'server_version_num')).reset_val::integer;
begin
    server_properties := log_sample_timings(server_properties, 'query pg_stat_slru', 'start');
    -- pg_stat_slru data
    CASE
      WHEN pg_version >= 130000 THEN
        server_query := 'SELECT '
          'name,'
          'blks_zeroed,'
          'blks_hit,'
          'blks_read,'
          'blks_written,'
          'blks_exists,'
          'flushes,'
          'truncates,'
          'stats_reset '
          'FROM pg_catalog.pg_stat_slru '
          'WHERE greatest('
              'blks_zeroed,'
              'blks_hit,'
              'blks_read,'
              'blks_written,'
              'blks_exists,'
              'flushes,'
              'truncates'
            ') > 0'
          ;
      ELSE
        server_query := NULL;
    END CASE;

    IF server_query IS NOT NULL THEN
      EXECUTE format($query$
          INSERT INTO last_stat_slru (
            server_id,
            sample_id,
            name,
            blks_zeroed,
            blks_hit,
            blks_read,
            blks_written,
            blks_exists,
            flushes,
            truncates,
            stats_reset
          )
          SELECT $1, $2, name, blks_zeroed, blks_hit, blks_read,
            blks_written, blks_exists, flushes, truncates, stats_reset
          FROM (%s) AS rs
        $query$, server_query)
      USING sserver_id, ssample_id;
    END IF;
    server_properties := log_sample_timings(server_properties, 'query pg_stat_slru', 'end');
    return server_properties;
end;
$$ LANGUAGE plpgsql;
