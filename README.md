# pg_profile_new

Корпоративный форк [pg_profile](https://github.com/zubkov-andrei/pg_profile)
для локального сбора статистики PostgreSQL и её передачи через JSON-интерфейс
DABOX в агрегирующую БД.

## Что изменено в форке

- итоговый HTML-отчёт переведён на русский язык;
- сбор выполняется только на локальном PostgreSQL-кластере;
- зависимость и исполняемые обращения к `dblink` удалены;
- сбор через `pg_stat_kcache` и `pg_wait_sampling` отключён;
- блокировки собираются деревом: связи определяются через
  `pg_blocking_pids()`, описание блоков берётся из `pg_locks`;
- добавлен экспорт одного снапшота в JSON для DABOX;
- добавлен идемпотентный импорт JSON на агрегаторе с контролем пропусков;
- поддержано обновление оригинального pg_profile 4.14 до версии форка 4.15.

## Быстрый старт

```bash
make USE_PGXS=1
sudo make USE_PGXS=1 install
```

```sql
CREATE EXTENSION pg_stat_statements;
CREATE EXTENSION pg_profile;

SELECT take_sample();
SELECT export_sample_dabox('local');
```

`dblink`, `pg_stat_kcache` и `pg_wait_sampling` устанавливать не требуется.

Приём JSON в агрегирующей БД:

```sql
SELECT import_sample_dabox($1::jsonb);
```

## Документация

- [Руководство по передаче и тестированию](docs/handoff-ru.md)
- [JSON-контракт DABOX](docs/dabox-json-contract.md)
- [Оригинальная документация pg_profile](doc/pg_profile.md) — описывает upstream
  и в части удалённых возможностей к этому форку неприменима.

## Статус

До интеграционного теста с DABOX готовы локальный сбор, хранение снапшотов,
деревья блокировок, JSON-экспорт, агрегаторный импорт, обнаружение дубликатов и
пропусков, а также формирование HTML на агрегаторе.

HTTP-клиент источника и HTTP endpoint DABOX в этот репозиторий не входят: для них
нужны адрес сервиса, схема авторизации и правила внутреннего API.
