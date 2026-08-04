CREATE FUNCTION collect_lock_tree(IN properties jsonb, IN sserver_id integer, IN s_id integer)
RETURNS void AS $$
DECLARE
  server_query  text;
  srv_version   integer;
  query_id_expr text;
BEGIN
  srv_version := (get_sp_setting(properties, 'server_version_num')).reset_val::integer;
  query_id_expr := CASE WHEN srv_version >= 140000 THEN 'query_id' ELSE 'NULL::bigint' END;

  /*
   * pg_blocking_pids() provides correct hard and soft blocking edges.  pg_locks
   * is used only to describe the waiting lock; it is deliberately not used to
   * infer blocker relationships.
   */
  server_query := format($sql$
    WITH RECURSIVE
    observed AS (
      SELECT clock_timestamp() AS subsample_ts
    ),
    activity AS (
      SELECT
        pid,
        datid,
        datname,
        usename,
        application_name,
        client_addr,
        backend_start,
        xact_start,
        query_start,
        state,
        wait_event_type,
        wait_event,
        %1$s AS query_id,
        query
      FROM pg_catalog.pg_stat_activity
    ),
    edges AS (
      SELECT DISTINCT
        blocked.pid AS blocked_pid,
        blocker.blocker_pid
      FROM activity blocked
      CROSS JOIN LATERAL
        unnest(pg_catalog.pg_blocking_pids(blocked.pid)) AS blocker(blocker_pid)
      WHERE blocked.wait_event_type = 'Lock'
    ),
    roots AS (
      SELECT DISTINCT edge.blocker_pid AS root_pid
      FROM edges edge
      WHERE NOT EXISTS (
        SELECT 1
        FROM edges parent_edge
        WHERE parent_edge.blocked_pid = edge.blocker_pid
      )
    ),
    lock_tree(root_pid, pid, blocked_by, depth, path) AS (
      SELECT
        root_pid,
        root_pid,
        NULL::integer,
        0,
        ARRAY[root_pid]
      FROM roots
      UNION ALL
      SELECT
        tree.root_pid,
        edge.blocked_pid,
        tree.pid,
        tree.depth + 1,
        tree.path || edge.blocked_pid
      FROM lock_tree tree
      JOIN edges edge ON edge.blocker_pid = tree.pid
      WHERE tree.depth < 32
        AND NOT edge.blocked_pid = ANY(tree.path)
    )
    SELECT
      observed.subsample_ts,
      tree.root_pid,
      tree.pid,
      tree.blocked_by,
      tree.depth,
      tree.path,
      activity.datid,
      activity.datname,
      activity.usename,
      activity.application_name,
      activity.client_addr,
      activity.backend_start,
      activity.xact_start,
      activity.query_start,
      activity.state,
      activity.wait_event_type,
      activity.wait_event,
      activity.query_id,
      activity.query,
      waiting_lock.lock_info
    FROM lock_tree tree
    CROSS JOIN observed
    LEFT JOIN activity ON activity.pid = tree.pid
    LEFT JOIN LATERAL (
      SELECT string_agg(
        concat_ws(' ',
          lock_row.locktype,
          lock_row.mode,
          CASE WHEN lock_row.database IS NOT NULL
            THEN 'db=' || lock_row.database::text END,
          CASE WHEN lock_row.relation IS NOT NULL
            THEN 'rel=' || lock_row.relation::text END,
          CASE WHEN lock_row.page IS NOT NULL
            THEN 'page=' || lock_row.page::text END,
          CASE WHEN lock_row.tuple IS NOT NULL
            THEN 'tuple=' || lock_row.tuple::text END,
          CASE WHEN lock_row.virtualxid IS NOT NULL
            THEN 'vxid=' || lock_row.virtualxid::text END,
          CASE WHEN lock_row.transactionid IS NOT NULL
            THEN 'xid=' || lock_row.transactionid::text END,
          CASE WHEN lock_row.classid IS NOT NULL
            THEN 'class=' || lock_row.classid::text END,
          CASE WHEN lock_row.objid IS NOT NULL
            THEN 'obj=' || lock_row.objid::text END,
          CASE WHEN lock_row.objsubid IS NOT NULL
            THEN 'subobj=' || lock_row.objsubid::text END
        ),
        '; ' ORDER BY lock_row.locktype, lock_row.mode
      ) AS lock_info
      FROM pg_catalog.pg_locks lock_row
      WHERE lock_row.pid = tree.pid
        AND NOT lock_row.granted
    ) waiting_lock ON true
    ORDER BY observed.subsample_ts, tree.root_pid, tree.path
  $sql$, query_id_expr);

  INSERT INTO last_lock_tree (
    server_id,
    sample_id,
    subsample_ts,
    root_pid,
    pid,
    blocked_by,
    depth,
    path,
    datid,
    datname,
    usename,
    application_name,
    client_addr,
    backend_start,
    xact_start,
    query_start,
    state,
    wait_event_type,
    wait_event,
    query_id,
    query_text,
    lock_info
  )
  SELECT
    sserver_id,
    s_id,
    remote_tree.subsample_ts,
    remote_tree.root_pid,
    remote_tree.pid,
    remote_tree.blocked_by,
    remote_tree.depth,
    remote_tree.path,
    remote_tree.datid,
    remote_tree.datname,
    remote_tree.usename,
    remote_tree.application_name,
    remote_tree.client_addr,
    remote_tree.backend_start,
    remote_tree.xact_start,
    remote_tree.query_start,
    remote_tree.state,
    remote_tree.wait_event_type,
    remote_tree.wait_event,
    remote_tree.query_id,
    remote_tree.query_text,
    remote_tree.lock_info
  FROM dblink('server_connection', server_query) AS remote_tree (
    subsample_ts       timestamp with time zone,
    root_pid           integer,
    pid                integer,
    blocked_by         integer,
    depth              integer,
    path               integer[],
    datid              oid,
    datname            name,
    usename            name,
    application_name   text,
    client_addr        inet,
    backend_start      timestamp with time zone,
    xact_start         timestamp with time zone,
    query_start        timestamp with time zone,
    state              text,
    wait_event_type    text,
    wait_event         text,
    query_id           bigint,
    query_text         text,
    lock_info          text
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION collect_lock_tree(IN jsonb, IN integer, IN integer) IS
  'Capture current blocking trees using pg_blocking_pids() and pg_locks';
