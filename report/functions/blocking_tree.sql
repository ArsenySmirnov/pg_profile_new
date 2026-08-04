/* Blocking tree reporting functions */
CREATE FUNCTION blocking_tree_format(IN sserver_id integer,
  IN start_id integer, IN end_id integer)
RETURNS TABLE(
  node_id          text,
  parent_node_id   text,
  depth            integer,
  has_children     boolean,
  node_label       text,
  role_label       text,
  blocks_pids      text,
  observed_at      text,
  dbname           name,
  pid              integer,
  blocked_by       integer,
  username         name,
  application_name text,
  client_addr      text,
  xact_age         text,
  session_state    text,
  wait_event       text,
  lock_info        text,
  query_text       text,
  klass            text,
  ord_tree         bigint
)
SET search_path=@extschema@ AS $$
  WITH source AS (
    SELECT
      tree.*,
      tree.sample_id::text || ':' ||
        extract(epoch FROM tree.subsample_ts)::numeric::text || ':' ||
        tree.root_pid::text || ':' || array_to_string(tree.path, '.') AS current_node_id,
      CASE
        WHEN tree.depth = 0 THEN NULL
        ELSE tree.sample_id::text || ':' ||
          extract(epoch FROM tree.subsample_ts)::numeric::text || ':' ||
          tree.root_pid::text || ':' ||
          array_to_string(tree.path[1:array_length(tree.path, 1) - 1], '.')
      END AS current_parent_node_id
    FROM sample_lock_tree tree
    WHERE tree.server_id = sserver_id
      AND tree.sample_id BETWEEN start_id + 1 AND end_id
  )
  SELECT
    tree.current_node_id,
    tree.current_parent_node_id,
    tree.depth,
    children.blocks_pids IS NOT NULL AS has_children,
    CASE
      WHEN tree.pid = 0 THEN 'Подготовленная транзакция'
      ELSE 'PID ' || tree.pid::text
    END AS node_label,
    CASE
      WHEN tree.depth = 0 THEN 'Блокирующий сеанс'
      WHEN children.blocks_pids IS NOT NULL THEN
        'Ожидает PID ' || tree.blocked_by::text ||
        '; блокирует PID ' || children.blocks_pids
      ELSE 'Ожидает PID ' || tree.blocked_by::text
    END AS role_label,
    children.blocks_pids,
    to_char(tree.subsample_ts, 'YYYY-MM-DD HH24:MI:SS.MS TZ') AS observed_at,
    tree.datname,
    tree.pid,
    tree.blocked_by,
    tree.usename,
    tree.application_name,
    tree.client_addr::text,
    CASE
      WHEN tree.xact_start IS NULL THEN NULL
      ELSE date_trunc('milliseconds', tree.subsample_ts - tree.xact_start)::text
    END AS xact_age,
    tree.state AS session_state,
    concat_ws(': ', tree.wait_event_type, tree.wait_event) AS wait_event,
    tree.lock_info,
    left(tree.query_text, 1000) AS query_text,
    CASE WHEN tree.depth = 0
      THEN 'lock-tree-blocker'
      ELSE 'lock-tree-waiter'
    END AS klass,
    row_number() OVER (
      ORDER BY tree.subsample_ts, tree.root_pid, tree.path
    ) AS ord_tree
  FROM source tree
  LEFT JOIN LATERAL (
    SELECT string_agg(child.pid::text, ', ' ORDER BY child.pid) AS blocks_pids
    FROM source child
    WHERE child.current_parent_node_id = tree.current_node_id
  ) children ON true
  ORDER BY tree.subsample_ts, tree.root_pid, tree.path;
$$ LANGUAGE sql;

CREATE FUNCTION blocking_tree_format_diff(IN sserver_id integer,
  IN start1_id integer, IN end1_id integer,
  IN start2_id integer, IN end2_id integer)
RETURNS TABLE(
  node_id          text,
  parent_node_id   text,
  depth            integer,
  has_children     boolean,
  node_label       text,
  interval_num     integer,
  role_label       text,
  blocks_pids      text,
  observed_at      text,
  dbname           name,
  pid              integer,
  blocked_by       integer,
  username         name,
  application_name text,
  client_addr      text,
  xact_age         text,
  session_state    text,
  wait_event       text,
  lock_info        text,
  query_text       text,
  klass            text,
  ord_tree         bigint
)
SET search_path=@extschema@ AS $$
  SELECT
    interval_num::text || ':' || src.node_id,
    CASE WHEN src.parent_node_id IS NULL THEN NULL
      ELSE interval_num::text || ':' || src.parent_node_id END,
    src.depth,
    src.has_children,
    src.node_label,
    interval_num,
    src.role_label,
    src.blocks_pids,
    src.observed_at,
    src.dbname,
    src.pid,
    src.blocked_by,
    src.username,
    src.application_name,
    src.client_addr,
    src.xact_age,
    src.session_state,
    src.wait_event,
    src.lock_info,
    src.query_text,
    src.klass,
    row_number() OVER (ORDER BY interval_num, src.ord_tree) AS ord_tree
  FROM (
    SELECT 1 AS interval_num, tree.*
    FROM blocking_tree_format(sserver_id, start1_id, end1_id) tree
    UNION ALL
    SELECT 2 AS interval_num, tree.*
    FROM blocking_tree_format(sserver_id, start2_id, end2_id) tree
  ) src
  ORDER BY interval_num, src.ord_tree;
$$ LANGUAGE sql;
