CREATE FUNCTION collect_tablespace_stats(IN sserver_id integer, IN ssample_id integer
) RETURNS void AS $collect_tablespace_stats$
begin
    -- Get tablespace stats
    /*
    * pg_tablespace_size can return NULL for unused tablespaces so we need to
    * ignore them
    */
    INSERT INTO last_stat_tablespaces(
      server_id,
      sample_id,
      tablespaceid,
      tablespacename,
      tablespacepath,
      size,
      size_delta
    )
    SELECT
      sserver_id,
      ssample_id,
      ts.oid,
      ts.spcname,
      pg_catalog.pg_tablespace_location(ts.oid),
      pg_catalog.pg_tablespace_size(ts.oid),
      0
    FROM pg_catalog.pg_tablespace ts
    WHERE pg_catalog.pg_tablespace_size(ts.oid) IS NOT NULL;
    EXECUTE format('ANALYZE last_stat_tablespaces_srv%1$s',
      sserver_id);
end;
$collect_tablespace_stats$ LANGUAGE plpgsql;
