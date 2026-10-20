# Tasks

## 1. Контракт и хранение массовой отметки

- [x] 1.1 Добавить `MarkConferenceRead` и request/response в `contracts/ffido/v1/ffido.proto`, сгенерировать клиентские файлы штатным `tools/proto/generate.sh`; descriptor-тестами проверить неизменность старых полей/RPC и новый контракт, описать совместимость в `apps/backend/README.md`.
- [x] 1.2 Расширить `apps/backend/include/storage/metadata_store.hpp` и `src/storage/sqlite_store.cpp`: миграция от текущей схемы 7, транзакционные пакетные read_status и receipt по user/operation. Unit-тестами проверить сохранение старых данных, повтор после рестарта, конфликт другой конференции, пустую операцию, generation, отсутствие изменений history/reading_positions, конкурентное одиночное чтение и rollback при SQL-сбое; документировать backup/rollback.

## 2. Серверная операция

- [x] 2.1 Реализовать bulk в `apps/backend/include/service/message_service.hpp`, `src/service/message_service.cpp` и RPC `grpc_service.*`: auth/read ACL до любых эффектов, только JAM EchoArea, согласованный снимок живых номеров без декодирования тел и повтор receipt. Service/RPC-тестами проверить сообщения за первой страницей, удалённые записи, новую generation, чтение без права постинга, запрет чужой/личной/служебной области, пустую эху и недействительную сессию; хеши временных JAM/JLR не меняются.
- [x] 2.2 Добавить интеграционные тесты потери ответа, новых поступлений и повторов после restart в `apps/backend/tests/integration/`, двух пользователей и двух сессий одного профиля. Проверить сохранение новых писем непрочитанными, idempotency-конфликт и rollback, прогнать большую временную базу на 100000 записей и записать время/ограничения в `docs/manual-test-results.md`.

## 3. Клиентская массовая отметка

- [x] 3.1 Добавить метод в `apps/frontend/lib/api/api_transport.dart`, `api_client.dart`, fake transport и `repositories/message_repository.dart`; repository/API-тестами проверить неизменный operation_id при uncertain retry, UNIMPLEMENTED старого сервера, epoch/cancel, отсутствие fallback на GetMessage/поштучные MarkRead; описать поведение в `apps/frontend/README.md`.
- [x] 3.2 Добавить действие overflow-меню и подтверждение в `apps/frontend/lib/pages/message_screen.dart`, занятость и повтор неопределённого результата, инвалидировать счётчики/кеш после подтверждения. Widget-тестами проверить отмену, две страницы/цепочку, Echo-only, отсутствие ложного успеха, network/смену аккаунта, сохранение открытого письма/позиции/фильтра и обновление счётчиков без оптимистичного нуля; добавить инструкцию проверки на временном стенде.

## 4. Нижняя навигация

- [x] 4.1 Обновить `apps/frontend/lib/pages/reader_app.dart`: скрыть обе разновидности постоянных labels, оставить четыре Material-иконки, выделение выбранной формы/индикатора, tooltip и semantics. Widget-тестами проверить переходы всех вкладок, отсутствие видимых подписей, доступные названия/фокус, область 48px и сохранение refresh/cache поведения; описать новую панель в README.

## 5. Итоговая интеграция

- [x] 5.1 Выполнить корневые CMake configure/build/CTest, штатные C++ проверки и `tools/proto/generate.sh --check`; из `apps/frontend/` pub get/analyze/test, форматирование и macOS/Android release build. Проверить через реальный Flutter ApiClient две сессии и большую временную эху; вручную проверить меню/счётчики/иконки на macOS и доступных мобильных средах, записав фактические результаты и ограничения в `docs/manual-test-results.md` без изменений рабочего HPT/JAM.
- [x] 5.2 Проверить `openspec validate mark-echo-read-and-icon-navigation --strict`, итоговый diff, соответствие сценариев тестам и инструкции совместимости/миграции SQLite; подтвердить отсутствие изменений реальных баз и конфигураций.

## Workflow follow-up

- После реализации и проверок предложить синхронизацию спецификаций и архивирование отдельным запросом.
