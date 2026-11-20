# Переход локальной пары на подписанный релиз

Этот runbook описывает новый парный режим. Он не разрешает выполнять его на
amster2. Публикация релиза, установка инструментов, рабочий переход и снятие
паузы выполняются отдельными поручениями после локальной приёмки.

## Исходные условия

- Выбран новый совместимый подписанный релиз с schema 12, Telegram и safe mailbox
  restore. Старый manifest v1.0.27 с max 11 не исправляется и не используется.
- Подготовлены updater с прежними production trust keys и новый restore toolkit:
  `ffido-admin --help` должен показывать `--maintenance-lock-fd`, helper HPT должен
  поддерживать backup inventory. Пути и содержимое toolkit фиксируются хешами.
- Локальная пара зарегистрирована точными image ID, фактическими BUILD и платформой.
  Для обоих сервисов используются одинаковые FFIDO distribution/BUILD.
- Все scheduled update guards/cron остаются в исходном состоянии. Renewal должен
  использовать тот же maintenance lock. Во время согласованного snapshot ручные
  изменения конфигураций также исключаются.
- Для каждого перехода выделяется новый приватный state-каталог вне данных узла.
  Снимки, исходная/целевая пары и staging сохраняются до отдельного решения об очистке.

## Приватный план

План JSON версии 1 содержит следующие поля. Абсолютные пути относятся к конкретной
изолированной копии либо к отдельно разрешённому deployment; их нельзя переносить
из локальной репетиции на сервер без проверки.

| Поле | Содержимое |
| --- | --- |
| `source.backend`, `source.tosser` | `image_id` вида sha256:…, фактический объект `build`, `platform: linux/amd64` |
| `files` | Словарь абсолютный путь → SHA-256: Compose, исходный override, backend config, deployed identity и pause markers |
| `services` | Логические роли backend/tosser → реальные имена Compose services |
| `writers` | Все писатели Compose: backend, tosser, mailer, jamnntpd и другие использующие эти данные службы |
| `jamnntpd_service` | Имя службы, которой для корректного завершения посылается SIGINT |
| `identity_file` | Файл deployed identity, проверяемый worker |
| `container_config`, `container_identity_file` | Пути этих файлов внутри worker; по умолчанию /etc/ffido/config.json и /home/fido/ffido/deployed-identity.json |
| `signed_floor` | Пути `manifest`/`signature` ранее доверенного подписанного релиза; проверяются установленными keys |
| `worker` | `context`, `dockerfile`, `files` (относительный путь → SHA-256), immutable `hpt_image` и точный `hpt_image_id` |
| `backup` | `root`, относительный `config`, `maintenance_lock`, `helper`, `admin`, `mappings` списком пар и дополнительные `includes` |
| `components` | Полные явно выделенные корни внешних deployment-компонентов, описанные ниже |
| `probes` | Списки argv-команд `private`, `public`, `pair`; все обязательны, ненулевой exit блокирует приёмку |
| `require_full_restore` | Опционально true для обязательной репетиции полного восстановления вместо image-only rollback |
| `extra_images` | Immutable image ID/digest gateway и restore toolkit, если они не входят в пару; экспортируются вместе с четырьмя образами пары |
| `automatic_guards` | Для будущего --automatic: pause_files с automatic_apply_paused и block_if_exists для самостоятельных legacy guards |

План не содержит HPT-паролей, Telegram initData или session tokens. Если probes
используют тестовые credentials, они читают их из отдельного приватного файла,
а не из argv. Внешний digest плана закрепляется до применения, вне восстанавливаемого
каталога. Неизвестная identity или изменившиеся файлы блокируют остановку.

`worker` использует две стадии `${FFIDO_IMAGE}` и `${HPT_IMAGE}`: первая — выбранный
backend по digest, вторая — закреплённый существующий HPT runtime с локальными
transport-правками. Допустим `RUN rm -rf /opt/ffido`, затем перенос всего
`/opt/ffido/` из первой стадии. ADD, загрузки пакетов и произвольные RUN не допускаются.
ENTRYPOINT должен сохранять штатный worker. На gated-start entrypoint временно
заменяется проверкой identity/admin/HPT-конфигурации/read-only SQLite и ожиданием
на приватном loopback socket без обработки очередей; нормальный worker стартует после
приёмки. Образ готовится до остановки узла; оба исходных и оба целевых образа
экспортируются в `STATE/rollback-images/images.tar`.

## Состав полного bundle

`components` обязан содержать девять ролей: deployment, images, updater, gateway,
tls, acme, renewal, cron, firewall. Каждая задаётся объектом `root` и непустым списком
относительных `required`. Опциональный `includes` ограничивает выбор файлами и
подкаталогами внутри корня; без него копируется весь корень. Обязательные файлы
должны входить в выбор. Исключаются runtime logs/status, история backup и
непереносимый venv, но не конфигурационные зависимости или данные для отката.

- deployment: действующие Compose, pins, env, конфигурации, deployed identity.
- images: строго `STATE/rollback-images`, обязательны images.tar и images.json.
- updater: код, public keys, состояния/журналы, pause markers и pinned requirements.
- gateway: действующий отдельный Compose, Envoy config, pins и параметры запуска.
- tls/acme: upstream CA, материализованные gateway TLS и полное состояние отдельного
  ACME account/config/archive/live/renewal. Разрешены только live-ссылки внутрь archive.
- renewal: действующий helper и инструкции воспроизводимой подготовки его runtime.
- cron/firewall: действующие относящиеся к узлу cron/systemd настройки, firewall script
  и снимок политики. В репетиции они копируются как данные и не применяются к хосту.

Данные узла снимаются штатным `scripts/node_backup.py`: JAM/SQLite/session key,
личные ящики, uploads/receipts, очереди/dupebase/flags и все выявленные зависимости
HPT/TLS/corrections. `deployment.json` связывает этот snapshot и внешние компоненты.
Успех публикуется только после проверки файлов, полного inventory и внешнего digest.
Старый snapshot без deployment.json не проходит полный gate.

Бюджет учитывает несжатый snapshot, архив, staging и временные данные: консервативно
`4 × source_bytes + 2 × image_bytes + reserve`, по умолчанию reserve = 2 GiB.
Реальные свободные байты проверяются до остановки и перед копированием. Старые
14 GiB — ориентир прежней репетиции, а не обещание достаточности. Автоочистки нет.

## Команды и фазы

К общим `--compose-file FILE --service BACKEND --state-dir STATE` добавляются
`--pair-plan PLAN --pair-plan-sha256 DIGEST --target-manifest MANIFEST
--target-signature SIGNATURE --target-tag TAG --channel stable`.
Исполняемый файл: `build/update-venv/bin/python scripts/update/ffido-docker-update.py`.

1. `check` проверяет source registration и явно выбранную подписанную цель. Это
   не проверка дискового бюджета или готовности всех инструментов.
2. `apply` подготавливает оба образа, проверяет место/identity/toolkit, фиксирует
   исходные состояния и под общей блокировкой останавливает всех писателей.
   Исходный backend должен работать; ранее остановленные worker/mailer сохраняют
   своё состояние. Остановка использует SIGTERM и ожидание без принудительного
   SIGKILL, для jamnntpd — SIGINT.
3. После полного backup pins пары записываются одной операцией. Временно backend
   и gated worker запускаются с network_mode none; backend проверяется внутренним
   TLS probe, затем выполняются private probes.
4. До открытия нормального listener журнал получает `admitted=true`. Public probes
   проверяют доверенный HTTPS/gRPC-Web/CORS gateway, после чего закрепляется signed
   floor и возвращаются ранее работавшие FTN-писатели. Автообновления не возобновляются.
5. `status` показывает фазу без credentials. `resume` повторяет безопасную отмену
   незавершённого перехода до admission; после admission останавливает писателей
   и требует reconciliation.

Проверки `private/public/pair`, `rollback_private/rollback_public` должны включать обе identity, личные данные и границы
доступа, Telegram/HPT и прежние допустимые сессии, mailbox generations, повторы
UUE/crosspost, gateway TLS/gRPC-Web и точный origin. Healthy одного backend
недостаточно. В репетиции отсутствуют production mounts/endpoints и FTN-сеть.

После приёмки сохраняются подписанные manifest/signature и pair-provenance.
Следующие `check/apply` с тем же планом могут выбирать релиз через штатный discovery,
без target-параметров: текущие image ID/BUILD сверяются с подписанным происхождением,
а не объявляются заново локальными. Одиночный updater отказывается менять этот state.
`--automatic` требует уже принятую подписанную пару и явно настроенные снятые guards;
этот флаг не снимает ни одного guard и не используется для первого перехода.

## Среда локальной репетиции

Координатор, provisioning, backup и admin должны работать в одном Linux-ядре с
backend/tosser: macOS и Docker видят разные st_dev/st_ino у одной host-копии.
Для Mac используется временный Linux QA host и отдельный Docker volume. Docker CLI
и socket доступны только тестовому координатору; FFIDO-контейнеры получают свои
изолированные каталоги данных. Входные tool images закрепляются digest/image ID.

`scripts/update/qa-host.Dockerfile` собирается из подготовленной QA-distribution,
matching Docker CLI/Compose, Envoy и build-tools с fault library. Python 3.12 и
зависимости из scripts/update/requirements.txt фиксируются без смены project lock.
Образ toolkit включается в extra_images. Gateway/cron/firewall/ACME в fixtures
локальные; рабочие сертификаты и аккаунты не нужны.

Скрипт `scripts/update/test_pair_compose_flow.py` запускается внутри QA host с
`--directory NEW_LINUX_VOLUME_PATH --source-worker IMAGE_ID
--admin /opt/ffido/bin/ffido-admin --envoy /usr/local/bin/envoy --toolkit-image QA_HOST_ID`.
Он подписывает только loopback QA-релиз, меняет Telegram key исключительно в
тестовой копии исходника, создаёт два фиктивных поинта и проверяет реальные RPC.
Начальная Telegram-связь создаётся как fixture при остановленном backend, а новая
QA-сборка проверяет свежий подписанный Telegram-вход. Восстановление SQL не исправляет.

## Откат

До admission `rollback` проверяет совместимость обеих прежних identity с текущими
данными. Совместимый image-only возврат использует сохранённые image ID без pull;
при несовместимости или require_full_restore восстанавливается проверенный baseline.
Сетевые FTN-писатели до проверки восстановленной пары не запускаются. Успешный
rollback сохраняет исходное обновление как неуспех.

Новый `ffido-admin mailbox-restore ROOT MANIFEST SHA256 check|apply [PLAN_DIGEST]
[--maintenance-lock-fd FD]` принимает maintenance lease через pass_fds. Первая запись
locks manifest — maintenance lock. CLI проверяет уже удерживаемый exclusive lock,
inode/device и open-file-description, самостоятельно захватывает instance/HPT и
не снимает блокировку родителя. Без флага старый синтаксис сохраняется.

При атомарной записи BUILD identity координатор сохраняет владельца, группу и права
существующего файла, чтобы worker под UID 1000 мог прочитать его после switch/rollback.
Приватные state/journal-файлы остаются с правами 0600.

После admission старый snapshot автоматически не возвращается. Остановленные
актуальные данные сохраняются, затем отдельно решается reconciliation новых
сообщений, receipts и транспортных очередей. Обходить этот gate флагом force или
ручным SQL нельзя. Signed floor не понижается даже при возврате локального кандидата.
Явный image-only rollback после admission допускается при доказанной совместимости
прежней пары: новый полный снимок текущих данных сохраняется, старый snapshot
не применяется, все последующие записи остаются на месте. Если требуется полный
restore, в том числе при require_full_restore, операция блокируется до reconciliation.
