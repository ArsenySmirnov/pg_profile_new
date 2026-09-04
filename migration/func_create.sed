/^CREATE FUNCTION collect_tablespace_stats(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION get_report_datasets(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION cluster_stat_io_reset_format(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION cluster_stat_lock_reset_format(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION cluster_stat_slru_reset_format(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION wal_stats_reset_format(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION wal_stats_reset_format_diff(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION collect_database_stats(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION collect_lock_tree(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION init_sample(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_archiver(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_bgwriter(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_io(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_lock(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_slru(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION query_pg_stat_wal(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION collect_pg_stat_statements_stats(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION take_sample_subset(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION take_sample(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION take_subsample(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION create_server_partitions(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION drop_server(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION collect_subsamples(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION get_report_context(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION blocking_tree_format(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION blocking_tree_format_diff(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION export_sample_dabox(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION import_sample_dabox(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/p
/^CREATE FUNCTION export_data(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
/^CREATE FUNCTION import_section_data_subsample(.*$/,/\$[[:space:]]*LANGUAGE[[:space:]]\+\(plpg\)\?sql[[:space:]]*;[[:space:]]*$/ { s/^CREATE FUNCTION/CREATE OR REPLACE FUNCTION/; p }
