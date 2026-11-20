# Tasks

Все задачи выполняются в репозитории и изолированной локальной среде. Они не
разрешают действия на amster2, production-публикацию или снятие пауз.

## 1. Происхождение и выбор подписанной цели

- [x] 1.1 В scripts/update/common.py и ffido-docker-update.py добавить отдельный descriptor зарегистрированной локальной пары и проверку digest плана, обоих image ID и BUILD. В test_common.py/test_docker.py проверить нестандартный tag, отсутствие RepoDigests, build 2026111804, неизвестную identity и подмену перед применением; строгий обычный version_key должен остаться прежним.
- [x] 1.2 В scripts/update/discovery.py и updater отделить signed floor от локального build number, проверять явно выбранную подписанную цель и сохранять floor после приёмки без понижения при restore. Тестами проверить floor 1065 → цель 1066, старую sequence, неверную подпись/identity и возврат локального кандидата; описать регистрацию и поведение check в docs/docker.md.

## 2. Подготовка и переключение пары

- [x] 2.1 В scripts/update/ реализовать opt-in подготовку backend по подписанному digest и производного tosser по закреплённому рецепту/HPT-входам; сохранять provenance и обе rollback identity/экспорты до остановки. В test_docker.py проверить несовпадение BUILD, mutable входы и ошибку worker: stop и смена pins не вызываются; документировать формат плана и рецепт в docs/deployment/amster2-miniapp/.
- [x] 2.2 В scripts/update/ffido-docker-update.py сохранять исходные override-файлы и атомарно менять только управляемые pins пары. Тестами test_docker.py подтвердить сохранение посторонних полей, mounts, UID/GID, TLS, lock и single-service режима; отдельные gateway/test-service не должны пересоздаваться. Обновить docs/docker.md.
- [x] 2.3 Добавить в scripts/update/ версионируемый host-координатор с общими locks, устойчивым журналом фаз и идемпотентным продолжением после прерывания. Проверить fault injection перед/после записи pins, между запусками и при повторном вызове; одновременно действующая транзакция должна блокироваться. Описать журнал и команды resume/status в docs/docker.md.
- [x] 2.4 Подготовить в scripts/update/ и docs/deployment/amster2-miniapp/ host-адаптер вместо независимого серверного ops/manage.py: исходные состояния/паузы, корректная остановка jamnntpd, private probe backend и gated-start worker без обработки очередей/FTN. Тестами подтвердить отсутствие писателей до admission, запись admission до открытия listener и отсутствие безусловного finally-start после миграции; доставить инструкцию установки без её выполнения.

- [x] 2.5 В C++ ffido-admin/mailbox_restore добавить опциональную передачу удерживаемого maintenance lock с проверкой fd/inode/exclusive open-file-description и сохранением старого CLI. В scripts/test_mailbox_restore.py проверить check/apply, конкурента, неверный inode, отсутствующий/shared lock и сохранение блокировки родителя; собрать и выполнить backend/HPT gates, документировать флаг.

## 3. Полный backup и восстановление deployment

- [x] 3.1 Расширить scripts/node_backup.py deployment-профилем, явными внешними mappings и общим manifest: данные узла, обе identity/образы, Compose/updater/host-инструменты, gateway/TLS/ACME/renewal/cron/firewall. В scripts/test_node_backup.py проверить полноту, внешние зависимости, bounded ACME symlink, права, порчу и path traversal; старые snapshots должны явно отличаться. Описать состав и приватное хранение в docs/deployment/amster2-miniapp/.
- [x] 3.2 Соединить snapshot helper с host-координатором под maintenance/instance/HPT locks, исключив параллельный renewal и изменение включённых конфигураций. Тестами проверить отказ backup при живом писателе, возврат только исходно работавших служб при ошибке до миграции и закрытые писатели после ошибки миграции; helper сам не запускает службы. Описать эту границу ответственности в runbook.
- [x] 3.3 Добавить preflight бюджета места с фактическими размерами, временными файлами, репетицией, обеими парами и резервом 2 GiB по умолчанию. Тестами проверить граничный дефицит, повторную оценку перед копированием и отсутствие stop/cleanup при отказе; отчёт/runbook должны показывать расчёт без универсальной константы 14 GiB.
- [x] 3.4 Реализовать staging-restore полного bundle с внешним trusted digest, сохранением владельцев/прав и проверкой всех компонентов до использования. В scripts/test_node_backup.py и тестах координатора проверить отсутствующий gateway/ACME-компонент и запрет автоматического применения host cron/firewall при репетиции; документировать восстановление инструментов/runtime и проверку материалов продления.

## 4. Откат и приёмка

- [x] 4.1 Реализовать rollback обеих identity, включая локальные image ID без pull, с проверкой совместимости текущих данных; несовместимый вариант восстанавливает полный baseline и применяет штатный ffido-admin mailbox restore. Тестами подтвердить сохранение обоих pins, ошибку update после успешного rollback и запрет старого образа поверх неподдерживаемой БД; описать ветви отката в docs/docker.md.
- [x] 4.2 В координаторе блокировать автоматическую перезапись snapshot после admission, сохранять актуальные данные и диагностировать необходимость reconciliation; rollback не должен понижать signed floor. Тестами проверить новые сообщения/очереди и прерывание на границе admission; runbook должен содержать явный stop-критерий и требование отдельного решения.
- [x] 4.3 Добавить приёмочные probes и тестовые fixtures для Telegram/HPT, сохранённых сессий, изоляции поинтов, mailbox generations и UUE/crosspost receipts, а также TLS/gRPC-Web/CORS gateway. Проверить отказ при healthy backend и неисправном gateway, отсутствие повторной доставки и отсутствие секретов в отчёте; documented acceptance не должна отправлять в FidoNet или снимать auto-update pause.
- [x] 4.4 Сверить scripts/release/update_metadata.py и расширить scripts/release/test_schema_compatibility.py: фактический backend создаёт 12, мигрирует 9/10/11→12, повторно открывает 12 и отклоняет 13; manifest с max 11 отвергается. Выполнить соответствующий unittest с подготовленным backend, обновить docs/testing.md; опубликованные manifests не менять.

## 5. Сквозная локальная репетиция

- [x] 5.1 Расширить scripts/update/test_compose_flow.py либо соседний integration runner полным циклом local-pair → подписанная QA-цель → rollback с временным registry/discovery и QA-ключом. Проверить реальные signature/digest, restore schema 12 с переносом JAM, gateway на изолированных портах, сохранность Telegram/mailbox и fault injection по фазам. Рабочие mounts/production endpoints/FTN должны быть недоступны; результат и точные команды сохранить в docs/deployment/amster2-miniapp/ без секретов.
- [x] 5.2 Запустить штатные unittest scripts/update, scripts/release и scripts/test_node_backup.py через существующее build/update-venv; выполнить применимые backend/HPT restore gates по docs/testing.md с FFIDO_TEST_HPT и scripts/release/check_ctest.py. В итоговом отчёте отделить успешные проверки от skipped/недоступных, приложить локальный runbook перехода/отката и список условий будущего production-допуска. Недоступная сквозная проверка остаётся открытой задачей, а не считается успехом.

## Workflow follow-up

- После реализации и успешной проверки отдельно запросить архивирование change.
- Выпуск production-релиза, свежий аудит/backup amster2, применение перехода и последующее возобновление автообновлений выполняются отдельными поручениями и не являются задачами этого apply.
