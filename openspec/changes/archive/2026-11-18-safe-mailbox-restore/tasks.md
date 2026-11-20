# Tasks

## 1. Полный снимок и доверенный manifest

- [x] 1.1 Добавить в scripts/ версионированный формат snapshot manifest и валидатор: состав, SHA-256, SQLite schema11/12, address/base и исходные идентичности всех JAM. Unittest проверяют неизвестную версию, дубликаты, traversal, symlink/hardlink, неверный внешний digest и неполный файл; приватные данные не выводятся в ошибках.
- [x] 1.2 Реализовать сбор зависимостей через существующий HPT/config adapter с явными дополнительными путями и тестами includes, intab/outtab, corrections manifest, spool/queues/flags, TLS/session key и updater state. Проверка: fixtures с отсутствующей зависимостью не получают завершённый manifest; описание состава добавить в apps/backend/README.md.
- [x] 1.3 Добавить остановленный snapshot helper в scripts/ с проверкой maintenance/instance/HPT locks и состояния писателей, приватными правами, завершением только после fsync/проверки архива, без auto-start служб. Unittest проверяют занятый lock, изменение файла при копировании, ошибку архива/нехватку места, сохранение специальных/referenced backups и отсутствие рекурсии backups внутрь backup. Рабочий удалённый manage.py не менять.

## 2. Offline восстановление metadata

- [x] 2.1 Добавить отдельное открытие существующей SQLite для restore в apps/backend/src/storage/ без автоматического Init/migration. CLI-регрессии scripts/test_mailbox_restore.py на реально provisioned SQLite подтверждают schema11 остаётся 11, schema12 остаётся 12, неизвестная/неполная схема и отсутствующий файл отклоняются без CREATE.
- [x] 2.2 Реализовать проверенный план восстановления в apps/backend/src/storage/point_mailbox.cpp и соседних restore-модулях: FD-based проверка доверенного manifest, всех компонентов JAM, адресов/путей и однозначного generation mapping. Регрессии проверяют чужой ящик, одинаковое содержимое разных адресов, смену inode после check, повреждённый header, повторное старое поколение и план без доверенного digest; отказ не меняет БД/JAM.
- [x] 2.3 Реализовать атомарное восстановление физической mailbox identity и проверенного logical-generation mapping в runtime, сохраняя без переписывания ссылки read_status, reading_positions, operations, mail_provenance, mail_transfers, bulk_read_operations и UUE/crosspost/FTN receipt. Тесты подтверждают прежние ACL/прочитанность/позицию/историю/закладки/направление и повтор исходного подтверждённого запроса без дубликата; pending/uncertain/неоднозначные ссылки отклоняются до commit.
- [x] 2.4 Добавить backup-before-apply, повторную проверку под locks, атомарный commit и идемпотентный повтор/проверку исхода. Fault/process-тесты проверяют прерывание до/после commit, недоступный fsync/backup, занятый instance/coordination lock и неизменность остальных пользователей; журнал ошибок не содержит секретов.

## 3. Административная команда и интеграционные проверки

- [x] 3.1 Подключить mailbox-restore check/apply к существующему ffido-admin и service/point_mail_admin, без RPC/FE изменений. CLI-тесты проверяют аргументы, dry-run без изменений, stale plan, доверенный digest и явное apply; документировать invocation, locks, приватность, schema11 rollback и ограничения pending state в apps/backend/README.md и docs/deployment/amster2-miniapp/.
- [x] 3.2 Выполнить штатные ./build.sh build, focused и полный CTest с FFIDO_TEST_HPT и python3 scripts/release/check_ctest.py build/backend, python3 scripts/check_cpp.py --build-dir build/backend, unittest backup helpers и применимые ASan/UBSan/TSan по docs/testing.md. Записать реально пройденные проверки и ограничения; новые warnings/failures исправить без ослабления проверок.

## 4. Повторная репетиция amster2

- [x] 4.1 Собрать новые linux/amd64 backend/tosser и отдельную пару rollback backend/tosser на базе v1.0.27 с restore-support из замороженных source manifest; сохранить image IDs, source digest, BUILD identity, архивы и результат release gate. Проверка: дистрибутив FFIDO внутри каждой пары backend/tosser побайтно совпадает, HPT runtime сохранён, ничего не опубликовано и рабочие теги/сервисы не заменены.
- [x] 4.2 Подготовить полный sandbox snapshot из существующей приватной копии amster2 с явным provenance дополнений; проверить новый backup helper и отсутствие доступа к live-зависимостям при restore. На распакованной schema11 выполнить штатные check/apply и readiness rollback-образа v1.0.27 с restore-support; отдельно проверить migration11→12 и восстановление schema12 новым образом, сохранив личные данные и идемпотентность без ручных SQL-исправлений.
- [x] 4.3 Повторить негативные restore-сценарии на отдельных копиях; сохранить безопасный отчёт в docs/deployment/amster2-miniapp/ и закрытый подробный на сервере. Проверить network=none, отсутствие production mounts/published ports/FTN-экспорта, остановку контейнеров репетиции и неизменные конфигурации/время старта рабочих служб. production_rollback_ready=true допустим только после всех обязательных успешных сценариев; непроверенный runtime-сценарий не заменять сохранностью SQL-строк.

## Workflow follow-up

- Рабочие backup scripts/cron на amster2, production backend/tosser, firewall, gateway и каталог не обновлять в рамках этого change; применение к рабочему узлу требует отдельного запроса.
- После реализации и проверки отдельно запросить архивирование change по штатному OpenSpec workflow. Исходный telegram-mini-app архив не переписывать.
