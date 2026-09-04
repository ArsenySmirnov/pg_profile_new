/* === Data tables used in dump import process ==== */
CREATE TABLE import_queries_version_order (
  extension         text,
  version           text,
  parent_extension  text,
  parent_version    text,
  CONSTRAINT pk_import_queries_version_order PRIMARY KEY (extension, version),
  CONSTRAINT fk_import_queries_version_order FOREIGN KEY (parent_extension, parent_version)
    REFERENCES import_queries_version_order (extension,version)
);
COMMENT ON TABLE import_queries_version_order IS 'Version history used in import process';

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
