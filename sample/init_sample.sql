CREATE FUNCTION init_sample(IN sserver_id integer, IN connect_server boolean
) RETURNS jsonb SET search_path=@extschema@ AS $$
DECLARE
    server_properties jsonb = '{"extensions":[],"settings":[],"timings":[],"properties":{}}'; -- version, extensions, etc.
    qres              record;
    qres_subsample    record;
    is_local          boolean;
    is_pgpro          boolean;
    observed_system_identifier bigint;
BEGIN
    SELECT server_name = 'local'
      INTO STRICT is_local
    FROM servers
    WHERE server_id = sserver_id;

    IF NOT is_local THEN
      RAISE 'Remote sampling is disabled. Only the local server is supported';
    END IF;

    server_properties := jsonb_set(server_properties, '{properties,in_sample}', to_jsonb(false));
    -- Conditionally set lock_timeout when it's not set
    server_properties := jsonb_set(server_properties,'{properties,lock_timeout_init}',
      to_jsonb(current_setting('lock_timeout')));
    IF (SELECT current_setting('lock_timeout')::interval = '0s'::interval) THEN
      SET lock_timeout TO '3s';
    END IF;
    server_properties := jsonb_set(server_properties,'{properties,lock_timeout_effective}',
      to_jsonb(current_setting('lock_timeout')));

    -- Getting timing collection setting
    BEGIN
        SELECT current_setting('{pg_profile}.track_sample_timings')::boolean AS collect_timings
          INTO qres;
        server_properties := jsonb_set(server_properties,
          '{collect_timings}',
          to_jsonb(qres.collect_timings)
        );
    EXCEPTION
        WHEN OTHERS THEN
          server_properties := jsonb_set(server_properties,
            '{collect_timings}',
            to_jsonb(false)
          );
    END;

    -- Getting TopN setting
    BEGIN
        SELECT least(current_setting('{pg_profile}.topn')::integer, 100) AS topn INTO qres;
        server_properties := jsonb_set(server_properties,'{properties,topn}',to_jsonb(qres.topn));
    EXCEPTION
        WHEN OTHERS THEN
          server_properties := jsonb_set(server_properties,
            '{properties,topn}',
            to_jsonb(20)
          );
    END;

    -- Getting statement stats reset setting
    BEGIN
        server_properties := jsonb_set(server_properties,
          '{properties,statements_reset}',
          to_jsonb(current_setting('{pg_profile}.statements_reset')::boolean)
        );
    EXCEPTION
        WHEN OTHERS THEN
          server_properties := jsonb_set(server_properties,
            '{properties,statements_reset}',
            to_jsonb(true)
          );
    END;

    server_properties := log_sample_timings(server_properties, 'total', 'start');

    server_properties := log_sample_timings(server_properties, 'get server environment', 'start');
    -- Get settings values for the server.
    FOR qres IN
      SELECT name, reset_val, unit, pending_restart
      FROM pg_catalog.pg_settings
      WHERE name = 'server_version_num'
    LOOP
      server_properties := jsonb_insert(server_properties,'{"settings",0}',to_jsonb(qres));
    END LOOP;

    -- Is it PostgresPro?
    SELECT count(*) = 3
      INTO STRICT is_pgpro
    FROM pg_catalog.pg_settings
    WHERE name IN ('pgpro_build','pgpro_edition','pgpro_version');
    server_properties := jsonb_set(server_properties,'{properties,pgpro}',to_jsonb(is_pgpro));

    -- Get extensions needed for statement statistics collection.
    FOR qres IN
      SELECT
        extname,
        extnamespace::regnamespace::name AS extnamespace,
        extversion
      FROM pg_catalog.pg_extension
      WHERE extname = 'pg_stat_statements'
    LOOP
      server_properties := jsonb_insert(server_properties,'{"extensions",0}',to_jsonb(qres));
    END LOOP;

    -- Check the local cluster system identifier.
    SELECT system_identifier
      INTO STRICT observed_system_identifier
    FROM pg_catalog.pg_control_system();

    SELECT
      min(reset_val::bigint) != observed_system_identifier AS sysid_changed,
      is_local AND min(local_control.system_identifier) != observed_system_identifier AS local_missmatch
      INTO STRICT qres
    FROM sample_settings
    CROSS JOIN pg_catalog.pg_control_system() AS local_control
    WHERE server_id = sserver_id AND name = 'system_identifier';
    IF qres.sysid_changed THEN
      RAISE 'Server system_identifier has changed! '
        'Ensure server connection string is correct. '
        'Consider creating a new server for this cluster.';
    END IF;
    IF qres.local_missmatch THEN
      RAISE 'Local system_identifier does not match '
        'with server specified by connection string of '
        '"local" server';
    END IF;

    -- Subsample settings collection
    -- Get last base sample identifier of a server
    SELECT
      last_sample_id,
      subsample_enabled,
      min_query_dur,
      min_xact_dur,
      min_xact_age,
      min_idle_xact_dur
      INTO STRICT qres_subsample
    FROM servers JOIN server_subsample USING (server_id)
    WHERE server_id = sserver_id;

    server_properties := jsonb_set(server_properties,
      '{properties,last_sample_id}',
      to_jsonb(qres_subsample.last_sample_id)
    );

    /* Getting subsample GUC thresholds used as defaults*/
    BEGIN
        SELECT current_setting('{pg_profile}.subsample_enabled')::boolean AS subsample_enabled
          INTO qres;
        server_properties := jsonb_set(
          server_properties,
          '{properties,subsample_enabled}',
          to_jsonb(COALESCE(qres_subsample.subsample_enabled, qres.subsample_enabled))
        );
    EXCEPTION
        WHEN OTHERS THEN
          server_properties := jsonb_set(server_properties,
            '{properties,subsample_enabled}',
            to_jsonb(COALESCE(qres_subsample.subsample_enabled, true))
          );
    END;

    -- Setup subsample settings when they are enabled
    IF (server_properties #>> '{properties,subsample_enabled}')::boolean THEN
      BEGIN
          SELECT current_setting('{pg_profile}.min_query_duration')::interval AS min_query_dur INTO qres;
          server_properties := jsonb_set(
            server_properties,
            '{properties,min_query_dur}',
            to_jsonb(COALESCE(qres_subsample.min_query_dur, qres.min_query_dur))
          );
      EXCEPTION
          WHEN OTHERS THEN
            server_properties := jsonb_set(server_properties,
              '{properties,min_query_dur}',
              COALESCE (
                to_jsonb(qres_subsample.min_query_dur)
                , 'null'::jsonb
              )
            );
      END;

      BEGIN
          SELECT current_setting('{pg_profile}.min_xact_duration')::interval AS min_xact_dur INTO qres;
          server_properties := jsonb_set(
            server_properties,
            '{properties,min_xact_dur}',
            to_jsonb(COALESCE(qres_subsample.min_xact_dur, qres.min_xact_dur))
          );
      EXCEPTION
          WHEN OTHERS THEN
            server_properties := jsonb_set(server_properties,
              '{properties,min_xact_dur}',
              COALESCE (
                to_jsonb(qres_subsample.min_xact_dur)
                , 'null'::jsonb
              )
            );
      END;

      BEGIN
          SELECT current_setting('{pg_profile}.min_xact_age')::integer AS min_xact_age INTO qres;
          server_properties := jsonb_set(
            server_properties,
            '{properties,min_xact_age}',
            to_jsonb(COALESCE(qres_subsample.min_xact_age, qres.min_xact_age))
          );
      EXCEPTION
          WHEN OTHERS THEN
            server_properties := jsonb_set(server_properties,
              '{properties,min_xact_age}',
              COALESCE (
                to_jsonb(qres_subsample.min_xact_age)
                , 'null'::jsonb
              )
            );
      END;

      BEGIN
          SELECT current_setting('{pg_profile}.min_idle_xact_duration')::interval AS min_idle_xact_dur INTO qres;
          server_properties := jsonb_set(
            server_properties,
            '{properties,min_idle_xact_dur}',
            to_jsonb(COALESCE(qres_subsample.min_idle_xact_dur, qres.min_idle_xact_dur))
          );
      EXCEPTION
          WHEN OTHERS THEN
            server_properties := jsonb_set(server_properties,
              '{properties,min_idle_xact_dur}',
              COALESCE (
                to_jsonb(qres_subsample.min_idle_xact_dur)
                , 'null'::jsonb
              )
            );
      END;
    END IF; -- when subsamples enabled
    RETURN server_properties;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION init_sample(IN sserver_id integer)
RETURNS jsonb
SET search_path=@extschema@ AS $$
  SELECT init_sample(sserver_id, false);
$$ LANGUAGE sql;
