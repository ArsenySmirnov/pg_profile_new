SELECT create_server('local','dbname='||current_database()||' port='||current_setting('port'));

-- The local DABOX-oriented mode must not open connections to other databases.
-- Cross-database object statistics will be supplied by the external collector.
SELECT set_server_setting('local', 'collect_objects', 'false');
