# Безопасное восстановление персональных ящиков

Change `safe-mailbox-restore` добавляет offline `ffido-admin mailbox-restore` и
`ffido-node-backup`. Рабочие службы, cron/ops/manage.py, firewall, gateway и каталог
узлов этим change не обновляются. Архивирование change выполняется отдельно.

## Принцип восстановления

Проверенный manifest и внешний доверенный SHA-256 фиксируют содержимое остановленного
снимка. `check` открывает существующую SQLite без CREATE/Init/migration, проверяет
схему 11/12, config/JAM/metadata и locks, затем выдаёт digest плана для конкретных
inode назначения. `apply` повторяет проверки, сохраняет приватную SQLite backup и
атомарно обновляет физические mailbox bindings и `restored_generations`.

Логическая generation остаётся прежней. Read status, reading positions, bookmarks,
history, operation_id/payload_hash, UUE/crosspost receipts и FTN source_key не
переписываются. Runtime проверяет физическое поколение перед использованием логического;
подмена блокирует доступ. При прерывании тот же явный apply проверяет transaction receipt
и различает исходное состояние и завершённый commit. После обычной работы backend
для следующего переноса необходим новый snapshot.

Исходный неподправленный v1.0.27 для полного отката не используется. Отдельный
rollback-образ основан на точном v1.0.27 и содержит restore-support без Telegram-миграции.
Schema11 остаётся 11; schema12 должна открываться новым backend. Pending/uncertain
состояния, неоднозначные поколения и устаревший план отклоняются без ремонта журналов.

## Полный sandbox snapshot

Данные из прежнего `/srv/ffido-main-rehearsal-20261118/baseline` проверяются по
2726 исходным хешам. Неполный архив от 15.11.2026 не переименовывается в завершённый
backup. Статические дополнения и материализация ACME записываются отдельным provenance;
пустые sandbox-директории flags/fileboxes явно отмечены как часть тестовой подготовки,
а не как утверждение о транспортных очередях старого рабочего узла.

Все новые данные и приватные отчёты находятся в `/srv/ffido-safe-restore-20261118`,
режим 0700. Контейнеры имеют network=none, без published ports и production mounts.

Пример подготовки после остановки писателей управляющей процедурой:

```sh
ffido-node-backup snapshot --root /sandbox/source --destination /sandbox/snapshot11 \
  --helper /opt/ffido/bin/ffido-hpt-auth \
  --map /home/fido=/sandbox/source --map /srv/fido=/sandbox/source \
  --map /var/lib/ffido=/sandbox/source/ffido/state \
  --map /etc/ffido/tls=/sandbox/source/ffido/tls \
  --include ffido/tls --include logs --include nodelist \
  --legacy-manifest /sandbox/legacy-provenance.private.json \
  --legacy-digest "$TRUSTED_LEGACY_PROVENANCE_SHA256"
```

Legacy override нужен только для уже распакованной старой копии с изменёнными inode.
Для обычного остановленного узла или нового snapshot после штатного restore он не
используется. TLS CA и нужные пустые HPT runtime-директории включены явно. SHA-256
выданного snapshot manifest хранится отдельно от распакованных данных.

```sh
ffido-admin mailbox-restore /sandbox/restored11 /sandbox/snapshot11/snapshot.json \
  "$TRUSTED_SNAPSHOT_SHA256" check
ffido-admin mailbox-restore /sandbox/restored11 /sandbox/snapshot11/snapshot.json \
  "$TRUSTED_SNAPSHOT_SHA256" apply "$PLAN_SHA256"
```

Для аварийного WAL повторяется явный apply при остановленных писателях; check требует
checkpointed DB. Ни один из инструментов не запускает backend, HPT или mailer автоматически.

## Локальная проверка

- `./build.sh build` — успешно.
- `CTEST_PARALLEL_LEVEL=4 FFIDO_TEST_HPT="$PWD/build/publication-deps/prefix/bin/hpt" python3 scripts/release/check_ctest.py build/backend` — 564/564, без скрытых skips.
- `python3 scripts/check_cpp.py --build-dir build/backend` — format и clang-tidy: 129 файлов, 65 translation units.
- `./build.sh asan-ubsan` и `./build.sh tsan` с подготовленными соответствующими dependency prefixes и pinned HPT — по 564/564 до завершающей проверки структуры; на окончательном коде повторены все 6 затронутых групп, включая 18 CLI/snapshot cases, в обеих sanitizer-сборках.
- Backup unittest: 8; CLI/snapshot regressions: 18, включая границы commit/WAL/fsync, legacy provenance, ACME containment, изменение файла во время копирования, устаревшие inode и чужие назначения.
- Отдельные runtime-регрессии: recovery с логическим поколением, повтор frozen crosspost и multipart UUE после смены inode, FTN source_key без новой доставки, отказ после изменения incarnation header.

Codegraph сообщил об отсутствии индекса для этого репозитория; индекс не создавался.
LLDB MCP не подключён; CLI LLDB использован на изолированном процессе для диагностики
SQLite NOFOLLOW/системного `/var` на macOS. Исторические проверки прежнего отчёта не
подменяют перечисленные результаты.

## Результаты репетиции

Окончательная репетиция завершена 18.11.2026 в 15:08 UTC на образах из таблицы ниже.

- Два полных sandbox snapshot: schema11 и schema12, по 2044 файла; inventory — 596 JAM и два персональных ящика.
- Schema11 восстановлена через штатные check/apply/repeat и открыта rollback-парой без повышения версии. Схема 12 восстановлена новым комплектом; отдельно проверена миграция 11→12.
- Все 152700 исходных строк 22 прежних таблиц сохранены; физические mailbox fields изменены только штатной командой. Тестовые native logins добавляли независимые сессии, сохраняя прежние строки. Прочитанность, позиции, история, bookmarks, направление, receipt и JAM/spool/config/session key сохранены.
- Два профиля вошли через HPT по TLS внутри контейнеров. Архивные MCP/RPC вернули прежние message IDs и одинаковые данные до/после миграции и восстановления. Точные ID проверяются без сравнения подстрок; чужие ящики вернули gRPC PERMISSION_DENIED (MCP GRPC_7). Чтение не изменяло read state/history/positions.
- Неверный внешний digest, устаревший plan, занятый lock, повреждение JAM, смена inode, symlink/hardlink и чужое назначение отвергнуты без изменения SQLite. На окончательном коде дополнительно проверен отказ неполным схемам 11/12; новые snapshot inventory используют тот же schema checker.
- Все контейнеры репетиции остановлены; network=none, без published ports и production mounts. HPT export/worker cycle не запускались, сообщений не отправлено. Image IDs, start times рабочих backend/tosser/fido/jamnntpd и тестовых backend/gateway, а также хеши рабочих конфигураций совпали с исходными.

Manifest SHA-256 schema11:
4d6bb765458d422c808e54444b10eae278bf9dddd52589e5f5a3ec3492233501;
schema12:
96e2213f228f6fd32ee757aeab628132105b53503221f3f5265f7a80e42148d8.
Приватный подробный отчёт — rehearsal-report.json; предыдущие попытки и их диагностика
сохранены отдельно. Никаких ручных SQL-исправлений generation/files не применялось:
перед повторами временная SQLite целиком бралась из доверенного snapshot, затем
применялся штатный restore.

restore_mechanism_verified=true. production_rollback_ready=false и
cutover_backup_ready=false: снимки исторические, перед рабочим переходом требуется
свежий остановленный backup и отдельное разрешение на обновление.

До отдельного разрешённого рабочего обновления нужны свежий остановленный cutover backup,
проверка его полного состава и доставка/фиксация точных образов. Исторический sandbox
не является свежим rollback-снимком рабочего узла.

### Условия административного контейнера

Snapshot helper запускается в контейнере с копией source под `/sandbox/source` и
read-only aliases той же копии под `/home/fido`, `/srv/fido`, `/var/lib/ffido`
(state) и `/etc/ffido/tls` (TLS). `--map` перенаправляет includes и инвентаризацию;
проверки ресурсов libfidoconfig при parsing требуют существования исходных runtime-путей.
Каждый alias указывает только на sandbox, без live mounts.

`ffido-admin metadata-schema-check DB` — общий read-only контракт обязательных таблиц и столбцов 11/12 для backup и restore. Регрессии отклоняют потерянную bookmarks, переименованный столбец history и подмену таблицы представлением; неполная схема не получает завершённый snapshot.

Offline `check/apply` закрепляет FD всех проверенных файлов. Default Docker soft limit
1024 недостаточен для снимка из 2044 файлов: проверка отклоняется без изменения БД.
Для административных контейнеров используется `--ulimit nofile=8192:8192` (минимум
число файлов manifest + 32). Рабочие службы и их лимиты не менялись. Перед снимком
legacy-копии проверен checkpoint SQLite; исходный SHA-256 основного файла схемы 11
сохранён, служебный SQLite index не принимается за пользовательские данные.

## Зафиксированные окончательные образы

| Роль | Локальный tag на amster2 | Image ID |
| --- | --- | --- |
| Backend | ffido-safe-restore:candidate-schema-20261118 | sha256:4339f8b44b076d8dcbea0cfde2532c0607dd8bd61fb561ec85380b1b713c4b9a |
| Tosser | ffido-safe-restore-tosser:candidate-schema-20261118 | sha256:0e9232a9b70026003920559293cdf7bff91c2dfcdd0f3d87effdd21c1408fcfb |
| Rollback backend | ffido-safe-restore:rollback-schema-20261118 | sha256:af7f0c334d8d96ac6d03dd13db3d48d87ba9e58c575653fd5b10a3e8ca5f4c3c |
| Rollback tosser | ffido-safe-restore-tosser:rollback-schema-20261118 | sha256:08f304b80542f1818257493cf560fa4afc3318ed90f8e65c16ef63230197d7e7 |

Идентификация идёт по полному локальному ID; это не опубликованные registry digests.
Оба комплекта unsigned, stable=false, version 1.0.27. Candidate tag
`safe-mailbox-restore-candidate-20261118`, build_number 2026111804, базовый HEAD
3926989e518efb9607df739f7f3c1288c7a0b31e; rollback tag
`safe-mailbox-restore-rollback-v1.0.27-20261118`, build_number 2026111805,
базовый v1.0.27 bdf245216c43089d011c6778f2e0465e16fa9082. Rollback сохраняет
state_schema_max=11, candidate — 12. Для полного отката нужны обе роли соответствующей пары.

Рабочее дерево dirty, поэтому HEAD не заменяет source manifest. Candidate: 296 файлов,
SHA-256 manifest 9f400666f874f32d687caac4e04e49f5dd8d7e24661a7b32d16760784e514fd2;
rollback: 289 файлов, SHA-256 manifest
05afc47ab233f41bb78b737d167ec64087794a8827c256ce19d4614ef3acedd8.
Окончательная сборка использовала проверенные builder/runtime bases, перенесла все
изменённые исходники из новых полных контекстов, повторила CMake build и полный
release gate. Native dependencies/toolchain не менялись. Docker marker и container
config example сохранены. В каждой паре весь `/opt/ffido` совпал: 174 файла candidate,
173 rollback; dynamic libraries разрешены.

HPT/runtime обоих worker получены из неизменённого рабочего worker
sha256:bb4d3b5e7046b65cc3a39cf394ec8f2b96d886e0c2fc89b9c853ccfcf83fccce.
HPT SHA-256 bb959f3b5cf5fe406fc1271628632a35d8e60ea5891610432825ee7bf11a006a и
FFIDO_HPT_KOI8_CP866=1 сохранены. Compose labels очищены. Worker cycle не запускался.

Приватные архивы и отчёты — `/srv/ffido-safe-restore-20261118`:

- candidate-image.tar.gz — SHA-256 1cbc4b2770e1249c115aebf19bed9b57e58a76d6e4c7c84d4ae9e545fd4b42f8;
- rollback-image.tar.gz — SHA-256 e88b53ac34935fd7de97f669844d77eeccaa3c299dd0165ddc033ce641f2a864;
- worker-images.tar.gz (обе роли) — SHA-256 11b1574b7b4cdaf81fbb2ffb1f8444dfd1f14f411c0f3e97f624ff901a8e89d5;
- candidate/rollback-source-manifest.json, image-validation.json, images.json;
- preparation.private.json, legacy-provenance.private.json, scripts и private logs.

Полный Linux release gate: candidate 564/564, rollback 548/548, без скрытых HPT skips.

## Завершение и место на диске

После окончательной проверки содержимое обоих gzip-архивов ещё раз сверено с manifest.
Сохранены полные snapshot11/snapshot12 (распакованные данные, manifests и архивы),
все образы, исходные frozen contexts, private logs и отчёты. Удалены только временные
производные `restored11`/`restored12`, созданные этой репетицией; исходный baseline и
рабочие данные не затронуты. Освобождено 4881444864 байта, свободно 8844525568 байт
(около 8,2 GiB). Проверка — scratch-cleanup.json.

Архив SHA-256 snapshot11:
432f9e48efea5e72b8e7a7768935eb50757acf6fad5fd6a775b169751ecc6c53;
snapshot12:
93d8d1876ec703ea70d39796bd1e5023e306da33e91739767e8792770bd2c577.
Stopped QA-контейнеры сохранены для просмотра inspect/logs; для повторного запуска
нужно заново распаковать снимок в закрытый root и выполнить check/apply для его inode.

Change выполнен: 12/12 задач. Коммиты, публикация, production deploy и archive change
не выполнялись; архивирование остаётся отдельным OpenSpec действием.

Полные frozen source contexts сохранены также на сервере (код, без данных узла):
candidate-source.tar.gz — SHA-256
5aac4910c85bd378ad75242f70d62f5bac7d40fe692d4877c032f04587c745b1;
rollback-source.tar.gz — SHA-256
8f43152c7cfa301fb07e12289ea5be12e6c56d533939a2ff34416790c3d89e97.
Архивы включают соответствующий source manifest; source-archives.json проверен после передачи.
