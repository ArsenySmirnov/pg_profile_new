/* ==== DABOX snapshot transport ==== */

CREATE FUNCTION export_sample_dabox(
  IN server_name name = 'local',
  IN sample_id integer = NULL,
  IN obfuscate_queries boolean = FALSE
) RETURNS jsonb
SET search_path=@extschema@ AS $$
DECLARE
  sserver_id          integer;
  ssample_id          integer;
  ssample_time        timestamp with time zone;
  sserver_created     timestamp with time zone;
  cluster_id          text;
  table_list          jsonb;
  filtered_table_list jsonb;
  server_section_id   bigint;
  payload_rows        jsonb;
  payload_row_count   bigint;
  payload_table_count integer;
  extension_version   text;
BEGIN
  SELECT s.server_id, s.server_created
    INTO sserver_id, sserver_created
  FROM servers s
  WHERE s.server_name = export_sample_dabox.server_name;

  IF sserver_id IS NULL THEN
    RAISE 'Server "%" is not found', export_sample_dabox.server_name;
  END IF;

  IF export_sample_dabox.sample_id IS NULL THEN
    SELECT max(s.sample_id)
      INTO ssample_id
    FROM samples s
    WHERE s.server_id = sserver_id;
  ELSE
    ssample_id := export_sample_dabox.sample_id;
  END IF;

  SELECT s.sample_time
    INTO ssample_time
  FROM samples s
  WHERE (s.server_id, s.sample_id) = (sserver_id, ssample_id);

  IF ssample_time IS NULL THEN
    RAISE 'Sample % for server "%" is not found',
      ssample_id, export_sample_dabox.server_name;
  END IF;

  SELECT ss.reset_val
    INTO cluster_id
  FROM sample_settings ss
  WHERE ss.server_id = sserver_id
    AND ss.name = 'system_identifier'
  LIMIT 1;

  IF cluster_id IS NULL THEN
    RAISE 'System identifier for server "%" is not found',
      export_sample_dabox.server_name;
  END IF;

  SELECT e.extversion
    INTO extension_version
  FROM pg_catalog.pg_extension e
  WHERE e.extname = '{pg_profile}';

  SELECT e.row_data::jsonb
    INTO table_list
  FROM export_data(
    export_sample_dabox.server_name,
    ssample_id,
    ssample_id,
    export_sample_dabox.obfuscate_queries,
    TRUE
  ) e
  WHERE e.section_id = 1;

  SELECT
    COALESCE(jsonb_agg(t.item ORDER BY (t.item ->> 'section_id')::bigint), '[]'::jsonb),
    count(*)::integer,
    max((t.item ->> 'section_id')::bigint)
      FILTER (WHERE t.item ->> 'relname' = 'servers')
    INTO filtered_table_list, payload_table_count, server_section_id
  FROM jsonb_array_elements(table_list) AS t(item)
  WHERE t.item ->> 'relname' NOT LIKE 'last\_%' ESCAPE '\';

  WITH exported AS MATERIALIZED (
    SELECT e.section_id, e.row_data::jsonb AS row_data
    FROM export_data(
      export_sample_dabox.server_name,
      ssample_id,
      ssample_id,
      export_sample_dabox.obfuscate_queries,
      TRUE
    ) e
  ),
  allowed_sections AS (
    SELECT (t.item ->> 'section_id')::bigint AS section_id
    FROM jsonb_array_elements(filtered_table_list) AS t(item)
  ),
  sanitized AS (
    SELECT
      e.section_id,
      CASE
        WHEN e.section_id = 1 THEN filtered_table_list
        WHEN e.section_id = server_section_id THEN e.row_data - 'connstr'
        ELSE e.row_data
      END AS row_data
    FROM exported e
    WHERE e.section_id IN (0, 1)
       OR e.section_id IN (SELECT a.section_id FROM allowed_sections a)
  )
  SELECT
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'section_id', s.section_id,
          'row_data', s.row_data
        )
        ORDER BY s.section_id, s.row_data::text
      ),
      '[]'::jsonb
    ),
    count(*)
    INTO payload_rows, payload_row_count
  FROM sanitized s;

  RETURN jsonb_build_object(
    'contract', 'pg_profile.dabox.snapshot',
    'contract_version', 1,
    'event_id', cluster_id || ':' || ssample_id::text,
    'created_at', clock_timestamp(),
    'source', jsonb_build_object(
      'cluster_id', cluster_id,
      'server_name', export_sample_dabox.server_name,
      'server_created', sserver_created,
      'pg_profile_version', extension_version
    ),
    'sequence', jsonb_build_object(
      'sample_id', ssample_id,
      'previous_sample_id', CASE WHEN ssample_id > 1 THEN ssample_id - 1 ELSE NULL END
    ),
    'sample', jsonb_build_object(
      'sample_time', ssample_time
    ),
    'content', jsonb_build_object(
      'encoding', 'pg_profile.export_data.rows',
      'table_count', payload_table_count,
      'row_count', payload_row_count,
      'rows', payload_rows
    )
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION export_sample_dabox(name, integer, boolean) IS
  'Export one completed sample as a DABOX JSON envelope without connection strings or last_* working data';

CREATE FUNCTION import_sample_dabox(
  IN payload jsonb,
  IN server_name_prefix text = NULL,
  IN allow_gap boolean = FALSE
) RETURNS bigint
SET search_path=@extschema@ AS $$
DECLARE
  v_cluster_id           text;
  v_sample_id            integer;
  v_previous_sample_id   integer;
  v_event_id             text;
  v_sample_time          timestamp with time zone;
  declared_row_count     bigint;
  actual_row_count       bigint;
  last_imported_sample   integer;
  imported_rows          bigint;
  effective_prefix       text;
  gap_detected           boolean = FALSE;
  existing_event_id      text;
  samples_section_id     bigint;
  settings_section_id    bigint;
  metadata_rows          bigint;
  table_catalog          jsonb;
BEGIN
  IF payload ->> 'contract' IS DISTINCT FROM 'pg_profile.dabox.snapshot' THEN
    RAISE 'Unsupported DABOX contract: %', payload ->> 'contract';
  END IF;

  IF payload ->> 'contract_version' IS DISTINCT FROM '1' THEN
    RAISE 'Unsupported DABOX contract version: %', payload ->> 'contract_version';
  END IF;

  IF jsonb_typeof(payload #> '{content,rows}') IS DISTINCT FROM 'array' THEN
    RAISE 'DABOX payload content.rows must be a JSON array';
  END IF;

  BEGIN
    v_cluster_id := payload #>> '{source,cluster_id}';
    v_sample_id := (payload #>> '{sequence,sample_id}')::integer;
    v_previous_sample_id := (payload #>> '{sequence,previous_sample_id}')::integer;
    v_event_id := payload ->> 'event_id';
    v_sample_time := (payload #>> '{sample,sample_time}')::timestamp with time zone;
    declared_row_count := (payload #>> '{content,row_count}')::bigint;
  EXCEPTION
    WHEN invalid_text_representation OR datetime_field_overflow OR numeric_value_out_of_range THEN
      RAISE 'Invalid typed value in DABOX payload metadata';
  END;

  IF v_cluster_id IS NULL OR v_cluster_id = '' OR v_sample_id IS NULL
    OR v_event_id IS NULL OR v_sample_time IS NULL OR declared_row_count IS NULL
  THEN
    RAISE 'Required DABOX payload metadata is missing';
  END IF;

  IF v_sample_id < 1
    OR (v_previous_sample_id IS NOT NULL AND v_previous_sample_id < 1)
  THEN
    RAISE 'DABOX sample identifiers must be positive';
  END IF;

  IF v_event_id IS DISTINCT FROM v_cluster_id || ':' || v_sample_id::text THEN
    RAISE 'DABOX event_id does not match cluster_id and sample_id';
  END IF;

  actual_row_count := jsonb_array_length(payload #> '{content,rows}');
  IF declared_row_count IS DISTINCT FROM actual_row_count THEN
    RAISE 'DABOX row count mismatch: declared %, actual %',
      declared_row_count, actual_row_count;
  END IF;

  SELECT r.item -> 'row_data'
    INTO table_catalog
  FROM jsonb_array_elements(payload #> '{content,rows}') AS r(item)
  WHERE (r.item ->> 'section_id')::bigint = 1
  LIMIT 1;

  IF jsonb_typeof(table_catalog) IS DISTINCT FROM 'array' THEN
    RAISE 'DABOX table catalog is missing or invalid';
  END IF;

  SELECT
    max((t.item ->> 'section_id')::bigint)
      FILTER (WHERE t.item ->> 'relname' = 'samples'),
    max((t.item ->> 'section_id')::bigint)
      FILTER (WHERE t.item ->> 'relname' = 'sample_settings')
    INTO samples_section_id, settings_section_id
  FROM jsonb_array_elements(table_catalog) AS t(item);

  IF samples_section_id IS NULL OR settings_section_id IS NULL THEN
    RAISE 'DABOX table catalog does not contain required metadata tables';
  END IF;

  SELECT count(*)
    INTO metadata_rows
  FROM jsonb_array_elements(payload #> '{content,rows}') AS r(item)
  WHERE (r.item ->> 'section_id')::bigint = samples_section_id
    AND (r.item #>> '{row_data,sample_id}')::integer = v_sample_id;

  IF metadata_rows <> 1 THEN
    RAISE 'DABOX payload must contain exactly one samples row for sample %',
      v_sample_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(payload #> '{content,rows}') AS r(item)
    WHERE (r.item -> 'row_data') ? 'sample_id'
      AND (r.item #>> '{row_data,sample_id}')::integer <> v_sample_id
  ) THEN
    RAISE 'DABOX payload contains rows for a different sample';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements(payload #> '{content,rows}') AS r(item)
    WHERE (r.item ->> 'section_id')::bigint = settings_section_id
      AND r.item #>> '{row_data,name}' = 'system_identifier'
      AND r.item #>> '{row_data,reset_val}' = v_cluster_id
  ) THEN
    RAISE 'DABOX cluster_id does not match the exported system identifier';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_cluster_id, 0)
  );

  SELECT l.event_id
    INTO existing_event_id
  FROM dabox_import_log l
  WHERE (l.cluster_id, l.sample_id) =
    (v_cluster_id, v_sample_id);

  IF existing_event_id IS NOT NULL THEN
    IF existing_event_id = v_event_id THEN
      RETURN 0; -- idempotent repeat delivery
    END IF;
    RAISE 'Conflicting DABOX event for cluster %, sample %',
      v_cluster_id, v_sample_id;
  END IF;

  SELECT max(l.sample_id)
    INTO last_imported_sample
  FROM dabox_import_log l
  WHERE l.cluster_id = v_cluster_id;

  IF last_imported_sample IS NOT NULL THEN
    gap_detected := v_sample_id <> last_imported_sample + 1
      OR v_previous_sample_id IS DISTINCT FROM last_imported_sample;

    IF v_sample_id <= last_imported_sample THEN
      RAISE 'Stale or out-of-order DABOX sample % for cluster %; latest imported sample is %',
        v_sample_id, v_cluster_id, last_imported_sample;
    END IF;

    IF gap_detected AND NOT allow_gap THEN
      RAISE 'DABOX sample gap for cluster %: latest imported %, incoming %, incoming previous %',
        v_cluster_id, last_imported_sample, v_sample_id, v_previous_sample_id;
    END IF;
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS pg_profile_dabox_stage (
    section_id bigint,
    row_data json
  ) ON COMMIT DROP;
  TRUNCATE pg_profile_dabox_stage;

  INSERT INTO pg_profile_dabox_stage(section_id, row_data)
  SELECT
    (r.item ->> 'section_id')::bigint,
    (r.item -> 'row_data')::json
  FROM jsonb_array_elements(payload #> '{content,rows}') AS r(item);

  effective_prefix := COALESCE(
    server_name_prefix,
    'dabox_' || right(v_cluster_id, 8) || '_'
  );

  imported_rows := import_data(
    'pg_temp.pg_profile_dabox_stage'::regclass,
    effective_prefix
  );

  INSERT INTO dabox_import_log(
    cluster_id, sample_id, previous_sample_id, event_id,
    sample_time, imported_rows, gap_accepted
  ) VALUES (
    v_cluster_id, v_sample_id, v_previous_sample_id, v_event_id,
    v_sample_time, imported_rows, gap_detected
  );

  RETURN imported_rows;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION import_sample_dabox(jsonb, text, boolean) IS
  'Validate and idempotently import one DABOX snapshot envelope; gaps are rejected by default';
