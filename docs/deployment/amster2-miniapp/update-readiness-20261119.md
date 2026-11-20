# Готовность к возобновлению автообновлений amster2

Проверка 19.11.2026 только на чтение. **Возобновлять пока нельзя.**
Штатный канал не содержит принятой Telegram/schema12 реализации, а текущая
процедура обновления требует адаптации к ручной паре образов и полному backup.

## Что проверено сейчас

- ffido и ffido-tosser работают, healthy, на закреплённых image ID из
  [результата переключения](cutover-result-20261119.md). Рабочий gateway running.
- SQLite schema12: integrity_check=ok, foreign_key_check без ошибок.
  Сохранены два mailbox_bindings для 2:5015/120.1 и .155; имеется одна
  Telegram-привязка и шесть активных Telegram-сеансов. Идентификатор Telegram,
  токены и HPT-пароли не выводились.
- auth.telegram содержит bot_id9052986615, обычное окружение, max_age300/skew30.
  Config и state находятся на постоянных host mounts; TLS upstream остаётся :8080.
- Шлюз имеет отдельный Compose и pinned Envoy, read-only mounts и restart
  unless-stopped. Сертификат действует до 17.02.2027 08:50:23 UTC. Отдельный root
  cron продления активен; renew_gateway.py использует maintenance.lock и проверку
  прежнего состояния running перед перезапуском gateway.
- Внешний запрос GetServerCapabilities через en0 к :9443: HTTPS HTTP200,
  grpc-status0, точный CORS origin https://hashev.github.io.
- Update в crontab yurik закомментирован; manual-deployment.json содержит
  automatic_apply_paused=true; ранний guard manage.py установлен.
- Свободно 6 271 762 432 байта (около 5,84 GiB).

## Блокеры

### 1. В stable нет совместимого принятого релиза

[Последний stable-релиз v1.0.27](https://github.com/hashev/ffido/releases/tag/v1.0.27)
опубликован 15.11.2026, revision bdf245216c43089d011c6778f2e0465e16fa9082,
sequence1065, container digest
sha256:25b46eb80b6da760d3e30ee54f311f886dc536025ee0dde2f4b170668dd0dca3.
Свежескачанные release-manifest.json/.sig прошли Ed25519 verify_manifest локально.
Их compatibility допускает state_schema9–11, рабочая база —12.
На сервере сохранённый manifest v1.0.27 также прошёл проверку подписи с его
установленными public keys; SHA-256 набора ключей совпал с локальным.

Рабочая пара — локальный safe-mailbox-restore-candidate-20261118, не официальный
подписанный релиз. Публикация Web через PR #50 не публиковала серверные образы.
Требуется отдельный совместимый официальный релиз с Telegram, safe-mailbox-restore,
проверенной schema12 и согласованным tosser. Одного изменения границы в manifest мало.

### 2. Текущая identity не принимается штатным updater

Установленный updater читает настоящий BUILD.json, затем вызывает common.version_key.
Чистая проверка в памяти воспроизвела `Invalid update integer`: build_number2026111804
превышает предел1 999 999 999. При подстановке допустимого числа только в тестовой
копии словаря выявляется второй отказ `Update identity/tag mismatch`:
safe-mailbox-restore-candidate-20261118 не соответствует формату stable/dev tag.
Никакие реальные identity/BUILD/state файлы не исправлялись.

Дополнительно minimum_sequence вычисляется как max(sequence.json, installed.build_number),
сейчас2026111804 против stable1065. Просто разрешить custom tag недостаточно:
следующий обычный релиз будет отвергнут по sequence. Нужен явный проверенный переход
с локального кандидата на подписанную identity, сохраняющий защиту от downgrade;
подделывать BUILD или просто сбрасывать sequence нельзя.

### 3. Обновление пары и откат не согласованы с текущими pins

Установленный ffido-docker-update.py обновляет одну службу. При apply он заменяет
весь image-override.json записью только ffido. Это удаляет нынешний pin ffido-tosser
и pull_policy=never. manage.py затем вызывает rebuild_worker(), строящий tosser
из нового backend. Согласованность, сохранение локальных HPT-правок и восстановление
обоих pins при ошибке не подтверждены репетицией после ручного переключения.

У локальных candidate и rollback образов RepoDigests пуст. Updater запишет для
текущего backend previous_digest=None; его штатный rollback требует опубликованный
digest и не сможет вернуть этот кандидат. Нынешний operation.json всё ещё относится
к переходу между прежними официальными релизами, а не к принятой локальной паре.

Нужна процедура первого перехода, которая сохраняет обе исходные image ID,
конфигурацию и журналы, атомарно переводит согласованную пару, при ошибке возвращает
обе службы и выполняет проверки. Gateway не входит в этот Compose и не должен
пересоздаваться. После обновления необходимы TLS/gRPC-Web/CORS и Telegram-вход,
проверка mailbox bindings и отсутствия смешанной пары backend/tosser.

### 4. Backup цел, но уже не отражает принятую рабочую систему

Заново прочитаны и проверены SHA-256 четырёх артефактов
/srv/ffido-main-cutover-20261119; все совпали с доверенными значениями из
[отчёта переключения](cutover-result-20261119.md): snapshot.json,
snapshot.tar.gz, deployment-extra.tar.gz, host-tools.tar.gz.
Полный manifest complete=true, 3407 файлов, 599 JAM, два mailbox.
Исторический restore-report подтверждает check/apply/repeat и TLS readiness
rollback-образа; **новая репетиция восстановления сейчас не запускалась**.

Этот snapshot — schema11, без telegram_bindings. Он сделан до открытия рабочего
доступа и привязки Telegram. Его слепое восстановление потеряет последующие записи,
привязку и сеансы. Старый snapshot12 в safe-restore-20261118 — прежняя изолированная
репетиция, не свежий полный backup принятой production schema12.

В deployment-extra есть gateway/ACME/cron, но gateway.compose.json отличается от
текущего: отсутствует --disable-hot-restart. Envoy config, pinned env и renew helper
в этом архиве совпали с нынешними. Рабочий /usr/local/sbin/amster-firewall в архив
не включён; прежний снимок правил сделан до открытия9443. Для восстановления нужен
свежий комплект актуальных gateway, сертификатов/ACME, cron, firewall source/unit,
Compose/pins/state/identity/updater и пользовательского cron, с приватными ключами
только в закрытом backup.

Штатный manage.py snapshot() по-прежнему использует старый tar-список и автоматический
stop/start. Он не интегрирован с ffido-node-backup, не включает отдельный рабочий
gateway и пропускает части обязательного layout, например spool/dupebase/flags и
updater/update journals. Поэтому штатный update-backup не заменяет принятую полную
процедуру. Её нужно интегрировать и проверить, учитывая SIGINT для jamnntpd и общий lock.

### 5. Место и свежий rollback gate

Все четыре подготовленных candidate/rollback образа присутствуют. Они не удалялись.
Однако около5,84 GiB свободного места меньше прежнего консервативного бюджета14 GiB
для полного snapshot, упаковки, restore-probe и новых образов. Перед новым окном
нужно пересчитать пиковый расход и обеспечить место либо отдельный диск; оставить
резерв после максимального расхода. Очистка этим аудитом не разрешалась и не делалась.

До обновления нужны свежий stopped-node backup schema12 вместе с Telegram и
персональными ящиками, восстановление на изолированной копии и проверка возврата
обоих образов. Для миграций будущей схемы image-only rollback допустим лишь при
доказанной совместимости. После возобновления записей восстановление старого снимка
требует сохранения/reconciliation новых данных и очередей.

## Порядок дальнейшей подготовки

1. Спроектировать и локально проверить переход local candidate → signed release,
   парное обновление/откат и интеграцию полного backup; не снимать паузу первым шагом.
2. Выпустить отдельно разрешённый совместимый подписанный серверный релиз.
3. Обеспечить место, сделать свежий полный backup и репетицию на копии schema12,
   включая Telegram, mailbox generations, UUE/crosspost receipts и актуальный gateway.
4. Выполнить отдельно разрешённый контролируемый первый переход с проверками;
   только после него отдельно возобновлять регулярный update.

Не запускались manage.sh check/update/backup/rollback, updater check/apply/rollback,
docker pull/build/run, renew или restore. Даже check может менять sequence/journals;
здесь использованы чтение файлов и чистые функции проверки metadata с Python -B,
read-only SQLite, Docker inspect, чтение архивов и HTTPS capabilities без сессии.
Настройки сервера, firewall, cron,
образы и службы не менялись; сообщения не отправлялись. Отчёт сохранён только локально.
