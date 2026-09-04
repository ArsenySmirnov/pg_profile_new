CREATE FUNCTION take_sample(IN server name, IN skip_sizes boolean = NULL)
RETURNS TABLE (
    result      text,
    elapsed     interval day to second (2)
)
SET search_path=@extschema@ AS $$
DECLARE
    sserver_id          integer;
    server_sampleres    integer;
    etext               text := '';
    edetail             text := '';
    econtext            text := '';

    start_clock         timestamp (2) with time zone;
BEGIN
    SELECT server_id INTO sserver_id FROM servers WHERE server_name = take_sample.server;
    IF sserver_id IS NULL THEN
        RAISE 'Server not found';
    ELSE
        BEGIN
            start_clock := clock_timestamp()::timestamp (2) with time zone;
            server_sampleres := take_sample(sserver_id, take_sample.skip_sizes);
            elapsed := clock_timestamp()::timestamp (2) with time zone - start_clock;
            CASE server_sampleres
              WHEN 0 THEN
                result := 'OK';
              ELSE
                result := 'FAIL';
            END CASE;
            RETURN NEXT;
        EXCEPTION
            WHEN OTHERS THEN
                BEGIN
                    GET STACKED DIAGNOSTICS etext = MESSAGE_TEXT,
                        edetail = PG_EXCEPTION_DETAIL,
                        econtext = PG_EXCEPTION_CONTEXT;
                    result := format (E'%s\n%s\n%s', etext, econtext, edetail);
                    elapsed := clock_timestamp()::timestamp (2) with time zone - start_clock;
                    RETURN NEXT;
                END;
        END;
    END IF;
    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION take_sample(IN server name, IN skip_sizes boolean) IS
  'Statistics sample creation function (by server name)';
