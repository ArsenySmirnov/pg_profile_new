# Передача pg_profile_new разработчику DABOX

## 1. Назначение и границы этапа

Форк собирает статистику непосредственно в локальном PostgreSQL, сохраняет её
в таблицах pg_profile и формирует один JSON-пакет на каждый завершённый снапшот.
DABOX должен принять пакет push-запросом и вызвать импорт в агрегирующей БД.

На этом этапе реализованы:

- локальный `take_sample()` и быстрый `take_subsample()`;
- история статистики и автоматическая локальная очистка;
- история активностей и деревьев блокировок;
- HTML-отчёт на русском языке;
- JSON-экспорт одного снапшота;
- идемпотентный импорт на агрегаторе;
- проверка последовательности снапшотов;
- миграция оригинального pg_profile 4.14 на форк 4.15.

За границами текущего этапа остаются:

- HTTP-клиент, который отправляет JSON с хоста;
- endpoint, аутентификация, inbox и quarantine сервиса DABOX;
- периодическая очистка импортированных данных на агрегаторе;
- фоновое формирование и хранение готового HTML в отдельной таблице;
- эксплуатационные метрики доставки и алерты;
- проверка на версиях PostgreSQL, отличных от PostgreSQL 16.

Репозиторий готов для установки коллегой и начала реального интеграционного
теста с DABOX, но ещё не является законченным промышленным контуром доставки.

## 2. Архитектура

```text
PostgreSQL-кластер
    |
    | scheduler: take_sample / take_subsample
    v
локальные таблицы pg_profile
    |
    | export_sample_dabox()
    v
JSON -> HTTP push -> DABOX -> import_sample_dabox()
                                  |
                                  v
                         агрегирующая БД
                                  |
                                  | get_report()
                                  v
                            HTML-отчёт
```

Между источником и агрегатором нет SQL-подключения, DB-link или обратного
сетевого соединения. Единственный переносимый объект — JSON.

## 3. Основные изменения в коде

### Локальный сбор без dblink

- `control.tpl` — из `requires` удалён `dblink`, остался `plpgsql`.
- `sample/init_sample.sql` — параметры, версия, расширения и
  `system_identifier` читаются локально.
- `sample/take_sample.0.sql` — удалён connect/disconnect и удалённые ветви.
- `sample/take_subsample.0.sql` — активности и ожидания читаются локально.
- `sample/collect_database_stats.sql` и `sample/query_pg_stat_*.sql` — обращения
  выполняются к локальным системным представлениям.
- `sample/sample_pg_stat_statements.sql` — локальный сбор
  `pg_stat_statements`, без сбора `pg_stat_kcache`.

Вызов снапшота для любого сервера, кроме записи `local`, отклоняется. Старая
таблица `servers` и API управления серверами оставлены для совместимости формата
данных и работы агрегатора.

### Дополнительные расширения

Из сборки удалены `sample/collect_obj_stats.sql` и
`sample/pg_wait_sampling.sql`. Новые данные `pg_stat_kcache` и
`pg_wait_sampling` не собираются. Их исторические таблицы и отчётные функции
оставлены, чтобы старые или импортированные снапшоты не ломали отчёт. Видимость
разделов определяется наличием данных.

Сбор статистики объектов разных БД отключён параметром `collect_objects=false`.
Это осознанное ограничение текущего локального этапа.

### Деревья блокировок

- `sample/collect_lock_tree.sql` строит связи через `pg_blocking_pids(pid)`.
- `pg_locks` используется для описания типа, режима и объекта блокировки.
- `last_lock_tree` накапливает быстрые наблюдения между обычными снапшотами.
- `sample_lock_tree` хранит перенесённую историю, привязанную к снапшоту.
- отчёт формирует раскрываемое дерево с PID, пользователем, приложением,
  временем и текстом SQL.

PID следует читать вместе с `backend_start`, `query_start`, пользователем и
приложением: после завершения сеанса PostgreSQL может переиспользовать PID.

### JSON/DABOX

- `management/dabox.sql` содержит `export_sample_dabox()` и
  `import_sample_dabox()`.
- `management/export.sql` импортирует `sample_lock_tree` и исключает служебный
  журнал DABOX.
- `schema/import.sql` создаёт `dabox_import_log`.
- `migration/schema.sql` создаёт новые таблицы при обновлении с 4.14.

Полное описание JSON находится в [dabox-json-contract.md](dabox-json-contract.md).

## 4. Требования

Проверенный стенд: PostgreSQL 16 и `pg_stat_statements`, загруженный через
`shared_preload_libraries`. Минимальная зависимость самого pg_profile — `plpgsql`.

```conf
shared_preload_libraries = 'pg_stat_statements'
track_activities = on
track_counts = on
track_io_timing = on
track_wal_io_timing = on
```

После изменения `shared_preload_libraries` PostgreSQL необходимо перезапустить.

## 5. Сборка и установка

Нужны PostgreSQL server development packages и `pg_config` нужной версии.

```bash
git clone https://github.com/ArsenySmirnov/pg_profile_new.git
cd pg_profile_new
make USE_PGXS=1
sudo make USE_PGXS=1 install
```

Переносимый архив:

```bash
make USE_PGXS=1 tarpkg
```

В целевой БД:

```sql
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION pg_profile;
```

Проверка зависимостей:

```sql
SELECT e.extname
FROM pg_depend d
JOIN pg_extension p ON p.oid = d.objid
JOIN pg_extension e ON e.oid = d.refobjid
WHERE p.extname = 'pg_profile' AND d.deptype = 'n';
```

Ожидаемый результат — только `plpgsql`.

## 6. Обновление оригинальной версии 4.14

После установки новых файлов:

```sql
ALTER EXTENSION pg_profile UPDATE TO '4.15';
```

После успешного обновления старый `dblink` можно удалить, если он не используется
другими объектами базы:

```sql
DROP EXTENSION dblink;
```

Перед обновлением промышленной базы обязательны резервная копия и репетиция на
копии. Автоматическая миграция проверена с оригинальной версии 4.14.

## 7. Планировщик снапшотов

```bash
psql -X -v ON_ERROR_STOP=1 -d profile_db -c "SELECT take_sample();"
```

Рекомендуемая начальная схема:

- `take_sample()` каждые 10–15 минут;
- `take_subsample('local')` каждую минуту, если нужна подробная история
  активностей и блокировок;
- экспорт JSON сразу после успешного `take_sample()`.

Интервалы нужно подтвердить нагрузочным тестом: частые подснапшоты увеличивают
детализацию и объём хранилища.

```sql
SELECT * FROM show_samples('local', 20);
```

## 8. Формирование и отправка JSON

```sql
SELECT export_sample_dabox('local');
SELECT export_sample_dabox('local', 42, false);
```

Третий аргумент включает обфускацию SQL-текстов. При `true` агрегатор не сможет
показать исходные тексты запросов.

До появления HTTP-клиента:

```bash
psql -X -A -t -v ON_ERROR_STOP=1 -d profile_db \
  -c "SELECT export_sample_dabox('local', 42, false);" \
  > pg_profile_42.json
```

Для HTTP рекомендуется `Content-Type: application/json`, TLS и gzip. Источник
повторяет пакет с тем же `event_id`, пока DABOX не вернёт подтверждение.

## 9. Импорт на агрегаторе

DABOX должен передавать JSON параметром подготовленного SQL-вызова:

```sql
SELECT import_sample_dabox($1::jsonb);
```

Создаётся отключённый сервер вида `dabox_<cluster_id>_local`:

```sql
SELECT server_id, server_name, enabled, last_sample_id
FROM servers
ORDER BY server_id;
```

Повтор принятого события возвращает `0`. После первого пакета номера идут строго
последовательно. Пропуск отклоняется и не меняет данные.

```sql
SELECT * FROM dabox_import_log ORDER BY cluster_id, sample_id;
```

`allow_gap=true` предназначен только для аварийного административного решения.
Отчёт нельзя построить через отсутствующий промежуточный снапшот.

## 10. Формирование HTML

После импорта двух последовательных снапшотов:

```sql
SELECT get_report('dabox_04854310_local', 1, 2);
```

```bash
psql -X -A -t -v ON_ERROR_STOP=1 -d profile_aggregator \
  -c "SELECT get_report('dabox_04854310_local', 1, 2);" \
  > report.html
```

Автоматическое сохранение готовых отчётов в отдельной таблице агрегатора остаётся
следующим этапом.

## 11. Очистка данных

Локально снапшоты старше семи дней по умолчанию удаляются во время следующего
успешного `take_sample()`.

```sql
SELECT set_server_max_sample_age('local', 7);
```

Baseline временно защищает включённые снапшоты от обычной очистки.

Импортированные серверы агрегатора имеют `enabled=false`, поэтому их штатная
очистка автоматически не запускается. Перед промышленной эксплуатацией нужен
отдельный регламент housekeeping агрегатора.

## 12. Сброс статистики

`pg_stat_reset()` проект не вызывает. Глобальный сброс повлиял бы на другие
системы мониторинга; pg_profile рассчитывает дельты счётчиков.

`pg_stat_statements_reset()` по умолчанию вызывается после успешного чтения
`pg_stat_statements`. Это предотвращает вытеснение запросов при заполнении
`pg_stat_statements.max`, но влияет на другие средства мониторинга.

Отключение полного сброса:

```sql
ALTER DATABASE profile_db SET pg_profile.statements_reset = 'false';
```

После переподключения в современных версиях `pg_stat_statements` сбрасываются
только min/max-поля, а основные счётчики остаются накопительными.

## 13. Проведённые проверки

- чистая установка без `dblink`;
- два локальных снапшота и HTML;
- оригинальная 4.14 → форк 4.15 → удаление `dblink` → новый снапшот;
- отсутствие `dblink` в установочном и миграционном SQL;
- перенос двух JSON между отдельными БД;
- идемпотентная повторная доставка;
- отклонение последовательности `1, 2, 4`;
- аварийное принятие пропуска с `gap_accepted=true`;
- перенос дерева блокировок;
- присутствие текста блокирующего SQL в HTML агрегатора.

## 14. Что нужно получить от команды DABOX

1. URL и HTTP-метод endpoint.
2. Аутентификацию и ротацию секрета/сертификата.
3. Максимальный размер тела и поддержку gzip.
4. Таймауты и правила повторной отправки.
5. Коды ACK, duplicate, gap, validation error и temporary error.
6. Срок хранения сырого JSON в inbox/quarantine.
7. Правило доставки пропущенного номера.
8. Согласованный префикс имени кластера на агрегаторе.
