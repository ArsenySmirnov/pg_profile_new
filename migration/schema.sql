/* Lock-tree history introduced in pg_profile 4.15. */
CREATE TABLE sample_lock_tree(
    server_id          integer,
    sample_id          integer,
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
    lock_info          text,

    CONSTRAINT pk_sample_lock_tree PRIMARY KEY (
      server_id, sample_id, subsample_ts, root_pid, path
    ),
    CONSTRAINT fk_sample_lock_tree_samples FOREIGN KEY (server_id, sample_id)
      REFERENCES samples (server_id, sample_id) ON DELETE CASCADE
      DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX ix_sample_lock_tree_interval ON
  sample_lock_tree(server_id, sample_id, subsample_ts);

CREATE TABLE last_lock_tree(
    server_id          integer,
    sample_id          integer,
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
)
PARTITION BY LIST (server_id);

DO $$
DECLARE
  srv record;
BEGIN
  FOR srv IN SELECT server_id FROM servers
  LOOP
    EXECUTE format(
      'CREATE TABLE last_lock_tree_srv%1$s PARTITION OF last_lock_tree '
      'FOR VALUES IN (%1$s)',
      srv.server_id
    );
    EXECUTE format(
      'ALTER TABLE last_lock_tree_srv%1$s '
      'ADD CONSTRAINT pk_last_lock_tree_srv%1$s '
        'PRIMARY KEY (server_id, sample_id, subsample_ts, root_pid, path), '
      'ADD CONSTRAINT fk_last_lock_tree_sample_srv%1$s '
        'FOREIGN KEY (server_id, sample_id) '
        'REFERENCES samples(server_id, sample_id) ON DELETE RESTRICT',
      srv.server_id
    );
  END LOOP;
END;
$$;

GRANT SELECT ON sample_lock_tree TO pg_read_all_stats;
GRANT SELECT ON last_lock_tree TO pg_read_all_stats;

CREATE TABLE dabox_import_log (
  cluster_id         text NOT NULL,
  sample_id          integer NOT NULL,
  previous_sample_id integer,
  event_id           text NOT NULL,
  sample_time        timestamp with time zone NOT NULL,
  received_at        timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  imported_rows      bigint NOT NULL,
  gap_accepted       boolean NOT NULL DEFAULT FALSE,
  CONSTRAINT pk_dabox_import_log PRIMARY KEY (cluster_id, sample_id),
  CONSTRAINT uk_dabox_import_log_event UNIQUE (event_id)
);
COMMENT ON TABLE dabox_import_log IS
  'Successfully imported DABOX snapshot envelopes used for deduplication and gap validation';
GRANT SELECT ON dabox_import_log TO pg_read_all_stats;
