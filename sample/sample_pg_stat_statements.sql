CREATE FUNCTION collect_pg_stat_statements_stats(IN properties jsonb, IN sserver_id integer, IN s_id integer, IN topn integer) RETURNS void SET search_path=@extschema@ AS $$
DECLARE
  qres              record;
  st_query          text;
  is_local          boolean;
  statements_rows   bigint;
  statement_texts   jsonb;
BEGIN
    SELECT server_name = 'local'
      INTO STRICT is_local
    FROM servers
    WHERE server_id = sserver_id;

    IF NOT is_local THEN
      RAISE 'Remote statement collection is disabled. Only the local server is supported';
    END IF;

    -- Check if mandatory extensions exists
    IF NOT
      (
        SELECT count(*) = 1
        FROM jsonb_to_recordset(properties #> '{extensions}') AS ext(extname text)
        WHERE extname = 'pg_stat_statements'
      )
    THEN
      RETURN;
    END IF;

    -- Save used statements extension in sample_settings
    INSERT INTO sample_settings(
      server_id,
      first_seen,
      setting_scope,
      name,
      setting,
      reset_val,
      boot_val,
      unit,
      sourcefile,
      sourceline,
      pending_restart
    )
    SELECT
      s.server_id,
      s.sample_time,
      2 as setting_scope,
      'statements_extension',
      'pg_stat_statements',
      'pg_stat_statements',
      'pg_stat_statements',
      null,
      null,
      null,
      false
    FROM samples s LEFT OUTER JOIN  v_sample_settings prm ON
      (s.server_id, s.sample_id, prm.name, prm.setting_scope) =
      (prm.server_id, prm.sample_id, 'statements_extension', 2)
    WHERE s.server_id = sserver_id AND s.sample_id = s_id AND (prm.setting IS NULL OR prm.setting != 'pg_stat_statements');

    -- Dynamic statements query
    st_query := format(
      'SELECT '
        'st.userid,'
        'st.userid::regrole AS username,'
        'st.dbid AS datid,'
        'st.queryid,'
        '{statements_fields} '
      'FROM '
        '{statements_view} st '
    );

    st_query := replace(st_query, '{statements_view}',
      format('%1$I.pg_stat_statements(false)',
        (
          SELECT extnamespace FROM jsonb_to_recordset(properties #> '{extensions}')
            AS x(extname text, extnamespace text)
          WHERE extname = 'pg_stat_statements'
        )
      )
    );

    -- pg_stat_statements versions
    CASE (
        SELECT extversion
        FROM jsonb_to_recordset(properties #> '{extensions}')
          AS ext(extname text, extversion text)
        WHERE extname = 'pg_stat_statements'
      )
      WHEN '1.3','1.4','1.5','1.6','1.7'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'true as toplevel,'
          'NULL as plans,'
          'NULL as total_plan_time,'
          'NULL as min_plan_time,'
          'NULL as max_plan_time,'
          'NULL as mean_plan_time,'
          'NULL as stddev_plan_time,'
          'st.calls,'
          'st.total_time as total_exec_time,'
          'st.min_time as min_exec_time,'
          'st.max_time as max_exec_time,'
          'st.mean_time as mean_exec_time,'
          'st.stddev_time as stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.blk_read_time as shared_blk_read_time,'
          'st.blk_write_time as shared_blk_write_time,'
          'NULL as wal_records,'
          'NULL as wal_fpi,'
          'NULL as wal_bytes, '
          'NULL as wal_buffers_full, '
          'NULL as jit_functions, '
          'NULL as jit_generation_time, '
          'NULL as jit_inlining_count, '
          'NULL as jit_inlining_time, '
          'NULL as jit_optimization_count, '
          'NULL as jit_optimization_time, '
          'NULL as jit_emission_count, '
          'NULL as jit_emission_time, '
          'NULL as temp_blk_read_time, '
          'NULL as temp_blk_write_time, '
          'NULL as local_blk_read_time, '
          'NULL as local_blk_write_time, '
          'NULL as jit_deform_count, '
          'NULL as jit_deform_time, '
          'NULL as parallel_workers_to_launch, '
          'NULL as parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'NULL as stats_since, '
          'NULL as minmax_stats_since '
        );
      WHEN '1.8'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'true as toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.blk_read_time as shared_blk_read_time,'
          'st.blk_write_time as shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'NULL as wal_buffers_full, '
          'NULL as jit_functions, '
          'NULL as jit_generation_time, '
          'NULL as jit_inlining_count, '
          'NULL as jit_inlining_time, '
          'NULL as jit_optimization_count, '
          'NULL as jit_optimization_time, '
          'NULL as jit_emission_count, '
          'NULL as jit_emission_time, '
          'NULL as temp_blk_read_time, '
          'NULL as temp_blk_write_time, '
          'NULL as local_blk_read_time, '
          'NULL as local_blk_write_time, '
          'NULL as jit_deform_count, '
          'NULL as jit_deform_time, '
          'NULL as parallel_workers_to_launch, '
          'NULL as parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'NULL as stats_since, '
          'NULL as minmax_stats_since '
        );
      WHEN '1.9'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'st.toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.blk_read_time as shared_blk_read_time,'
          'st.blk_write_time as shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'NULL as wal_buffers_full, '
          'NULL as jit_functions, '
          'NULL as jit_generation_time, '
          'NULL as jit_inlining_count, '
          'NULL as jit_inlining_time, '
          'NULL as jit_optimization_count, '
          'NULL as jit_optimization_time, '
          'NULL as jit_emission_count, '
          'NULL as jit_emission_time, '
          'NULL as temp_blk_read_time, '
          'NULL as temp_blk_write_time, '
          'NULL as local_blk_read_time, '
          'NULL as local_blk_write_time, '
          'NULL as jit_deform_count, '
          'NULL as jit_deform_time, '
          'NULL as parallel_workers_to_launch, '
          'NULL as parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'NULL as stats_since, '
          'NULL as minmax_stats_since '
        );
      WHEN '1.10'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'st.toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.blk_read_time as shared_blk_read_time,'
          'st.blk_write_time as shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'NULL as wal_buffers_full, '
          'st.jit_functions, '
          'st.jit_generation_time, '
          'st.jit_inlining_count, '
          'st.jit_inlining_time, '
          'st.jit_optimization_count, '
          'st.jit_optimization_time, '
          'st.jit_emission_count, '
          'st.jit_emission_time, '
          'st.temp_blk_read_time, '
          'st.temp_blk_write_time, '
          'NULL as local_blk_read_time, '
          'NULL as local_blk_write_time, '
          'NULL as jit_deform_count, '
          'NULL as jit_deform_time, '
          'NULL as parallel_workers_to_launch, '
          'NULL as parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'NULL as stats_since, '
          'NULL as minmax_stats_since '
        );
      WHEN '1.11'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'st.toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.shared_blk_read_time,'
          'st.shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'NULL as wal_buffers_full, '
          'st.jit_functions, '
          'st.jit_generation_time, '
          'st.jit_inlining_count, '
          'st.jit_inlining_time, '
          'st.jit_optimization_count, '
          'st.jit_optimization_time, '
          'st.jit_emission_count, '
          'st.jit_emission_time, '
          'st.temp_blk_read_time, '
          'st.temp_blk_write_time, '
          'st.local_blk_read_time, '
          'st.local_blk_write_time, '
          'st.jit_deform_count, '
          'st.jit_deform_time, '
          'NULL as parallel_workers_to_launch, '
          'NULL as parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'st.stats_since, '
          'st.minmax_stats_since '
        );
      WHEN '1.12'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'st.toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.shared_blk_read_time,'
          'st.shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'st.wal_buffers_full, '
          'st.jit_functions, '
          'st.jit_generation_time, '
          'st.jit_inlining_count, '
          'st.jit_inlining_time, '
          'st.jit_optimization_count, '
          'st.jit_optimization_time, '
          'st.jit_emission_count, '
          'st.jit_emission_time, '
          'st.temp_blk_read_time, '
          'st.temp_blk_write_time, '
          'st.local_blk_read_time, '
          'st.local_blk_write_time, '
          'st.jit_deform_count, '
          'st.jit_deform_time, '
          'st.parallel_workers_to_launch, '
          'st.parallel_workers_launched, '
          'NULL as generic_plan_calls, '
          'NULL as custom_plan_calls, '
          'st.stats_since, '
          'st.minmax_stats_since '
        );
      WHEN '1.13'
      THEN
        st_query := replace(st_query, '{statements_fields}',
          'st.toplevel,'
          'st.plans,'
          'st.total_plan_time,'
          'st.min_plan_time,'
          'st.max_plan_time,'
          'st.mean_plan_time,'
          'st.stddev_plan_time,'
          'st.calls,'
          'st.total_exec_time,'
          'st.min_exec_time,'
          'st.max_exec_time,'
          'st.mean_exec_time,'
          'st.stddev_exec_time,'
          'st.rows,'
          'st.shared_blks_hit,'
          'st.shared_blks_read,'
          'st.shared_blks_dirtied,'
          'st.shared_blks_written,'
          'st.local_blks_hit,'
          'st.local_blks_read,'
          'st.local_blks_dirtied,'
          'st.local_blks_written,'
          'st.temp_blks_read,'
          'st.temp_blks_written,'
          'st.shared_blk_read_time,'
          'st.shared_blk_write_time,'
          'st.wal_records,'
          'st.wal_fpi,'
          'st.wal_bytes, '
          'st.wal_buffers_full, '
          'st.jit_functions, '
          'st.jit_generation_time, '
          'st.jit_inlining_count, '
          'st.jit_inlining_time, '
          'st.jit_optimization_count, '
          'st.jit_optimization_time, '
          'st.jit_emission_count, '
          'st.jit_emission_time, '
          'st.temp_blk_read_time, '
          'st.temp_blk_write_time, '
          'st.local_blk_read_time, '
          'st.local_blk_write_time, '
          'st.jit_deform_count, '
          'st.jit_deform_time, '
          'st.parallel_workers_to_launch, '
          'st.parallel_workers_launched, '
          'st.generic_plan_calls, '
          'st.custom_plan_calls, '
          'st.stats_since, '
          'st.minmax_stats_since '
        );
      ELSE
        RAISE 'Unsupported pg_stat_statements extension version.';
    END CASE; -- pg_stat_statememts versions

    -- Get statements data
    EXECUTE format($query$
        INSERT INTO last_stat_statements (
          server_id, sample_id, userid, username, datid, queryid,
          plans, total_plan_time, min_plan_time, max_plan_time,
          mean_plan_time, stddev_plan_time, calls, total_exec_time,
          min_exec_time, max_exec_time, mean_exec_time, stddev_exec_time,
          rows, shared_blks_hit, shared_blks_read, shared_blks_dirtied,
          shared_blks_written, local_blks_hit, local_blks_read,
          local_blks_dirtied, local_blks_written, temp_blks_read,
          temp_blks_written, shared_blk_read_time, shared_blk_write_time,
          wal_records, wal_fpi, wal_bytes, wal_buffers_full, toplevel,
          in_sample, jit_functions, jit_generation_time, jit_inlining_count,
          jit_inlining_time, jit_optimization_count, jit_optimization_time,
          jit_emission_count, jit_emission_time, temp_blk_read_time,
          temp_blk_write_time, local_blk_read_time, local_blk_write_time,
          jit_deform_count, jit_deform_time, parallel_workers_to_launch,
          parallel_workers_launched, generic_plan_calls, custom_plan_calls,
          stats_since, minmax_stats_since
        )
        SELECT
          $1, $2,
          dbl.userid::oid,
          dbl.username::name,
          dbl.datid::oid,
          dbl.queryid::bigint,
          dbl.plans::bigint,
          dbl.total_plan_time::double precision,
          dbl.min_plan_time::double precision,
          dbl.max_plan_time::double precision,
          dbl.mean_plan_time::double precision,
          dbl.stddev_plan_time::double precision,
          dbl.calls::bigint,
          dbl.total_exec_time::double precision,
          dbl.min_exec_time::double precision,
          dbl.max_exec_time::double precision,
          dbl.mean_exec_time::double precision,
          dbl.stddev_exec_time::double precision,
          dbl.rows::bigint,
          dbl.shared_blks_hit::bigint,
          dbl.shared_blks_read::bigint,
          dbl.shared_blks_dirtied::bigint,
          dbl.shared_blks_written::bigint,
          dbl.local_blks_hit::bigint,
          dbl.local_blks_read::bigint,
          dbl.local_blks_dirtied::bigint,
          dbl.local_blks_written::bigint,
          dbl.temp_blks_read::bigint,
          dbl.temp_blks_written::bigint,
          dbl.shared_blk_read_time::double precision,
          dbl.shared_blk_write_time::double precision,
          dbl.wal_records::bigint,
          dbl.wal_fpi::bigint,
          dbl.wal_bytes::numeric,
          dbl.wal_buffers_full::bigint,
          dbl.toplevel::boolean,
          false,
          dbl.jit_functions::bigint,
          dbl.jit_generation_time::double precision,
          dbl.jit_inlining_count::bigint,
          dbl.jit_inlining_time::double precision,
          dbl.jit_optimization_count::bigint,
          dbl.jit_optimization_time::double precision,
          dbl.jit_emission_count::bigint,
          dbl.jit_emission_time::double precision,
          dbl.temp_blk_read_time::double precision,
          dbl.temp_blk_write_time::double precision,
          dbl.local_blk_read_time::double precision,
          dbl.local_blk_write_time::double precision,
          dbl.jit_deform_count::bigint,
          dbl.jit_deform_time::double precision,
          dbl.parallel_workers_to_launch::bigint,
          dbl.parallel_workers_launched::bigint,
          dbl.generic_plan_calls::bigint,
          dbl.custom_plan_calls::bigint,
          dbl.stats_since::timestamp with time zone,
          dbl.minmax_stats_since::timestamp with time zone
        FROM (%s) AS dbl
      $query$, st_query)
    USING sserver_id, s_id;
    GET DIAGNOSTICS statements_rows = ROW_COUNT;
    -- Whe should skip the following when no statements are available
    IF statements_rows = 0 THEN
      RETURN;
    END IF;

    EXECUTE format('ANALYZE last_stat_statements_srv%1$s',
      sserver_id);

    PERFORM mark_pg_stat_statements(sserver_id, s_id, topn,
      (properties #> '{properties,statements_reset}') = to_jsonb(true));

    -- Get queries texts
    CASE (
        SELECT extversion
        FROM jsonb_to_recordset(properties #> '{extensions}')
          AS ext(extname text, extversion text)
        WHERE extname = 'pg_stat_statements'
      )
      WHEN '1.3','1.4','1.5','1.6','1.7','1.8'
      THEN
        st_query :=
          'SELECT userid, dbid AS datid, true AS toplevel, queryid, '||
          $o$regexp_replace(query,$i$\s+$i$,$i$ $i$,$i$g$i$) AS query $o$ ||
          'FROM %1$I.pg_stat_statements(true) '
          'WHERE queryid IN (%s)';
      WHEN '1.9', '1.10', '1.11', '1.12', '1.13'
      THEN
        st_query :=
          'SELECT userid, dbid AS datid, toplevel, queryid, '||
          $o$regexp_replace(query,$i$\s+$i$,$i$ $i$,$i$g$i$) AS query $o$ ||
          'FROM %1$I.pg_stat_statements(true) '
          'WHERE queryid IN (%s)';
      ELSE
        RAISE 'Unsupported pg_stat_statements extension version.';
    END CASE;

    -- Substitute pg_stat_statements extension schema and queries list
    st_query := format(st_query,
        (
          SELECT extnamespace FROM jsonb_to_recordset(properties #> '{extensions}')
            AS x(extname text, extnamespace text)
          WHERE extname = 'pg_stat_statements'
        ),
        (
          SELECT string_agg(queryid::text,',')
          FROM last_stat_statements
          WHERE
            (server_id, sample_id, in_sample) =
            (sserver_id, s_id, true)
        )
    );

    EXECUTE format(
      'SELECT COALESCE(jsonb_agg(to_jsonb(dbl)), ''[]''::jsonb) FROM (%s) AS dbl',
      st_query
    ) INTO statement_texts;

    -- Now we can save statement
    /*
    Hash function md5() is not working when the FIPS mode is
    enabled. This can cause sampling falure in PG14+. SHA functions
    however are unavailable before PostgreSQL 11. We'll use md5()
    before PG11, and sha224 after PG11
    */
    IF current_setting('server_version_num')::integer < 110000 THEN
      FOR qres IN (
        SELECT
          userid,
          datid,
          toplevel,
          queryid,
          query
        FROM jsonb_to_recordset(statement_texts) AS
          dbl(
              userid    oid,
              datid     oid,
              toplevel  boolean,
              queryid   bigint,
              query     text
            )
          JOIN last_stat_statements lst USING (userid, datid, toplevel, queryid)
        WHERE
          (lst.server_id, lst.sample_id, lst.in_sample) =
          (sserver_id, s_id, true)
      )
      LOOP
        -- statement texts
        INSERT INTO stmt_list AS isl (
            server_id,
            last_sample_id,
            queryid_md5,
            query
          )
        VALUES (
            sserver_id,
            NULL,
            md5(COALESCE(qres.query, '')),
            qres.query
          )
        ON CONFLICT ON CONSTRAINT pk_stmt_list
        DO UPDATE SET last_sample_id = NULL
        WHERE
          isl.last_sample_id IS NOT NULL;

        -- bind queryid to queryid_md5 for this sample
        -- different text queries can have the same queryid
        -- between samples
        UPDATE last_stat_statements SET queryid_md5 = md5(COALESCE(qres.query, ''))
        WHERE (server_id, sample_id, userid, datid, toplevel, queryid) =
          (sserver_id, s_id, qres.userid, qres.datid, qres.toplevel, qres.queryid);
      END LOOP; -- over sample statements
    ELSE
      FOR qres IN (
        SELECT
          userid,
          datid,
          toplevel,
          queryid,
          query
        FROM jsonb_to_recordset(statement_texts) AS
          dbl(
              userid    oid,
              datid     oid,
              toplevel  boolean,
              queryid   bigint,
              query     text
            )
          JOIN last_stat_statements lst USING (userid, datid, toplevel, queryid)
        WHERE
          (lst.server_id, lst.sample_id, lst.in_sample) =
          (sserver_id, s_id, true)
      )
      LOOP
        -- statement texts
        INSERT INTO stmt_list AS isl (
            server_id,
            last_sample_id,
            queryid_md5,
            query
          )
        VALUES (
            sserver_id,
            NULL,
            left(encode(sha224(convert_to(COALESCE(qres.query, ''),'UTF8')), 'base64'), 32),
            qres.query
          )
        ON CONFLICT ON CONSTRAINT pk_stmt_list
        DO UPDATE SET last_sample_id = NULL
        WHERE
          isl.last_sample_id IS NOT NULL;

        -- bind queryid to queryid_md5 for this sample
        -- different text queries can have the same queryid
        -- between samples
        UPDATE last_stat_statements SET queryid_md5 =
          left(encode(sha224(convert_to(COALESCE(qres.query, ''),'UTF8')), 'base64'), 32)
        WHERE (server_id, sample_id, userid, datid, toplevel, queryid) =
          (sserver_id, s_id, qres.userid, qres.datid, qres.toplevel, qres.queryid);
      END LOOP; -- over sample statements
    END IF;

    -- Flushing statements
    st_query := NULL;
    CASE (
        SELECT extversion
        FROM jsonb_to_recordset(properties #> '{extensions}')
          AS ext(extname text, extversion text)
        WHERE extname = 'pg_stat_statements'
      )
      -- pg_stat_statements v 1.3-1.8
      WHEN '1.3','1.4','1.5','1.6','1.7','1.8','1.9','1.10'
      THEN
        IF (properties #> '{properties,statements_reset}') = to_jsonb(true) THEN
          st_query := 'SELECT %1$I.pg_stat_statements_reset() IS NULL';
        END IF;
      WHEN '1.11','1.12','1.13'
      THEN
        IF (properties #> '{properties,statements_reset}')::boolean THEN
          st_query := 'SELECT %1$I.pg_stat_statements_reset() IS NULL';
        ELSE
          st_query := 'SELECT %1$I.pg_stat_statements_reset(0, 0, 0, true) IS NULL';
        END IF;
      ELSE
        RAISE 'Unsupported pg_stat_statements version.';
    END CASE;

    IF st_query IS NOT NULL THEN
      st_query :=
        format(st_query,
          (
            SELECT extnamespace FROM jsonb_to_recordset(properties #> '{extensions}')
              AS x(extname text, extnamespace text)
            WHERE extname = 'pg_stat_statements'
          )
        );

      EXECUTE st_query;
    END IF;

    -- Save the diffs in a sample
    PERFORM save_pg_stat_statements(sserver_id, s_id,
      (properties #> '{properties,statements_reset}') = to_jsonb(true));
    -- Delete obsolete last_* data
    DELETE FROM last_stat_kcache WHERE server_id = sserver_id AND sample_id < s_id;
    DELETE FROM last_stat_statements WHERE server_id = sserver_id AND sample_id < s_id;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION mark_pg_stat_statements(IN sserver_id integer, IN s_id integer, IN topn integer,
  IN statements_reset boolean)
RETURNS void
SET search_path=@extschema@ AS $$
  -- Mark statements to include in a sample
  UPDATE last_stat_statements ust
  SET in_sample = true
  FROM
    (SELECT
      cur.server_id,
      cur.sample_id,
      cur.userid,
      cur.datid,
      cur.queryid,
      cur.toplevel,
      CASE WHEN cur.total_plan_time - COALESCE(lst.total_plan_time, 0) > 0 THEN
        row_number() over (ORDER BY cur.total_plan_time + cur.total_exec_time -
            COALESCE(lst.total_plan_time + lst.total_exec_time, 0) DESC NULLS LAST)
      ELSE NULL END AS time_rank,

      CASE WHEN cur.total_plan_time - COALESCE(lst.total_plan_time, 0) > 0 THEN
        row_number() over (ORDER BY cur.total_plan_time - COALESCE(lst.total_plan_time, 0) DESC NULLS LAST)
      ELSE NULL END AS plan_time_rank,

      row_number() over (ORDER BY cur.total_exec_time - COALESCE(lst.total_exec_time, 0) DESC NULLS LAST)
        AS exec_time_rank,
      row_number() over (ORDER BY cur.mean_exec_time - COALESCE(lst.mean_exec_time, 0) DESC NULLS LAST)
        AS mean_exec_time_rank,
      row_number() over (ORDER BY cur.calls - COALESCE(lst.calls, 0) DESC NULLS LAST) AS calls_rank,

      CASE WHEN COALESCE(cur.shared_blk_read_time,0) + COALESCE(cur.shared_blk_write_time,0) -
        COALESCE(lst.shared_blk_read_time,0) - COALESCE(lst.shared_blk_write_time,0) > 0 THEN
          row_number() over (ORDER BY cur.shared_blk_read_time + cur.shared_blk_write_time -
            COALESCE(lst.shared_blk_read_time + lst.shared_blk_write_time, 0) DESC NULLS LAST)
      ELSE NULL END AS io_time_rank,

      CASE WHEN COALESCE(cur.temp_blk_read_time, 0) + COALESCE(cur.temp_blk_write_time, 0) -
        COALESCE(lst.temp_blk_read_time, 0) - COALESCE(lst.temp_blk_write_time, 0) > 0 THEN
        row_number() over (ORDER BY COALESCE(cur.temp_blk_read_time, 0) + COALESCE(cur.temp_blk_write_time, 0) -
          COALESCE(lst.temp_blk_read_time, 0) - COALESCE(lst.temp_blk_write_time, 0)
          DESC NULLS LAST)
      ELSE NULL END AS io_temp_rank,

      row_number() over (ORDER BY cur.shared_blks_hit + cur.shared_blks_read -
        COALESCE(lst.shared_blks_hit + lst.shared_blks_read, 0) DESC NULLS LAST) AS gets_rank,

      row_number() over (ORDER BY cur.shared_blks_read - COALESCE(lst.shared_blks_read, 0) DESC NULLS LAST)
        AS read_rank,
      row_number() over (ORDER BY cur.shared_blks_dirtied - COALESCE(lst.shared_blks_dirtied, 0) DESC NULLS LAST)
        AS dirtied_rank,
      row_number() over (ORDER BY cur.shared_blks_written - COALESCE(lst.shared_blks_written, 0) DESC NULLS LAST)
        AS written_rank,

      CASE WHEN cur.temp_blks_written + cur.local_blks_written -
        COALESCE(lst.temp_blks_written + lst.local_blks_written, 0) > 0 THEN
        row_number() over (ORDER BY cur.temp_blks_written + cur.local_blks_written -
          COALESCE(lst.temp_blks_written + lst.local_blks_written, 0) DESC NULLS LAST)
      ELSE NULL END AS tempw_rank,

      CASE WHEN cur.temp_blks_read + cur.local_blks_read -
        COALESCE(lst.temp_blks_read + lst.local_blks_read, 0) > 0 THEN
        row_number() over (ORDER BY cur.temp_blks_read + cur.local_blks_read -
          COALESCE(lst.temp_blks_read + lst.local_blks_read, 0) DESC NULLS LAST)
      ELSE NULL END AS tempr_rank,

      CASE WHEN cur.wal_bytes - COALESCE(lst.wal_bytes, 0) > 0 THEN
        row_number() over (ORDER BY cur.wal_bytes - COALESCE(lst.wal_bytes, 0) DESC NULLS LAST)
      ELSE NULL END AS wal_rank,
      CASE WHEN cur.parallel_workers_to_launch + cur.parallel_workers_launched -
      COALESCE(lst.parallel_workers_to_launch, 0) - COALESCE(lst.parallel_workers_launched, 0) > 0 THEN
        row_number() over (ORDER BY cur.parallel_workers_to_launch + cur.parallel_workers_launched -
          COALESCE(lst.parallel_workers_to_launch, 0) - COALESCE(lst.parallel_workers_launched, 0) DESC NULLS LAST)
      ELSE NULL END AS wrkrs_rank
    FROM
      last_stat_statements cur
      -- In case of statements in already dropped database
      JOIN sample_stat_database db USING (server_id, sample_id, datid)
      LEFT JOIN last_stat_statements lst ON
        (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
        cur.userid, cur.queryid, cur.toplevel) =
        (sserver_id, sserver_id, s_id, s_id - 1, lst.datid, lst.userid,
        lst.queryid, lst.toplevel) AND
        (cur.stats_since = lst.stats_since OR (
            (NOT statements_reset) AND
            cur.calls >= lst.calls
          )
        )
    WHERE
      (cur.server_id, cur.sample_id) = (sserver_id, s_id)
    ) diff
  WHERE
    (
      least(
        time_rank,
        plan_time_rank,
        wal_rank,
        io_time_rank,
        exec_time_rank,
        mean_exec_time_rank,
        calls_rank,
        gets_rank,
        read_rank,
        dirtied_rank,
        written_rank,
        io_temp_rank,
        tempw_rank,
        tempr_rank,
        wrkrs_rank
      ) <= topn
    )
    AND
    (ust.server_id ,ust.sample_id, ust.userid, ust.datid, ust.queryid, ust.toplevel, ust.in_sample) =
    (diff.server_id, diff.sample_id, diff.userid, diff.datid, diff.queryid, diff.toplevel, false);

  -- Mark rusage stats to include in a sample
  UPDATE last_stat_statements ust
  SET in_sample = true
  FROM
    (SELECT
      cur.server_id,
      cur.sample_id,
      cur.userid,
      cur.datid,
      cur.queryid,
      cur.toplevel,
      CASE WHEN COALESCE(cur.plan_user_time, 0.0) + COALESCE(cur.plan_system_time, 0.0) -
        COALESCE(lst.plan_user_time, 0.0) - COALESCE(lst.plan_system_time, 0.0) > 0.0
      THEN
        row_number() OVER (ORDER BY
          COALESCE(cur.plan_user_time, 0.0) + COALESCE(cur.plan_system_time, 0.0) -
          COALESCE(lst.plan_user_time, 0.0) - COALESCE(lst.plan_system_time, 0.0)
          DESC NULLS LAST)
      ELSE NULL END AS plan_cpu_time_rank,

      row_number() OVER (ORDER BY
         cur.exec_user_time + cur.exec_system_time -
         COALESCE(lst.exec_user_time, 0.0) - COALESCE(lst.exec_system_time, 0.0)
         DESC NULLS LAST) AS exec_cpu_time_rank,

      CASE WHEN COALESCE(cur.plan_reads, 0.0) + COALESCE(cur.plan_writes, 0.0) -
        COALESCE(lst.plan_reads, 0.0) - COALESCE(lst.plan_writes, 0.0) > 0.0
      THEN
        row_number() OVER (ORDER BY
          COALESCE(cur.plan_reads, 0.0) + COALESCE(cur.plan_writes, 0.0) -
          COALESCE(lst.plan_reads, 0.0) - COALESCE(lst.plan_writes, 0.0)
        DESC NULLS LAST)
      ELSE NULL END AS plan_io_rank,

      row_number() OVER (ORDER BY
        COALESCE(cur.exec_reads, 0) + COALESCE(cur.exec_writes, 0) -
        COALESCE(lst.exec_reads, 0) - COALESCE(lst.exec_writes, 0)
        DESC NULLS LAST) AS exec_io_rank
    FROM
      last_stat_kcache cur
      -- In case of statements in already dropped database
      JOIN sample_stat_database db USING (server_id, sample_id, datid)
      LEFT JOIN last_stat_kcache lst ON
        (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
        cur.userid, cur.queryid, cur.toplevel) =
        (sserver_id, sserver_id, s_id, s_id - 1, lst.datid, lst.userid,
        lst.queryid, lst.toplevel) AND
        (cur.stats_since = lst.stats_since OR (
            (NOT statements_reset) AND
            cur.exec_user_time >= lst.exec_user_time
          )
        )
    WHERE
      (cur.server_id, cur.sample_id) = (sserver_id, s_id)
    ) diff
  WHERE
    (
      least(
        plan_cpu_time_rank,
        plan_io_rank,
        exec_cpu_time_rank,
        exec_io_rank
      ) <= topn
    )
    AND
    (ust.server_id, ust.sample_id, ust.userid, ust.datid, ust.queryid, ust.toplevel, ust.in_sample) =
    (diff.server_id, diff.sample_id, diff.userid, diff.datid, diff.queryid, diff.toplevel, false);
$$ LANGUAGE sql;

CREATE FUNCTION save_pg_stat_statements(IN sserver_id integer, IN s_id integer,
  IN statements_reset boolean)
RETURNS void
SET search_path=@extschema@ AS $$
  -- This function performs save marked statements data in sample tables
  -- User names
  INSERT INTO roles_list AS irl (
    server_id,
    last_sample_id,
    userid,
    username
  )
  SELECT DISTINCT
    sserver_id,
    NULL::integer,
    st.userid,
    COALESCE(st.username, '_unknown_')
  FROM
    last_stat_statements st
  WHERE (st.server_id, st.sample_id, in_sample) = (sserver_id, s_id, true)
  ON CONFLICT ON CONSTRAINT pk_roles_list
  DO UPDATE SET
    (last_sample_id, username) =
    (EXCLUDED.last_sample_id, EXCLUDED.username)
  WHERE
    (irl.last_sample_id, irl.username) IS DISTINCT FROM
    (EXCLUDED.last_sample_id, EXCLUDED.username)
  ;

  -- Statement stats
  INSERT INTO sample_statements(
    server_id,
    sample_id,
    userid,
    datid,
    toplevel,
    queryid,
    queryid_md5,
    plans,
    total_plan_time,
    min_plan_time,
    max_plan_time,
    mean_plan_time,
    sum_plan_time_sq,
    calls,
    total_exec_time,
    min_exec_time,
    max_exec_time,
    mean_exec_time,
    sum_exec_time_sq,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    temp_blk_read_time,
    temp_blk_write_time,
    local_blk_read_time,
    local_blk_write_time,
    jit_deform_count,
    jit_deform_time,
    parallel_workers_to_launch,
    parallel_workers_launched,
    generic_plan_calls,
    custom_plan_calls,
    stats_since,
    minmax_stats_since
  )
  SELECT
    sserver_id,
    s_id,
    cur.userid,
    cur.datid,
    cur.toplevel,
    cur.queryid,
    cur.queryid_md5,
    cur.plans - COALESCE(lst.plans, 0),
    cur.total_plan_time - COALESCE(lst.total_plan_time, 0.0),
    cur.min_plan_time,
    cur.max_plan_time,
    (cur.mean_plan_time * cur.plans -
      COALESCE(lst.mean_plan_time * lst.plans, 0)) /
      NULLIF(cur.plans - COALESCE(lst.plans, 0), 0)
    AS mean_plan_time,
    CASE
      WHEN cur.plans - COALESCE(lst.plans, 0) = 0 THEN 0
      WHEN cur.plans - COALESCE(lst.plans, 0) = 1 THEN
        pow(cast(cur.total_plan_time - COALESCE(lst.total_plan_time, 0.0) AS numeric), 2)
      ELSE
        pow(cur.stddev_plan_time::numeric, 2) * cur.plans +
          pow(cur.mean_plan_time::numeric, 2) * cur.plans -
          COALESCE(pow(lst.stddev_plan_time::numeric, 2) * lst.plans +
          pow(lst.mean_plan_time::numeric, 2) * lst.plans, 0)
    END AS sum_plan_time_sq,
    cur.calls - COALESCE(lst.calls, 0),
    cur.total_exec_time - COALESCE(lst.total_exec_time, 0.0),
    cur.min_exec_time,
    cur.max_exec_time,
    (cur.mean_exec_time * cur.calls -
      COALESCE(lst.mean_exec_time * lst.calls, 0)) /
      NULLIF(cur.calls - COALESCE(lst.calls, 0), 0)
    AS mean_exec_time,
    CASE
      WHEN cur.calls - COALESCE(lst.calls, 0) = 0 THEN 0
      WHEN cur.calls - COALESCE(lst.calls, 0) = 1 THEN
        pow(cast(cur.total_exec_time - COALESCE(lst.total_exec_time, 0.0) as numeric), 2)
      ELSE
        pow(cur.stddev_exec_time::numeric, 2) * cur.calls +
          pow(cur.mean_exec_time::numeric, 2) * cur.calls -
          COALESCE(pow(lst.stddev_exec_time::numeric, 2) * lst.calls +
          pow(lst.mean_exec_time::numeric, 2) * lst.calls, 0)
    END AS sum_exec_time_sq,
    cur.rows - COALESCE(lst.rows, 0),
    cur.shared_blks_hit - COALESCE(lst.shared_blks_hit, 0),
    cur.shared_blks_read - COALESCE(lst.shared_blks_read, 0),
    cur.shared_blks_dirtied - COALESCE(lst.shared_blks_dirtied, 0),
    cur.shared_blks_written - COALESCE(lst.shared_blks_written, 0),
    cur.local_blks_hit - COALESCE(lst.local_blks_hit, 0),
    cur.local_blks_read - COALESCE(lst.local_blks_read, 0),
    cur.local_blks_dirtied - COALESCE(lst.local_blks_dirtied, 0),
    cur.local_blks_written - COALESCE(lst.local_blks_written, 0),
    cur.temp_blks_read - COALESCE(lst.temp_blks_read, 0),
    cur.temp_blks_written - COALESCE(lst.temp_blks_written, 0),
    cur.shared_blk_read_time - COALESCE(lst.shared_blk_read_time, 0),
    cur.shared_blk_write_time - COALESCE(lst.shared_blk_write_time, 0),
    cur.wal_records - COALESCE(lst.wal_records, 0),
    cur.wal_fpi - COALESCE(lst.wal_fpi, 0),
    cur.wal_bytes - COALESCE(lst.wal_bytes, 0),
    cur.wal_buffers_full - COALESCE(lst.wal_buffers_full, 0),
    cur.jit_functions - COALESCE(lst.jit_functions, 0),
    cur.jit_generation_time - COALESCE(lst.jit_generation_time, 0),
    cur.jit_inlining_count - COALESCE(lst.jit_inlining_count, 0),
    cur.jit_inlining_time - COALESCE(lst.jit_inlining_time, 0),
    cur.jit_optimization_count - COALESCE(lst.jit_optimization_count, 0),
    cur.jit_optimization_time - COALESCE(lst.jit_optimization_time, 0),
    cur.jit_emission_count - COALESCE(lst.jit_emission_count, 0),
    cur.jit_emission_time - COALESCE(lst.jit_emission_time, 0),
    cur.temp_blk_read_time - COALESCE(lst.temp_blk_read_time, 0),
    cur.temp_blk_write_time - COALESCE(lst.temp_blk_write_time, 0),
    cur.local_blk_read_time - COALESCE(lst.local_blk_read_time, 0),
    cur.local_blk_write_time - COALESCE(lst.local_blk_write_time, 0),
    cur.jit_deform_count - COALESCE(lst.jit_deform_count, 0),
    cur.jit_deform_time - COALESCE(lst.jit_deform_time, 0),
    cur.parallel_workers_to_launch - COALESCE(lst.parallel_workers_to_launch, 0),
    cur.parallel_workers_launched - COALESCE(lst.parallel_workers_launched, 0),
    cur.generic_plan_calls - COALESCE(lst.generic_plan_calls, 0),
    cur.custom_plan_calls - COALESCE(lst.custom_plan_calls, 0),
    cur.stats_since,
    cur.minmax_stats_since
  FROM
    last_stat_statements cur JOIN stmt_list USING (server_id, queryid_md5)
    LEFT JOIN last_stat_statements lst ON
      (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
      cur.userid, cur.queryid, cur.toplevel) =
      (sserver_id, sserver_id, s_id, s_id - 1, lst.datid,
      lst.userid, lst.queryid, lst.toplevel) AND
      (cur.stats_since = lst.stats_since OR (
          (NOT statements_reset) AND
          cur.calls >= lst.calls
        )
      )
  WHERE
    (cur.server_id, cur.sample_id, cur.in_sample) = (sserver_id, s_id, true);

  /*
  * Aggregated statements stats
  */
  INSERT INTO sample_statements_total(
    server_id,
    sample_id,
    datid,
    plans,
    total_plan_time,
    calls,
    total_exec_time,
    rows,
    shared_blks_hit,
    shared_blks_read,
    shared_blks_dirtied,
    shared_blks_written,
    local_blks_hit,
    local_blks_read,
    local_blks_dirtied,
    local_blks_written,
    temp_blks_read,
    temp_blks_written,
    shared_blk_read_time,
    shared_blk_write_time,
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    statements,
    jit_functions,
    jit_generation_time,
    jit_inlining_count,
    jit_inlining_time,
    jit_optimization_count,
    jit_optimization_time,
    jit_emission_count,
    jit_emission_time,
    temp_blk_read_time,
    temp_blk_write_time,
    mean_max_plan_time,
    mean_max_exec_time,
    mean_min_plan_time,
    mean_min_exec_time,
    local_blk_read_time,
    local_blk_write_time,
    jit_deform_count,
    jit_deform_time
  )
  SELECT
    cur.server_id,
    s_id,
    cur.datid,
    sum(cur.plans - COALESCE(lst.plans, 0)),
    sum(cur.total_plan_time - COALESCE(lst.total_plan_time, 0.0)),
    sum(cur.calls - COALESCE(lst.calls, 0)),
    sum(cur.total_exec_time - COALESCE(lst.total_exec_time, 0.0)),
    sum(cur.rows - COALESCE(lst.rows, 0)),
    sum(cur.shared_blks_hit - COALESCE(lst.shared_blks_hit, 0)),
    sum(cur.shared_blks_read - COALESCE(lst.shared_blks_read, 0)),
    sum(cur.shared_blks_dirtied - COALESCE(lst.shared_blks_dirtied, 0)),
    sum(cur.shared_blks_written - COALESCE(lst.shared_blks_written, 0)),
    sum(cur.local_blks_hit - COALESCE(lst.local_blks_hit, 0)),
    sum(cur.local_blks_read - COALESCE(lst.local_blks_read, 0)),
    sum(cur.local_blks_dirtied - COALESCE(lst.local_blks_dirtied, 0)),
    sum(cur.local_blks_written - COALESCE(lst.local_blks_written, 0)),
    sum(cur.temp_blks_read - COALESCE(lst.temp_blks_read, 0)),
    sum(cur.temp_blks_written - COALESCE(lst.temp_blks_written, 0)),
    sum(cur.shared_blk_read_time - COALESCE(lst.shared_blk_read_time, 0)),
    sum(cur.shared_blk_write_time - COALESCE(lst.shared_blk_write_time, 0)),
    sum(cur.wal_records - COALESCE(lst.wal_records, 0)),
    sum(cur.wal_fpi - COALESCE(lst.wal_fpi, 0)),
    sum(cur.wal_bytes - COALESCE(lst.wal_bytes, 0)),
    sum(cur.wal_buffers_full - COALESCE(lst.wal_buffers_full, 0)),
    count(nullif(cur.calls - COALESCE(lst.calls, 0), 0)),
    sum(cur.jit_functions - COALESCE(lst.jit_functions, 0)),
    sum(cur.jit_generation_time - COALESCE(lst.jit_generation_time, 0)),
    sum(cur.jit_inlining_count - COALESCE(lst.jit_inlining_count, 0)),
    sum(cur.jit_inlining_time - COALESCE(lst.jit_inlining_time, 0)),
    sum(cur.jit_optimization_count - COALESCE(lst.jit_optimization_count, 0)),
    sum(cur.jit_optimization_time - COALESCE(lst.jit_optimization_time, 0)),
    sum(cur.jit_emission_count - COALESCE(lst.jit_emission_count, 0)),
    sum(cur.jit_emission_time - COALESCE(lst.jit_emission_time, 0)),
    sum(cur.temp_blk_read_time - COALESCE(lst.temp_blk_read_time, 0)),
    sum(cur.temp_blk_write_time - COALESCE(lst.temp_blk_write_time, 0)),
    avg(cur.max_plan_time)::double precision,
    avg(cur.max_exec_time)::double precision,
    avg(cur.min_plan_time)::double precision,
    avg(cur.min_exec_time)::double precision,
    sum(cur.local_blk_read_time - COALESCE(lst.local_blk_read_time, 0)),
    sum(cur.local_blk_write_time - COALESCE(lst.local_blk_write_time, 0)),
    sum(cur.jit_deform_count - COALESCE(lst.jit_deform_count, 0)),
    sum(cur.jit_deform_time - COALESCE(lst.jit_deform_time, 0))
  FROM
    last_stat_statements cur
    -- In case of already dropped database
    JOIN sample_stat_database ssd USING (server_id, sample_id, datid)
    LEFT JOIN last_stat_statements lst ON
      (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
      cur.userid, cur.queryid, cur.toplevel) =
      (sserver_id, sserver_id, s_id, s_id - 1, lst.datid,
      lst.userid, lst.queryid, lst.toplevel) AND
      (cur.stats_since = lst.stats_since OR (
          (NOT statements_reset) AND
          cur.calls >= lst.calls
        )
      )
  WHERE
    (cur.server_id, cur.sample_id) = (sserver_id, s_id)
  GROUP BY
    cur.server_id,
    cur.sample_id,
    cur.datid
  ;

  /*
  * If rusage data is available we should just save it in sample for saved
  * statements
  */
  INSERT INTO sample_kcache (
      server_id,
      sample_id,
      userid,
      datid,
      queryid,
      queryid_md5,
      plan_user_time,
      plan_system_time,
      plan_minflts,
      plan_majflts,
      plan_nswaps,
      plan_reads,
      plan_writes,
      plan_msgsnds,
      plan_msgrcvs,
      plan_nsignals,
      plan_nvcsws,
      plan_nivcsws,
      exec_user_time,
      exec_system_time,
      exec_minflts,
      exec_majflts,
      exec_nswaps,
      exec_reads,
      exec_writes,
      exec_msgsnds,
      exec_msgrcvs,
      exec_nsignals,
      exec_nvcsws,
      exec_nivcsws,
      toplevel,
      stats_since
  )
  SELECT
    cur.server_id,
    cur.sample_id,
    cur.userid,
    cur.datid,
    cur.queryid,
    sst.queryid_md5,
    cur.plan_user_time - COALESCE(lst.plan_user_time, 0.0),
    cur.plan_system_time - COALESCE(lst.plan_system_time, 0.0),
    cur.plan_minflts - COALESCE(lst.plan_minflts, 0),
    cur.plan_majflts - COALESCE(lst.plan_majflts, 0),
    cur.plan_nswaps - COALESCE(lst.plan_nswaps, 0),
    cur.plan_reads - COALESCE(lst.plan_reads, 0),
    cur.plan_writes - COALESCE(lst.plan_writes, 0),
    cur.plan_msgsnds - COALESCE(lst.plan_msgsnds, 0),
    cur.plan_msgrcvs - COALESCE(lst.plan_msgrcvs, 0),
    cur.plan_nsignals - COALESCE(lst.plan_nsignals, 0),
    cur.plan_nvcsws - COALESCE(lst.plan_nvcsws, 0),
    cur.plan_nivcsws - COALESCE(lst.plan_nivcsws, 0),
    cur.exec_user_time - COALESCE(lst.exec_user_time, 0.0),
    cur.exec_system_time - COALESCE(lst.exec_system_time, 0.0),
    cur.exec_minflts - COALESCE(lst.exec_minflts, 0),
    cur.exec_majflts - COALESCE(lst.exec_majflts, 0),
    cur.exec_nswaps - COALESCE(lst.exec_nswaps, 0),
    cur.exec_reads - COALESCE(lst.exec_reads, 0),
    cur.exec_writes - COALESCE(lst.exec_writes, 0),
    cur.exec_msgsnds - COALESCE(lst.exec_msgsnds, 0),
    cur.exec_msgrcvs - COALESCE(lst.exec_msgrcvs, 0),
    cur.exec_nsignals - COALESCE(lst.exec_nsignals, 0),
    cur.exec_nvcsws - COALESCE(lst.exec_nvcsws, 0),
    cur.exec_nivcsws - COALESCE(lst.exec_nivcsws, 0),
    cur.toplevel,
    cur.stats_since
  FROM
    last_stat_kcache cur JOIN last_stat_statements sst ON
      (sst.server_id, cur.server_id, sst.sample_id, sst.userid, sst.datid, sst.queryid, sst.toplevel) =
      (sserver_id, sserver_id, cur.sample_id, cur.userid, cur.datid, cur.queryid, cur.toplevel)
      LEFT JOIN last_stat_kcache lst ON
        (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
        cur.userid, cur.queryid, cur.toplevel) =
        (sserver_id, sserver_id, s_id, s_id - 1, lst.datid, lst.userid,
        lst.queryid, lst.toplevel) AND
        (cur.stats_since = lst.stats_since OR (
            (NOT statements_reset) AND
            cur.exec_user_time >= lst.exec_user_time
          )
        )
  WHERE
    (cur.server_id, cur.sample_id, sst.in_sample) = (sserver_id, s_id, true)
    AND sst.queryid_md5 IS NOT NULL;

  -- Aggregated pg_stat_kcache data
  INSERT INTO sample_kcache_total(
    server_id,
    sample_id,
    datid,
    plan_user_time,
    plan_system_time,
    plan_minflts,
    plan_majflts,
    plan_nswaps,
    plan_reads,
    plan_writes,
    plan_msgsnds,
    plan_msgrcvs,
    plan_nsignals,
    plan_nvcsws,
    plan_nivcsws,
    exec_user_time,
    exec_system_time,
    exec_minflts,
    exec_majflts,
    exec_nswaps,
    exec_reads,
    exec_writes,
    exec_msgsnds,
    exec_msgrcvs,
    exec_nsignals,
    exec_nvcsws,
    exec_nivcsws,
    statements
  )
  SELECT
    cur.server_id,
    cur.sample_id,
    cur.datid,
    SUM(cur.plan_user_time - COALESCE(lst.plan_user_time, 0.0)),
    SUM(cur.plan_system_time - COALESCE(lst.plan_system_time, 0.0)),
    SUM(cur.plan_minflts - COALESCE(lst.plan_minflts, 0)),
    SUM(cur.plan_majflts - COALESCE(lst.plan_majflts, 0)),
    SUM(cur.plan_nswaps - COALESCE(lst.plan_nswaps, 0)),
    SUM(cur.plan_reads - COALESCE(lst.plan_reads, 0)),
    SUM(cur.plan_writes - COALESCE(lst.plan_writes, 0)),
    SUM(cur.plan_msgsnds - COALESCE(lst.plan_msgsnds, 0)),
    SUM(cur.plan_msgrcvs - COALESCE(lst.plan_msgrcvs, 0)),
    SUM(cur.plan_nsignals - COALESCE(lst.plan_nsignals, 0)),
    SUM(cur.plan_nvcsws - COALESCE(lst.plan_nvcsws, 0)),
    SUM(cur.plan_nivcsws - COALESCE(lst.plan_nivcsws, 0)),

    SUM(cur.exec_user_time - COALESCE(lst.exec_user_time, 0.0)),
    SUM(cur.exec_system_time - COALESCE(lst.exec_system_time, 0.0)),
    SUM(cur.exec_minflts - COALESCE(lst.exec_minflts, 0)),
    SUM(cur.exec_majflts - COALESCE(lst.exec_majflts, 0)),
    SUM(cur.exec_nswaps - COALESCE(lst.exec_nswaps, 0)),
    SUM(cur.exec_reads - COALESCE(lst.exec_reads, 0)),
    SUM(cur.exec_writes - COALESCE(lst.exec_writes, 0)),
    SUM(cur.exec_msgsnds - COALESCE(lst.exec_msgsnds, 0)),
    SUM(cur.exec_msgrcvs - COALESCE(lst.exec_msgrcvs, 0)),
    SUM(cur.exec_nsignals - COALESCE(lst.exec_nsignals, 0)),
    SUM(cur.exec_nvcsws - COALESCE(lst.exec_nvcsws, 0)),
    SUM(cur.exec_nivcsws - COALESCE(lst.exec_nivcsws, 0)),

    COUNT(NULLIF(cur.exec_user_time - COALESCE(lst.exec_user_time, 0.0), 0.0))
  FROM
    last_stat_kcache cur
    -- In case of already dropped database
    JOIN sample_stat_database db USING (server_id, sample_id, datid)
    LEFT JOIN last_stat_kcache lst ON
      (cur.server_id, lst.server_id, cur.sample_id, lst.sample_id, cur.datid,
      cur.userid, cur.queryid, cur.toplevel) =
      (sserver_id, sserver_id, s_id, s_id - 1, lst.datid, lst.userid,
      lst.queryid, lst.toplevel) AND
      (cur.stats_since = lst.stats_since OR (
          (NOT statements_reset) AND
          cur.exec_user_time >= lst.exec_user_time
        )
      )
  WHERE
    (cur.server_id, cur.sample_id) = (sserver_id, s_id) AND
    cur.toplevel
  GROUP BY
    cur.server_id,
    cur.sample_id,
    cur.datid
  ;
$$ LANGUAGE sql;
