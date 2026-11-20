# Свежий backup FFIDO на amster2 и восстановление

Выполнено 19.11.2026 по отдельному разрешению: остановка исходных рабочих контейнеров,
полный остановленный снимок FFIDO, запуск тех же контейнеров и изолированное восстановление.
Это backup узла FFIDO и связанных конфигураций развёртывания/gateway, не образ всей VM
со сторонними VPN/MQTT и не снимок данных отдельного тестового backend.

## Состав и расположение

Завершённый комплект: `/srv/ffido-main-backup-20261119-retry`, directory0700.

- `snapshot/snapshot.json` и `snapshot/snapshot.tar.gz`: **3375 файлов, 599 JAM,
  два персональных ящика, schema11**. Включены JLR, весь state/session key,
  HPT/includes/intab/outtab, f/spool/dupebase/flags/fileboxes, Compose/.env/binkd.cfg/t.sh,
  config/TLS/ACME, ops/updater/updates, deployed identity/transaction, исправления
  кодировок и активные локальные deployment-каталоги, owner credentials, logs/nodelist/MCP.
- `node-service-extra.tar.gz` и его private manifest: NNTP-конфигурация/таблицы/скрипты
  и все обычные корневые файлы узла, 40 файлов. Сняты при остановленных писателях;
  хеши файлов проверены до/после архивирования и при восстановлении.
- `deployment-extra.tar.gz`: отдельный `/srv/ffido-miniapp-main`, системные cron,
  persistent firewall и Docker daemon config при наличии. Включает отдельные ACME
  account/lineage/key, public pair, Envoy config, pinned image и renewal script.
- Отдельно сохранены исходный yurik crontab, root crontab/его отсутствие,
  iptables-save и приватные operational logs. Для восстановления заданий yurik
  использовать `crontab.yurik.before.private.txt`, а не временно приостановленную копию.
- `report.json`, `restore-report.json`, `deployment-restore.json`: результаты и provenance.

Доверенные SHA-256 сохранены также вне сервера в локальном `build/amster2-backup-20261119`
и здесь; приватные архивы/ключи/содержимое почты в репозиторий не переносились.

| Артефакт | SHA-256 |
| --- | --- |
| snapshot.json | 682cd672bedb9e7cfc0a72a96597cf99eb904f910f7954e1c67c99af0337452d |
| snapshot.tar.gz | f43ea66b8e02bc047f7d44094e751e6ca56a62bb6e33ef6a59c6243bd87e9343 |
| node-service-extra.tar.gz | d2d8c9a3159de2b92a357f1552b95f67945ef26c65d446b88df4e07bcc1764ea |
| deployment-extra.tar.gz, окончательный | 8d898020dceda94f2c8baba2f89f514d59ab4df375e3ca757179fff281463349 |

Первоначальный deployment-extra сохранён как `deployment-extra.initial.tar.gz`
(SHA eaaadf4df74e0e563a78cfd5fe4e190d9ebb8020f510205b5e94dd1fb7a8c2a1)
для диагностики ошибки прав, описанной ниже. Для восстановления брать окончательный архив.
Существующие backup, образы и прежние доверенные snapshots не удалялись.

## Окна остановки и возврат служб

Управляющий процесс удерживал настоящий maintenance.lock, временно приостановил
ровно четыре managed задания yurik cron, сохранял исходный crontab и возвращал
службы через finally. Root cron gateway не менялся. `manage.sh backup` не использовался.

Первый проход, 12:57:34–12:58:48 MSK (74 секунды), прерван до создания снимка:
непривилегированный host `/proc` scan не смог прочитать FD недампируемого процесса.
Все службы и исходный cron успешно возвращены; это не завершённый backup.
Отчёт сохранён отдельно в `/srv/ffido-main-backup-20261119`.

Повторное окно: **12:59:41–13:05:43 MSK, около 6 минут** от начала остановки
писателей до возврата служб. Завершение каждого процесса подтверждалось, SIGKILL
не применялся. Установлено по `/proc/1/status`: jamnntpd обрабатывает **SIGINT**, а
SIGTERM оставляет PID1 работающим. Для него использован SIGINT; это надо сохранять
в будущей процедуре остановки без принудительного kill.

SQLite под DB/HPT locks прошла checkpoint(TRUNCATE), integrity_check и foreign_key_check;
ненулевых WAL/SHM/journal не осталось. Sidecars вручную не удалялись.
Проверка writable host FD выполнена отдельно от root для всех UID. Backup helper
работал от1000 в изолированном PID namespace: непривилегированное чтение host /proc
здесь не используется вместо привилегированной проверки supervisor.
Настоящий maintenance.lock оставался у supervisor; helper использовал отдельный
`ffido/cutover.snapshot.lock`, вошедший в manifest. Snapshot без legacy override.

После встроенной полной проверки файлов, архива и gzip целостности запущены
исходные ffido/fido/jamnntpd/ffido-tosser. Образы не заменялись и не пересобирались.
Backend и tosser healthy, native TLS readiness успешна, первый штатный cycle после
возврата завершился с exit0. Рабочая schema осталась11, main config/Compose/.env/HPT,
image override и deployed identity сохранили хеши. Оригинальный crontab восстановлен
байт-в-байт. Тестовые backend/gateway и остальные службы сохранили image/start times.
Политики AMSTER-INPUT/AMSTER-DOCKER/INPUT/DOCKER-USER не изменились.

## Изолированное восстановление

`restore-probe` распакован в новые inode из доверенного архива. При безопасной
распаковке сначала проверялись пути и типы tar members, затем восстанавливались
владельцы, группы и modes из manifest/заголовков: один tar data filter не сохраняет
всю эту metadata. Дополнительный NNTP/root архив восстановлен и проверен по хешам.

Использован точный rollback backend с restore-support:
`sha256:af7f0c334d8d96ac6d03dd13db3d48d87ba9e58c575653fd5b10a3e8ca5f4c3c`.
Не исходный неподправленный backend и не Telegram-кандидат для миграции.

- `mailbox-restore check` не изменил SQLite; apply применил выданный plan.
- Повторный apply вернул already_applied без изменения SQLite SHA.
- Логические данные **22 прежних таблиц, 166056 строк** сохранены; сравнение —
  multisets хешей строк, без вывода их содержимого. У mailbox_bindings отдельно
  подтверждено сохранение address/base и изменение только generation/files.
- Для всех599 JAM подтверждено совпадение прежней logical_generation с manifest;
  новые физические inode учитываются штатной таблицей restored_generations.
- Проверочный backend успешно прошёл native TLS readiness и остановлен с exit0.
  После него schema11, исходные логические строки и все non-database файлы сохранены.
- Контейнер `ffido-main-fresh-restore-qa-20261119`: network=none, без port bindings;
  все data/config/TLS mounts указывали только на `restore-probe`, не на рабочий узел.
  HPT export, worker cycle и отправка сообщений в копии не запускались; содержимое
  личных сообщений не выводилось и API-чтение писем не выполнялось.

Проверочная копия и остановленный QA-контейнер сохранены для диагностики. Их обычная
работа не возобновлялась. Прочие raw snapshots/архивы остаются неизменными.

## Проверка отдельного gateway/ACME и найденное исправление

Архив gateway восстановлен в отдельную private директорию без установки файлов в
live пути. Проверены contained ACME links, совпадение public pair с lineage,
ключ/сертификат и доверенная цепочка.

Проверка под реальным UID10001 обнаружила дефект `renew_gateway.py`: mkdir(0750)
под umask077 создавал public directory0700. Исходный HTTPS validate проверял stage
с явным chmod0750 и поэтому эту ошибку размещения не выявил.

Исправлено: `install_pair` явно устанавливает directory0750. На сервер доставлен
исправленный скрипт, у существующего public directory выставлен0750 (root:10001).
Ключ/сертификат и их содержимое не менялись. Gateway не создавался и не запускался.
Добавлен regression test с umask077: **9/9** тестов прошли с ResourceWarning=error.

Отдельный deployment архив обновлён под maintenance lock без остановки служб;
первоначальный сохранён для аудита. Восстановлены его owners/groups/modes и
проверен именно конечный runtime public directory через Envoy `--mode validate`
под UID10001, network=none, только с mounts из восстановленных копий. Listener и
служба не запускались. Результат — успешно.

## Итог и границы

fresh_backup_verified=true; isolated_restore_verified=true. После проверки свободно
15148797952 байта (около14,1 GiB), место перед следующим окном пересчитать.
Никакого обновления рабочих backend/tosser, запуска рабочего gateway, изменения
допусков firewall или публикации каталога/Web-клиента не было.

Snapshot фиксирует состояние окна 12:59–13:05 MSK. После запуска рабочих служб
обычная обработка почты возобновилась; для последующего рабочего переключения нужен
актуальный остановленный snapshot того окна, а не слепой возврат этой более ранней
копии поверх поступивших данных. Восстановление на новых inode — только через
штатный mailbox-restore и совместимый rollback/backend, без ручных SQL-исправлений.
