# Подготовка обновления FFIDO на amster2

Состояние проверки на 29 октября 2026 года: production не обновлялся.
На узле установлен сервер 1.0.4, Android 1.0.7 не меняет версию сервера.
Старые Tagline/Origin в NINO.120.LOCAL соответствуют поведению сервера 1.0.4.
Новые поля footer доступны начиная с сервера 1.0.5 через Login/RestoreSession.
Исторические сообщения обновление не переписывает.

**Обновление до опубликованного 1.0.7 пока заблокировано.** Изолированная
репетиция с официальным 1.0.4 создаёт SQLite `user_version=10`, а подписанный
manifest 1.0.7 разрешает только 9. Штатный updater правильно останавливает
операцию с `Container state schema is incompatible` и запускает прежний сервер.
Нельзя менять `PRAGMA user_version`, подписанный manifest или обходить проверку.
В исходниках диапазон исправлен на 9–10. Локальная подписанная репетиция исправленного кандидата прошла; для production по-прежнему нужен новый официальный подписанный выпуск.
Ниже приведён порядок подготовки; это не разрешение обновлять рабочий узел.

## Проверенные пути и обвязка

Рабочий каталог — `/home/yurik/fido`, Compose — `docker-compose.yaml`, сервисы —
`ffido`, `ffido-tosser`, `fido`, `jamnntpd`. Точка обслуживания —
`/home/yurik/fido/ffido/manage.sh`; она запускает `ffido/ops/manage.py` и удерживает
`ffido/maintenance.lock`. Обновление использует `ffido/updates`, включая
`image-override.json`, `operation.json`, подписанные выбранные manifest/signature
и счётчик последовательности. Нельзя запускать параллельные updater/обвязку.

Проверенные команды только для чтения:

```sh
ssh amster2
cd /home/yurik/fido
ffido/manage.sh status
ffido/manage.sh check
```

`check` проверяет подпись и наличие кандидата, но не доказывает совместимость
реальной БД: проверка `PRAGMA user_version` выполняется позднее в `apply`.
Для ручного вызова того же updater:

```sh
ffido/venv/bin/python ffido/updater/scripts/update/ffido-docker-update.py check \
  --compose-file /home/yurik/fido/docker-compose.yaml \
  --service ffido --state-dir /home/yurik/fido/ffido/updates --channel stable
```

Не публикуйте вывод полного `docker compose config`, `.env`, config.json,
сессионные/TLS-ключи и архивы: они содержат рабочие секреты.

## Preflight

1. Зафиксировать version/tag/sha из `/opt/ffido/BUILD.json`, фактический digest
   образа и readiness. Контрольный digest установленного 1.0.4:
   `sha256:df275d0bbb39efb9be70c74dc5a771b73844053fcec9f28a2d11193439b1b834`.
   Сверять фактический запуск, а не только тег или `deployed-identity.json`.
2. Проверить подпись нового manifest доверенным ключом штатного updater,
   канал, sequence, platform linux/amd64, OCI version/revision, digest,
   config format, JAM format и диапазон схемы. Сохранить выбранные подписанные
   входы локально; запись `available` сама по себе не разрешает замену.
3. Прочитать локально `ffido/ops/manage.py` и active markers в
   `local-jam-encoding-20261023`, `local-owner-echo-20261023`,
   `local-hpt-transport-20261023`, `review-codecs-access-20261023`.
   Сопоставить с кандидатом KOI8-R/UTF-8 codec, права владельца и HPT patch
   из [инструкции worker](README.md). Не удалять markers и не снимать
   `automatic_apply_paused` ради обхода паузы. Повторить charset acceptance
   из README на изолированных JAM с новым образом и worker.
4. Проверить постоянные mounts `/etc/ffido/config.json`, `/etc/ffido/tls`,
   `/var/lib/ffido`, `/srv/fido`, владельцев/UID/GID, место под backup и образы,
   TLS gRPC healthcheck. Не заменять конфигурацию поставляемым примером.
5. Остановить конкурирующие cron/systemd maintenance задачи на время операции,
   сохранить их прежнее расписание. Подготовить старый digest и worker для
   восстановления без сети; выбрать окно обслуживания.

## Согласованная копия и обновление

Сначала на изолированных базах повторить **весь** цикл, включая восстановление:

```sh
export PATH="/path/to/flutter-3.47.7/bin:$PATH"
/path/to/python-with-update-requirements scripts/check_footer_upgrade.py \
  --local-candidate --directory /private/tmp/ffido-footer-fresh-run \
  --hpt /path/to/native/hpt
```

Каталог должен отсутствовать. Сценарий использует только искусственные RU.ONE /
RU.TWO, временные TLS и учётные данные; Docker Compose получает случайное имя.
Флаг `--local-candidate` использует loopback registry, временный ключ и копию updater. Проверяются настоящие подпись, digest, schema gate и Docker-переключение; изменяется только транспорт обнаружения и доверенный ключ изолированной копии. Без флага опубликованный 1.0.7 по-прежнему отвергается из-за схемы. Для Android добавьте `--android emulator-5554` при запущенном эмуляторе.
Успехом считается только итоговый `result.json` после update, HPT scan и restore;
наличие промежуточных файлов не означает прохождения.

После устранения блокировки и отдельного разрешения на production:

1. Проверить отсутствие незавершённого `update-transaction.json` и изучить
   `updates/operation.json`. Ветка `prepared` в manage.py продолжает прежнюю
   операцию без нового snapshot; это требует проверки имеющейся копии.
2. `ffido/manage.sh backup` останавливает все четыре сервиса, сохраняет
   согласованные JAM/очереди/state/config/TLS/локальные политики и crontab в
   `ffido/backups/<timestamp>-maintenance`, затем запускает сервисы обратно.
   Для update обычная ветка `ffido/manage.sh update` сама вызывает snapshot,
   оставляет FFIDO/worker остановленными и возобновляет mailer/NNTP. Поэтому
   отдельный ранний backup не заменяет snapshot непосредственно перед update.
3. Защитить backup правами 0700/0600. Дополнительно сохранить под тем же
   maintenance lock `ffido/updates`, `ffido/deployed-identity.json`,
   `ffido/update-transaction.json` при наличии, digest старого worker и
   образов. Проверенный snapshot сам не включает каталог `updates`.
4. Запускать `ffido/manage.sh update` только после подтверждения всех gates.
   Обвязка применяет подписанный digest, сохраняет identity, обновляет только
   `FFIDO_IMAGE` в `.env`, пересобирает и запускает worker. Это обоснованное
   изменение `.env`, а не повод переписать остальные настройки.
5. Проверить `healthy`, точные version/sha/digest, `phase=complete`, согласованную
   версию worker, права и чтение исторических сообщений. При ошибке worker
   остаётся остановленным: изучить журнал до ручного запуска или восстановления.
6. Перезапустить клиент или восстановить сессию через RestoreSession. Проверить
   `supports_message_footer=true`; прежняя сохранённая сессия должна остаться
   действительной. На тестовых JAM проверить обычное письмо, ответ, кросспост:
   автоматический и пользовательский Tagline/Origin, ровно один footer,
   фактический FTN-адрес автора, сохранность после HPT scan. Рабочие эхи
   для этой проверки не использовать.

## Восстановление

Нельзя откатывать только образ поверх несовместимой новой схемы. Проверка rollback
штатного updater также обязана отказать, если старые метаданные не допускают
текущую схему; обходить её нельзя.

Для восстановления согласованной копии остановить maintenance и все четыре
сервиса, сохранить повреждённое состояние отдельно, затем восстановить **вместе**
JAM, очереди, SQLite (включая согласованное состояние WAL), session key,
конфигурацию, `.env`, TLS, local markers, `updates` и журналы транзакции из одного
snapshot. Не распаковывать архив поверх работающих писателей. Сохранить исходных
владельцев и права. Вернуть точно проверенные старые digest FFIDO и worker,
создать контейнер FFIDO с прежними mounts, проверить readiness, identity,
восстановление сессии и байты старых сообщений, затем запустить worker и
mailer/NNTP. Только после успешной проверки вернуть прежнее расписание.

Окончательные команды распаковки должны ссылаться на выбранный проверенный
snapshot; универсальная команда с подстановкой «последней» копии здесь намеренно
не приводится. Контроль восстановления входит в изолированную репетицию выше.

При восстановлении файлов JAM меняются inode и generation сообщений. Клиент
должен заново загрузить списки: прежний MessageReference может стать недействительным.
Сравнивать сохранность тела следует по сообщению из нового списка, а не обходить
проверку generation. Репетиция также сверяет исходные байты `.jdt`.
