# Tasks

## 1. Аддитивный контракт и объявление поддержки

- [x] 1.1 В `contracts/ffido/v1/ffido.proto` добавить ровно поля SessionInfo.supports_offline_sync=5 (bool), Conference.generation=17 (string), ListMessagesResponse.generation=5 (string), ListMessagesRequest.after_message_id=7 (string), ReadArchiveMessageRequest.include_subfields=5 (bool), ReadArchiveMessageResponse.subfields=6 (repeated MessageTechnicalSubfield), attributes2=7 (uint32) и MessageSort.MESSAGE_SORT_NUMBER_ASCENDING=3; добавить комментарии raw JAM к обоим attributes. Проверка: diff не меняет прежние номера/типы, комментарии содержат Local=0x1, Private=0x4 и отличие от FTS-0001.
- [x] 1.2 В `contracts/tests/test_contract.cpp` и `apps/frontend/test/api/contract_test.dart` добавить проверки каждого нового поля и enum: номера/типы по descriptor либо wire-тегам, round-trip значений и protobuf-defaults, включая отсутствующий capability=false, bytes и uint32 со старшим битом; сохранить тесты неизвестных enum. Проверка: C++ Contract и Dart contract_test проходят.
- [x] 1.3 Выполнить `(cd tools/proto && dart pub get --enforce-lockfile)`, `tools/proto/generate.sh`, `tools/proto/generate.sh --check` с закреплённым protoc (при необходимости PROTOC); CMake регенерирует C++/descriptor. Проверка: повторная генерация идентична, версии/lock-файлы не изменены, generated не редактирован вручную.
- [x] 1.4 В `apps/backend/src/service/grpc_service.cpp` установить флаг true в Login и RestoreSession, добавить gRPC-тесты обеих операций в `apps/backend/tests/integration/test_grpc.cpp`. Проверка: новый и существующие supports-флаги присутствуют в обоих ответах.

## 2. Поколение во всех ответах

- [x] 2.1 Расширить модели в `apps/backend/include/domain/` и mapping в `apps/backend/src/service/grpc_service.cpp`, заполнение в `apps/backend/src/service/conference_service.cpp` и `message_service.cpp`: брать generation из того же JamAccess для Conference с известной статистикой и всех успешных ListMessages/GetThread/GetArchiveThread. Проверка: сервисные/gRPC-тесты сопоставляют поле с префиксом message_id, включая пустые страницы.
- [x] 2.2 В `apps/backend/tests/integration/test_services.cpp` и `test_grpc.cpp` проверить statistics_known=false → пустое generation, omit_statistics → отсутствие открытия JAM, замену файлов с прежними total_count/last_message_date → новое generation во всех четырёх ответах там, где поле заполняется. Проверка: тесты воспроизводят смену поколения самого message_id, а не вводят новую его трактовку.

## 3. Диапазон JAM и ListMessages по номеру

- [x] 3.1 В `apps/backend/include/JamMessageBase.h` добавить минимальный helper диапазона слотов/живых номеров, поддерживающий обход строго после номера без чтения заголовков ниже или на нём; использовать active_msgs для total. Добавить storage unit-тесты в `apps/backend/tests/unit/` с регистрацией в существующем CMake при необходимости. Проверка: пустая база, ненулевой base_msg_num, удалённые/крайние слоты, переполнение и наблюдение прочитанных номеров доказывают границы обхода; ошибки читаемых записей не скрываются.
- [x] 3.2 Расширить `apps/backend/include/service/message_service.hpp`, `apps/backend/src/service/message_service.cpp`, domain и `grpc_service.cpp` для NUMBER_ASCENDING и after_message_id, изолировав новую ветку от прежних сортировок. Проверка: сервисные тесты показывают возрастающие живые JAM-номера, offset без курсора, limit, total всей базы, actual_offset=0 с курсором, корректный has_more и пустую последнюю страницу.
- [x] 3.3 Добавить в `apps/backend/tests/integration/test_services.cpp` и `test_grpc.cpp` позднее поступление письма со старой датой, удалённый курсор, курсор на base_msg_num и последнем слоте. Проверка: возвращаются только большие живые номера, старые заголовки не читаются; previews и respect_personal_filters сохраняют семантику.
- [x] 3.4 Добавить строгий разбор курсора и тесты ошибок: malformed/пустая часть/лишний разделитель/нечисло/переполнение → INVALID_ARGUMENT; другое поколение, номер до base_msg_num, после последнего слота и курсор в пустой базе → FAILED_PRECONDITION; query/anchor с NUMBER_ASCENDING, after с другой сортировкой или ненулевым offset → INVALID_ARGUMENT. Проверка: сервис и wire возвращают именно ожидаемые статусы.
- [x] 3.5 В `apps/backend/tests/integration/test_grpc.cpp` закрепить отказ NUMBER_ASCENDING в FindMessage и SearchArchiveMessages и неизменность прежних сортировок. Для новых успешных, пустых и ошибочных списков сравнивать снимки read_status, history и reading_positions с ревизиями. Проверка: все снимки совпадают, прежние service/API tests проходят.
- [x] 3.6 Описать новые поля, ошибки курсора и отсутствие межзапросного снимка в `apps/backend/README.md`, не меняя документацию чужих работ. Проверка: описание соответствует delta conference-browsing и не обещает сортировку по дате.

## 4. Полные сырые подполя архивного чтения

- [x] 4.1 Расширить ArchiveMessage в `apps/backend/include/domain/`, интерфейс/реализацию MessageService и gRPC mapping: include_subfields проверяет offset=0, переносит все raw-подполя и attributes2 только для нескрытого ответа. Проверка: GetMessageTechnicalData и прежние include_subfields=false вызовы сохраняют поведение и не получают дополнительных raw-чтений.
- [x] 4.2 В `apps/backend/tests/integration/test_services.cpp` и `test_grpc.cpp` добавить fixture с LoID 4, 5, 2000, 2001, 2002, 2004, 7 и другими/неизвестными, разными high_id, повторами, пустыми значениями, NUL и невалидным UTF-8; attributes2 со старшим битом. Проверка: все bytes и порядок сохранены, attributes2 совпадает с raw и техническим ответом; блок 64 КиБ проходит, превышение отклоняется существующей проверкой без усечения.
- [x] 4.3 Проверить include_subfields=true с ненулевым offset → INVALID_ARGUMENT; false → прежний ответ и пустые/нулевые новые поля; collapsed/reveal=false → пустые/нулевые поля; reveal=true на первой части → полные поля. Проверка: service/gRPC tests проходят, read_status/history/reading_positions с ревизиями до/после совпадают для успехов и ошибок, JAM и фильтры не меняются.
- [x] 4.4 Дополнить `apps/backend/README.md` описанием include_subfields, первой части тела, collapse и общего лимита блока. Проверка: документация не обещает расширения GetMessageTechnicalData и соответствует archive-research delta.

## 5. Общая проверка интеграции

- [x] 5.1 Из корня выполнить `./build.sh build`, полный `ctest --test-dir build/backend --output-on-failure --parallel 4`, `python3 scripts/check_cpp.py --build-dir build/backend`, `tools/proto/generate.sh --check`; с закреплённым HPT — `FFIDO_TEST_HPT="$PWD/build/release-deps/prefix/bin/hpt" python3 scripts/release/check_ctest.py build/backend`. Проверка: все применимые gates проходят; отсутствие зависимости или skipped HPT явно отражены как ограничение.
- [x] 5.2 Из `apps/frontend` с закреплённым SDK выполнить `flutter pub get --enforce-lockfile`, `flutter analyze --no-pub`, `flutter test --no-pub`, включая реальные API RPC-тесты к изолированному серверу; из корня `python3 scripts/check_dart.py --check`. Проверка: контракт и существующие клиенты работают; runtime hot reload не требуется для одних generated-изменений.
- [x] 5.3 Обновить `docs/testing.md` фактическими результатами новых проверок, проверить `git diff --check` и итоговый diff своего изменения. Проверка: нет рефакторинга, перенумерации, обновлений зависимостей, секретов и включённых чужих правок; непроверенные конфигурации перечислены явно.


## Итог реализации (2026-11-15)

Все 19 задач завершены. Сопоставление с кодом и текущие доказательства приведены
в docs/testing.md, раздел «Завершение add-offline-sync-reads»:
backend/release gate 526/526 без skips, Flutter 727 с обеими native RPC E2E и HPT,
format/clang-tidy, Dart analyze/format, повторная генерация и strict validation.
Проверки использовали существующий pinned HPT из build/publication-deps;
Dart MCP с неподходящим глобальным SDK заменён CLI проектного SDK.
Открытых задач и блокеров нет. Основные specs ещё не синхронизировались,
изменение остаётся активным; коммит, публикация и развёртывание не выполнялись.


## Согласование перед архивированием (2026-11-15)

Восемь итоговых требований синхронизированы с api-transport, archive-research
и conference-browsing. Все прежние требования, сценарии и Purpose сохранены.
Явно закреплены независимость страниц и прежняя защита при замене файлов.
Строгая валидация изменения и всех specs прошла, чек-лист 19/19.
Предыдущая запись об активном состоянии выше относится к завершению реализации;
изменение переносится в archive/2026-11-15-add-offline-sync-reads.
