# Tasks

## 1. Воспроизводимые проверки и контракт

- [x] 1.1 В `apps/backend/tests/` заменить общие временные пути на изолированные каталоги с JAM-файлами внутри; проверить отсутствие остаточных файлов и успешный повтор `ctest --test-dir build/backend --parallel 4 --repeat until-fail:10 --output-on-failure`.
- [x] 1.2 В корневом CMake и `apps/backend/CMakeLists.txt` выделить единые настройки warnings, ASan/UBSan и TSan для core/tests/executable, запретить конфликтующие режимы; проверить compile_commands и запуск существующих тестов в отдельных build-directory.
- [x] 1.3 Добавить отчёты покрытия собственного backend-кода и Flutter, исключая generated/third_party/tmp; сохранить baseline lines/branches и список непокрытых компонентов в документации проверок, проверить воспроизводимость отчётов.
- [x] 1.4 В `cmake/deps.cmake` централизовать текущие зависимости FFIDO, выбрать и зафиксировать совместимые gRPC/protobuf/protoc/Dart-plugin; проверить configure и link небольшого generated RPC на macOS/Linux без Cellar-путей и обновления несвязанных версий.
- [x] 1.5 Создать `contracts/ffido/v1/ffido.proto` со всеми RPC и типами из design, включая Timestamp, sorting, ErrorDetails, pagination, operation_id и локальный статус сохранения; проверить descriptor и генерацию C++/Dart, покрыть мэппинг Unicode/Empty/enum/error-details контрактными тестами.
- [x] 1.6 Добавить contracts-library в CMake и воспроизводимую Dart-генерацию, описать команды и совместимые версии в документации; повторная генерация должна давать идентичные файлы, изменение proto должно пересобирать потребителей.

## 2. Выбор JAM и ограниченный разбор

- [x] 2.1 Исправить `apps/backend/src/EchoAreaConfig.cpp` для используемых HPT-строк, filename/type/default encoding и обязательных полей; добавить fixtures для tabs, malformed lines и отсутствующих значений, ошибки не должны молча давать разрешённую базу.
- [x] 2.2 В backend создать единый resolver разрешённых конференций с проверкой корня/открытых дескрипторов; тестами подтвердить различие ID и filename, запрет traversal/symlink-race и исключение Passthrough/Squish.
- [x] 2.3 Исправить JAM index reader в `apps/backend/include/JamMessageBase.h`: сохранять физические слоты и deleted markers, проверять размер индекса; тестами подтвердить сохранение номеров после reopen и удаления в начале/середине/конце при BaseMsgNum != 1.
- [x] 2.4 Исправить allocation/offset/narrowing проверки и little-endian parsing JAM; добавить негативные fixtures для усечений/signature/revision/overflows/огромных длин, проверить ASan/UBSan и ограниченную память.
- [x] 2.5 Восстанавливать из headers даты, attributes и reply-поля; применять CHRS/default_encoding и безопасный Unicode preview; round-trip тесты должны сохранять данные и русский текст в UTF-8/cp866.
- [x] 2.6 Исправить append-slot/ActiveMsgs/delete semantics; тестами с HPT-подобными deleted slots подтвердить отсутствие перезаписи живых сообщений и корректность счётчиков после reopen.
- [x] 2.7 Добавить bounded fuzz harness и corpus JAM parser, описать запуск и ограничения в `apps/backend/README.md`; sanitizer-прогон corpus должен завершаться без crash/UB/unbounded allocations.

## 3. Синхронизация с HPT и устойчивость записи

- [x] 3.1 Зафиксировать версии локальных HPT/SMAPI и фактический sharing/locking режим; добавить тестовый отдельный процесс SMAPI/HPT на искусственной базе, доказать конфликт блокировки первого байта .jhr с POSIX fcntl на Linux/macOS и описать предпосылки совместимости.
- [x] 3.2 В backend реализовать владельца дескрипторов и process mutex по физической базе для read/open/write/close; проверить concurrent read/write и alias-пути, отсутствие снятия lock закрытием постороннего fd.
- [x] 3.3 Добавить обязательный wrapper HPT и shared/exclusive coordination lock на полный open/read/write/close lifecycle, затем совместимые file read/write locks с deadline/cancellation/backoff и instance lock одного backend; тестами подтвердить timeout без мутации, освобождение lock после ошибки/завершения процесса и независимый доступ к разным базам.
- [x] 3.4 Перечитывать заголовки/индекс под lock и учитывать generation при replacement; тестами подтвердить отказ от stale snapshot и корректное обнаружение замены базы, описать окно обслуживания для pack.
- [x] 3.5 Добавить SQLite operation journal и durable intent для JAM append с fsync и уникальным FTN MsgID; инъекциями short-write/ENOSPC/fsync-failure проверить порядок публикации и отсутствие ложного успеха.
- [x] 3.6 Реализовать recovery полностью записанного и доказуемо незавершённого собственного append; restart-тесты на каждом этапе должны сохранять старые подтверждённые сообщения и завершать или откатывать только собственные изменения.
- [x] 3.7 Реализовать quarantine при неопределённом хвосте/изменениях HPT/generation; тесты после внешнего append должны подтвердить отсутствие truncate/потери чужих данных, документация должна описывать ручное восстановление.
- [x] 3.8 Добавить HPT round-trip чтения/экспорта русских сообщений, FTN MsgID и reply headers, а также конкурентный HPT/backend сценарий через обязательный общий wrapper, включая защиту от stale cached close SMAPI; успех требует согласованных .jhr/.jdt/.jdx и всех подтверждённых сообщений, без production FTN-путей.

## 4. Пользователи и SQLite

- [x] 4.1 В `apps/backend/src/storage/sqlite_store.cpp` добавить versioned schema migration, WAL/foreign_keys/busy_timeout и проверку prepare/bind/step; тесты должны покрывать BUSY/I/O, rollback, string_view подстроку/embedded NUL и повторную инициализацию.
- [x] 4.2 Мигрировать read_status к структурному ключу user/conference/message/generation: сохранить все старые отметки в backup и начать новую прочитанность заново, сохранив bookmarks/history; тестами подтвердить полноту backup, rollback/повтор миграции и отсутствие коллизий разных конференций.
- [x] 4.3 Добавить заранее назначенные профили и token digests с expiry/revocation, локальные provision/revoke команды; тесты должны подтвердить выдачу, отсутствие plaintext в DB/logs, отзыв и связь с валидным FTN-адресом, README должен описывать локальное использование.
- [x] 4.4 Заменить активный JWT-путь проверкой opaque bearer и request-context; тестами подтвердить отсутствие доступа/побочных эффектов при missing/unknown/expired/revoked токенах и игнорирование подмены user_id/from_address.
- [x] 4.5 Обеспечить одинаковый доступ к разрешённым JAM areas и изоляцию профиля/bookmarks/history/read_status; multiuser-тесты должны доказать, что действия A не меняют состояние B.
- [x] 4.6 Реализовать персональную прочитанность/историю и реальные total/unread/date counters; сервисные тесты должны покрывать повтор чтения, deleted slots, filtered total и ошибки metadata без молчаливого успеха.

## 5. Сервисы сообщений и gRPC server

- [x] 5.1 Исправить conference/message services для resolver, profile sender, UTC-дат, корректной пагинации и NOT_FOUND; unit/service-тесты должны покрывать пустые базы, границы страниц, filter/sort и GetConference.
- [x] 5.2 Реализовать в CreateMessage проверку родителя/FTN-адреса/размеров и идемпотентность через operation journal; тесты должны покрывать одновременный повтор, потерю ответа, restart и ALREADY_EXISTS для другого payload.
- [x] 5.3 Реализовать GetThread с visited-set, pagination и reply references; тестами покрыть ветвление, отсутствующего родителя, циклы и deleted messages, сохранив существующие правила обычного ответа.
- [x] 5.4 Добавить gRPC adapter с общей auth-проверкой, error-details mapping, TLS, RPC deadlines и resource limits; реальные localhost client/server тесты должны проверить все RPC и negative статусы, без утечки paths/SQL/секретов.
- [x] 5.5 Исправить lifecycle в `apps/backend/src/main.cpp`: bind-error exit, безопасный shutdown, draining начатого commit; process-тесты должны покрывать SIGINT/SIGTERM при idle/lock-wait/write и bounded completion.
- [x] 5.6 Удалить REST/legacy/static-file serving и сделанные ненужными HTTP/JWT зависимости/DTO привязки; проверить отсутствие старых endpoint и сборку всех потребителей, обновить `apps/backend/README.md` и безопасный config template под новый API.

## 6. Flutter client и персональные экраны

- [x] 6.1 В `apps/frontend/lib/api/` внедрить native/web gRPC transport и typed mapping ошибок вместо HTTP/JSON; тестами покрыть Empty/Unicode/field-details/status/deadline/cancel, безопасные bounded retries и закрытие канала.
- [x] 6.2 Добавить настройку endpoint и ввод/замену/удаление выданного токена с хранением в памяти; session epoch должен отменять старые операции, widget-тесты должны подтвердить отсутствие токена в SharedPreferences и данных предыдущей сессии.
- [x] 6.3 Перевести conference/message repositories на внедряемый transport и generated types; repository-тесты должны покрыть все RPC, правильного получателя ответа, operation_id при retry и ошибки отправки с сохранением текста.
- [x] 6.4 Разделить/инвалидировать кеш по endpoint/session/schema и обновить fallback по gRPC-статусам; тестами сохранить действующие cache/debounce/last-query-wins сценарии и добавить смену пользователя/сервера при позднем ответе.
- [x] 6.5 Подключить profile/bookmarks/history экраны к реальному API, убрать демонстрационные данные и неподдерживаемую статистику; widget-тесты должны покрыть loading/empty/error/success и закрытие экрана во время RPC.
- [x] 6.6 Подключить чтение/списки/threads/отправку message screen к RPC и корректной прочитанности; widget-тестами проверить double-submit, неопределённый результат/retry, ошибки и отсутствие заявления о доставке в FidoNet.
- [x] 6.7 Удалить ставшие ненужными HTTP imports/dependencies, обновить документацию клиента; `flutter pub get`, `flutter analyze --no-pub`, `flutter test --no-pub` должны пройти из `apps/frontend` без обновления несвязанных пакетов.

## 7. Web, платформы и локальный build.sh

- [x] 7.1 Добавить локальную конфигурацию/команду запуска Envoy gRPC-Web с TLS/CORS/metadata/limits без Docker; browser integration tests должны подтвердить авторизацию, Unicode, Empty, ошибки полей, trailers и отказ чужому origin, описать запуск в README.
- [x] 7.2 Проверить и скорректировать сетевые разрешения Android release и macOS sandbox, native/web channel selection; platform smoke matrix должна проверить RPC в production-сборках Android/iOS/Windows/Linux/macOS/Web или явно перечислить недоступные окружения.
- [x] 7.3 Создать корневой `build.sh` build/test/check/format/proto/coverage/asan-ubsan/tsan, BUILD_DIR/JOBS и install target по design; проверить запуск из разных cwd, код возврата при ошибках и отсутствие маскировки missing-tools.
- [x] 7.4 Добавить scoped clang-format/clang-tidy конфигурацию и команды без массового рефакторинга/generated formatting; check должен быть read-only и анализировать core/tests с настоящим compilation database, README должен содержать выполненные команды.

## 8. Сквозная приёмка

- [x] 8.1 Выполнить сквозной сценарий два пользователя → список → чтение → ответ → повтор отправки → HPT export → bookmarks/history/profile через native gRPC и браузер gRPC-Web; зафиксировать результаты и соответствие каждому сценарию delta-specs.
- [x] 8.2 Выполнить конкурентную/fault/restart матрицу и ASan/UBSan/TSan на Linux/macOS с инструментированным core; отчёт должен отделять пройденные проверки от недоступных платформ/инструментов, без подавления выявленных ошибок.
- [x] 8.3 Проверить coverage gates из design: общий код ≥90% строк, backend ≥85% ветвей; JAM/auth/idempotency/recovery ≥95% строк и ≥90% ветвей; все критические сценарии должны иметь содержательные тесты независимо от процента.
- [x] 8.4 Выполнить корневые configure/build/CTest, клиентские pub get/analyze/test и release Web, генерацию контрактов и проверку финального diff; не должно быть runtime FTN/SQLite/uploads/секретов/кешей и несвязанных изменений.
- [x] 8.5 Проверить инструкции migration/backup/recovery на искусственной базе и зафиксировать ограничения HPT pack/sharing; завершение требует воспроизводимого локального запуска backend/native/Web без REST и без обещания неподтверждённой платформенной проверки.
