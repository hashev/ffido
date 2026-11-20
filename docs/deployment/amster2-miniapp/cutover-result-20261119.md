# Рабочий backend amster2 переключён на Telegram-совместимую пару

Переключение выполнено 19.11.2026. Окно 13:30:58–13:41:20 MSK, около10 минут22 секунд:
новый остановленный backup, проверка его восстановления, закрытая миграция и возврат служб.

## Фактическая конфигурация

| Служба | Image ID | Состояние |
| --- | --- | --- |
| ffido | sha256:4339f8b44b076d8dcbea0cfde2532c0607dd8bd61fb561ec85380b1b713c4b9a | healthy |
| ffido-tosser | sha256:0e9232a9b70026003920559293cdf7bff91c2dfcdd0f3d87effdd21c1408fcfb | healthy |

Оба /opt/ffido имеют одинаковый BUILD.json: tag `safe-mailbox-restore-candidate-20261118`,
sha `3926989e518efb9607df739f7f3c1288c7a0b31e`, build_number2026111804.
Пара — проверенные локальные образы; она не выдаётся за подписанный официальный релиз.

В каноническом `/home/yurik/fido/ffido/updates/image-override.json` закреплены обе службы,
pull_policy=never. Up выполнен с `--no-deps --no-build --pull never --force-recreate`;
ничего не пересобиралось и не скачивалось. `.env` FFIDO_IMAGE соответствует backend ID.
`deployed-identity.json` получен из настоящего BUILD.json; `update-transaction.json`
complete с явной manual-pinned ролью. BinkD и jamnntpd возвращены на исходных образах.
Первый цикл нового worker завершился с exit0, native TLS readiness успешна.

Настроен `auth.telegram`: bot_id9052986615, test_environment=false,
max_age_seconds300, clock_skew_seconds30. Временный private bind127.0.0.1 внутри
контейнера использовался только для проверки; итоговый server.ip снова0.0.0.0.
Native endpoint8080 и его TLS CA/SAN не менялись.

## Пауза автообновлений

- Из исходного crontab закомментирована только строка `manage.sh update`.
  Poll, native renew и rotation восстановлены; root cron gateway не изменялся.
- `ffido/updates/manual-deployment.json`: automatic_apply_paused=true, причина,
  точные candidate/rollback/previous IDs и ссылка на свежий backup/manifest.
- В ops/manage.py перед любым update/check-and-apply/rebuild-worker добавлена
  fail-closed проверка этого marker; воспроизводимый diff —
  [manage-update-pause.patch](manage-update-pause.patch).
- Реальный вызов `manage.sh update` после освобождения maintenance lock вернул
  `Manual pinned deployment: automatic apply paused`, без смены образов и запуска
  updater apply. Это дополнение к отключённому расписанию, не фиктивный JAM marker.

Возвращать автоматическое apply только отдельной операцией после выбора совместимого
официального релиза с поддержкой schema12 и проверки coherent worker. Не обходить
pause прямым updater apply/build. Обычный native renew может штатно перезапустить
backend по необходимости, используя существующий закреплённый контейнер.

## Свежий rollback-комплект

`/srv/ffido-main-cutover-20261119`, mode0700. Предыдущие backup и образы сохранены.

- `snapshot/snapshot.json`, `snapshot/snapshot.tar.gz`: schema11, **3407 файлов,
  599 JAM и два mailbox**. В отличие от предыдущего снимка NNTP и корневые служебные
  файлы включены прямо в основной manifest. Включены очереди, state/session key,
  HPT/dependencies, TLS/ACME, deployment/ops/updater/identity и активные corrections.
- `deployment-extra.tar.gz`: рабочий gateway/ACME и системные cron/firewall config;
  архивирование под maintenance lock, без запуска gateway и изменения firewall.
- `host-tools.tar.gz`: отдельно сохранены maintenance venv и старый native probe,
  необходимые для полного восстановления обслуживающих команд. Они проверены в
  восстановленной копии; interpreter symlinks допускаются только для известных
  host Python путей. Runtime данные и primary snapshot не ослабляли symlink policy.
- Исходный crontab до паузы и целевой crontab с отключённым update сохранены отдельно;
  не устанавливать в рабочую систему временный crontab из середины окна.
- Приватные report.json/restore-report.json и operational logs; безопасные сводки
  дополнительно сохранены локально в build/amster2-cutover-20261119.

| Артефакт | SHA-256 |
| --- | --- |
| snapshot.json | 294b0706a3f5dbcae83ab671ef22451fe85b14cc9658ecbf0df66134151ea629 |
| snapshot.tar.gz | 41e7c8045a76b4172d9b411a0632c9df742b3e7bd4952d08049873ed80850c4a |
| deployment-extra.tar.gz | fa366a07b21d1672dc5f84dd2c9a631596262e0ca525a198821d95b6e867d5b0 |
| host-tools.tar.gz | c92c6176503f2ce1341f7887af79102237088954af78fd6c9714523bb9059001 |

Backup получен при остановленных писателях и checkpointed SQLite; проверены integrity,
FK, отсутствие writable host FD от root и полные хеши/архив. Backup helper работал
в отдельном PID namespace с1000:1000; настоящий maintenance lock удерживал supervisor,
для helper использован отдельный cutover.snapshot.lock. jamnntpd остановлен по SIGINT,
остальные — штатным stop без принудительного SIGKILL.

Свежий архив до изменения production распакован в restore-probe с владельцами и modes.
Подготовленный rollback backend `sha256:af7f0c334d8d96ac6d03dd13db3d48d87ba9e58c575653fd5b10a3e8ca5f4c3c`
успешно выполнил check/apply/repeat и native TLS readiness на schema11.
Все прежние логические строки и non-database файлы сохранены. QA контейнер остановлен,
network=none, без port bindings и production mounts. Экспорт/отправка в QA не запускались.
Проверочная копия и свидетельства сохранены; source snapshots не изменены.

## Проверка миграции и входа

1. После свежего restore gate установлены pins и Telegram config; новый backend
   поднят с listener только127.0.0.1 внутри контейнера. Внешние native клиенты в этот
   момент не могли создавать новые записи, fido/NNTP/tosser оставались остановлены.
2. Проверены schema11→12, integrity/FK и точное сохранение **166110 исходных строк
   22 таблиц**, выбирая прежние столбцы из новой схемы и сравнивая multisets хешей.
   Изменения на source inode не требовали mailbox-restore над рабочими данными.
3. Native TLS RPC через network namespace этого же контейнера:
   GetServerCapabilities.supports_telegram=true; пустой/неподписанный Telegram proof
   отвергнут UNAUTHENTICATED. HPT-вход существующего `2:5015/120.1`, ListConferences
   с одним своим mailbox, GetTelegramBinding=false и Logout успешны. Пароли/токены
   не печатались; сообщения не читались и не отправлялись.
4. У `2:5015/120.155` существующий HPT point/mailbox, но ещё нет backend user.
   Проверка не создавала его автоматически. Этот профиль требует обычного первого
   HPT-входа пользователем; это не отсутствие FTN point.
5. Private backend штатно остановлен, SQLite checkpointed и проверена полная структура
   schema12 через read-only metadata-schema-check. Затем возвращён обычный bind,
   пересоздан backend на том же pinned образе и проверены public native TLS/RPC.
6. Запущен подготовленный tosser, проверены его образ/health и новый cycle exit0;
   затем подтверждены работа обычных служб, coherent BUILD и pause updater.

Действительный Telegram initData и постоянная привязка в этом окне не проверялись
и не создавались: production gateway ещё не запущен, основной backend не опубликован
в каталоге. Это server/native gate, не завершённая end-to-end приёмка Mini App.

## Итог и оставшиеся границы

cutover_complete=true; schema12; обе службы healthy; automatic_update_guard_verified=true.
Остальные контейнеры, включая тестовые backend/gateway, сохранили image/start times.
Политики AMSTER-INPUT/AMSTER-DOCKER/INPUT/DOCKER-USER совпали с исходными.
Рабочий gateway не создавался, :9443 остаётся свободен/закрыт, каталог и Web не публиковались.
После сохранения нового snapshot и QA-копии свободно6288850944 байта (около5,86 GiB).
Новых образов/сборок не создавалось; перед следующим большим backup место пересчитать.

До разрешения обычного native listener supervisor имел проверенную rollback-копию
и процедуру возврата полной schema11 на совместимой rollback-паре. Откат не потребовался.
После13:41 MSK рабочие записи и штатная обработка возобновлены: слепой возврат этого
snapshot теперь может потерять новые данные. При проблемах — forward fix либо
согласованное восстановление с сохранением и reconciliation новых данных/очередей.
Один старый image поверх schema12 и неподправленный прежний backend для восстановления
на новых inode не использовать.

Следующий самостоятельный этап — разрешённый запуск рабочего gateway на9443 с локальной
проверкой HTTPS/gRPC-Web/CORS; затем отдельно допуск firewall и публикация каталога.
