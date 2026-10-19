# Design

## Context

Мотивация и согласованная область изменения — в `proposal.md`. Пользователь подтвердил все нынешние платформы, полную замену REST, заранее выданные токены и FTN-адреса, одинаковый доступ к конференциям, один backend на локальном диске рядом с HPT, Linux/macOS и только локальные сборку/проверки.

### Результаты анализа исходников

Ниже — наблюдения по текущей рабочей версии, а не утверждение о завершённом аудите всего проекта. Ссылки относительно корня; номера строк относятся к версии перед реализацией.

| Приоритет | Место | Наблюдение и последствие | Проверка исправления |
|---|---|---|---|
| P0 | `apps/backend/src/http/router.cpp:21` | Все обработчики получают личность из `X-User-Id`, JWT не проверяется. Возможна подмена владельца метаданных. | Нет токена/чужие metadata/отозванный токен: RPC не имеет побочных эффектов. |
| P0 | `apps/backend/src/service/message_service.cpp:35,108,174` | Путь строится из входного conference_id; нет сопоставления с разрешённым EchoArea.filename. README обещает защиту пути, которой в этом пути вызовов нет. | Неизвестные ID, traversal, симлинки, различающиеся имя/файл. |
| P0 | `apps/backend/src/main.cpp:52,103` | Логируется префикс JWT-секрета; `set_base_dir(".")` включает раздачу рабочей директории. | Секреты отсутствуют в логах; HTTP-раздача удалена. |
| P0 | `apps/backend/src/service/message_service.cpp:207`; `include/JamMessageBase.h:637` | Mutex только вокруг записи в экземпляре сервиса, ключ по basename; чтение без него, межпроцессных блокировок нет. Файлы и заголовок обновляются отдельно. | Чтение/запись/HPT, alias одного файла, timeout, отказ на каждом этапе. |
| P1 | `apps/backend/include/JamMessageBase.h:466,535,665,723` | Open исключает удалённые индексные записи, ReadMessage индексирует по номеру; AddMessage выбирает слот через ActiveMsgs, хотя при удалениях число активных не равно числу слотов. | Удаления в начале/середине/конце, BaseMsgNum != 1, добавление после HPT-удаления. |
| P1 | `apps/backend/include/JamMessageBase.h:580,831` | Длины из файла используются для allocations до проверки размера файла/лимита; narrowing tellp и размеров в uint32_t не проверен. | Усечения, гигантские длины, переполнения и границы 32-bit формата. |
| P1 | `apps/backend/src/service/message_service.cpp:95,152,270` | Чтение статуса по bare ID, запись по склеенному ID. | Read→list и одинаковые номера в разных конференциях/у разных пользователей. |
| P1 | `apps/backend/src/storage/sqlite_store.cpp:357` | GetUnreadCount возвращает число прочитанных; ошибки sqlite3_step ряда чтений превращаются в пустой результат; bind string_view с длиной -1 предполагает NUL-терминацию. | Реальные unread, I/O/BUSY, string_view подстроки и embedded NUL. |
| P1 | `apps/backend/src/storage/sqlite_store.cpp:157` | WAL не включается явным PRAGMA; foreign keys и busy_timeout не настроены. | Проверка режима/ограничений и конкуренции соединений. |
| P1 | `apps/backend/src/service/message_service.cpp:217,223,230,277` | Автор/адрес hardcoded, MsgID по секундам; отсутствующий родитель не отклоняется, GetThread — заглушка. | Профили, несколько отправок в секунду, invalid reply, cycles. |
| P1 | `apps/backend/include/JamMessageBase.h:535` | ReadMessage не восстанавливает атрибуты/даты/числовые reply-поля; service отдаёт сырой текст без конвертации, preview может разрезать UTF-8. | Round-trip headers, CHRS/default encoding, Unicode preview. |
| P1 | `apps/backend/src/main.cpp:23` | Signal handler вызывает logger, не останавливает сервер; сигналобезопасность не обеспечена. | SIGINT/SIGTERM при idle/записи/ожидании lock. |
| P1 | `apps/frontend/lib/repositories/conference_repository.dart` | Кеш общий для сервера/пользователя; смена токена не изолирует данные и поздние результаты. | Смена identity/endpoint при незавершённом RPC. |
| P1 | `apps/backend/tests/integration/test_jam_write.cpp:45` | Все JAM-тесты используют одинаковый префикс; cleanup удаляет каталог, но sibling `.jhr/.jdt/.jdx/.jlr` остаются. Параллельный CTest небезопасен. | Уникальный temp-directory с файлами внутри, parallel repeat. |
| P2 | `apps/backend/src/service/conference_service.cpp:25` | total до фильтрации, счётчики/даты — заглушки, filename игнорируется. | Filter/page/count consistency. |
| P2 | `apps/frontend/lib/repositories/conference_repository.dart`; `lib/pages/{profile_screen,bookmarks_screen,history_screen}.dart` | getConferenceById вызывает отсутствующий маршрут; персональные экраны показывают заглушки. | Живой RPC и widget-тесты на серверные данные. |
| P2 | `apps/backend/CMakeLists.txt:105–118` | Warnings и sanitizers только на executable, core/tests не инструментированы; ASan/TSan могут включаться одновременно. | Проверка compile_commands для core/tests, раздельные сборки. |

Базовая проверка на текущем macOS: CMake configure/build и 55 CTest успешны, Flutter analyze без замечаний и 139 тестов успешны. Осталось предупреждение CMP0135. Покрытие строк/ветвей не измерено; существующие тесты не доказывают безопасность HPT-конкуренции. Linux, нативные release-сборки, интеграция HPT и gRPC на этом этапе не проверялись.

## Goals / Non-Goals

**Goals:** один источник контракта; проверяемая идентичность; сохранность подтверждённых JAM-записей; ограниченные ресурсы; регрессионная защита найденных дефектов; воспроизводимая локальная проверка.

**Non-Goals:** распределённое хранилище, несколько backend, NFS/SMB, индивидуальные ACL, регистрация/пароли, Squish, REST-мост, доставка сообщений до конечного узла, Docker и CI. Гарантия не распространяется на стороннюю утилиту, игнорирующую согласованные блокировки; упаковка/пересоздание файлов HPT выполняется в согласованном окне обслуживания.

## Decisions

### 1. Контракт и транспорты

`contracts/ffido/v1/ffido.proto` — общий источник. Unary RPC для List/GetConference, List/Get/CreateMessage, MarkRead, GetThread с пагинацией, List/Add/RemoveBookmark, List/ClearHistory и GetProfile. Сохраняются правила обычного ответа из `message-replies`; «ответ всем» не получает фиктивную многополучательную семантику.

C++ server использует gRPC C++; Flutter native — grpc Dart, Web — grpc-web transport через Envoy с ограниченным CORS. Все вызовы имеют deadline, пагинация limit 1–100, тела и объём ответа ограничены. `google.protobuf.Timestamp`, enum сортировки с отклонением неизвестных значений, Empty для операций без данных. `ErrorDetails` с violations полей — собственный тип в контракте, передаваемый в бинарной metadata; Web-шлюз открывает нужные trailers/metadata. Карта ошибок: validation→INVALID_ARGUMENT, auth→UNAUTHENTICATED, missing→NOT_FOUND, collision→ALREADY_EXISTS, resource→RESOURCE_EXHAUSTED, busy→UNAVAILABLE, damaged base→DATA_LOSS, I/O→INTERNAL. Публичные ошибки не раскрывают пути/SQL/секреты.

Из CMake генерируется отдельная `ffido_contracts` в build-directory, как `ivrws_contracts_lib`; Dart-генератор воспроизводимо обновляет выделенный generated-каталог, проверка требует отсутствие расхождений после повторной генерации. Версии protoc/runtime/plugin фиксируются совместимым набором. Поля не перенумеровываются; удалённые номера резервируются. REST/legacy и статическая раздача удаляются вместе с HTTP-зависимостью, если больше нет потребителей.

Альтернативы: сохранение REST увеличивает поверхность и противоречит решению пользователя; native gRPC в браузере не поддерживает нужный сценарий; серверный REST→gRPC мост не требуется. Envoy добавляет локальный процесс, но позволяет одинаковую бизнес-логику API. Источник: https://grpc.io/docs/platforms/web/quickstart/.

### 2. Предварительная выдача идентичности

Выбрать непрозрачные криптографически случайные bearer-токены: сервер хранит SHA-256 digest и token_id, user_id, optional expires_at/revoked_at; полный токен показывается администратору только при локальной выдаче. Профиль (имя, валидный FTN-адрес) назначается заранее. Локальная административная команда provision/revoke работает с metadata SQLite, без публичного RPC регистрации. Это явно выбранная реализация понятия «заранее выданный токен», а не предположение о формате уже существующих токенов. Тестовые токены создаются только в fixtures.

Interceptor/единый вход адаптера создаёт неизменяемый request-context после проверки токена и активного профиля. user_id/from_address не принимаются как источник доверия. Доступ общий ко всем разрешённым JAM areas; Passthrough/unsupported типы исключаются. Метаданные всегда фильтруются по request-context. Административные операции сериализуются с backend через SQLite-транзакции, не считаются вторым процессом backend.

TLS обязателен в production, plaintext допускается только в явно включённом loopback dev-режиме. Токен в UI вводится пользователем, сессия по умолчанию хранит его в памяти; автоматическое долговременное сохранение в SharedPreferences не вводится. Повторный запуск требует ввода токена. Если позже потребуется постоянное хранение, это отдельное решение с платформенным secure storage. JWT не нужен для немедленного отзыва и предварительной выдачи; текущая JWT-генерация удаляется из активного пути.

### 3. Выбор базы и процессные блокировки

Единый каталог разрешённых конференций сопоставляет ID с EchoArea.filename и типом. Разрешённый корень задаётся конфигурацией; файл из EchoArea допускается только внутри него (включая проверенные абсолютные пути). Открытие через проверенные directory/file descriptors и запрет симлинк-подмены защищает от TOCTOU, а не только от строкового `..`. Тесты проверяют inode и реальный открытый путь. Ошибка конфигурации fail-closed, без молчаливого принятия некорректных обязательных параметров.

По локальным исходникам Husky:
- `.../smapi/src/api_jam.c`, Jam_Lock: lock на HdrHandle, offset 0, length 1;
- `.../huskylib/src/locking.c:477`: POSIX `fcntl(F_SETLK, F_WRLCK)`, unlock тем же диапазоном;
- upstream для сверки: https://github.com/huskyproject/smapi/blob/c2fc9ecb0dd1ec8909e9e9709bfdd0031d5b9bf2/src/api_jam.c.

Backend использует тот же POSIX диапазон первого байта `.jhr`; чтение получает совместимую read-lock, запись write-lock, обе охватывают открытие согласованных companion files/refresh/snapshot или целую запись. Внутри процесса mutex по физической идентичности базы покрывает ВСЕ операции, включая чтение, открытие и закрытие любых дескрипторов этой базы. POSIX record locks принадлежат процессу, а закрытие другого fd того же inode может снять lock; отдельные JamMessageBase без общего владельца дескрипторов запрещены. Реестр не растёт по произвольным RPC-ID; aliases объединяются. Счётчики заголовка перечитываются после lock, stale snapshot не используется для записи.

Ожидание — nonblocking fcntl с ограниченным backoff, deadline и отменой, без глобального mutex на ожидании. Дополнительная process-instance lock исключает второй backend той же конфигурации. Это не замена JAM lock HPT. `flock` на отдельном sidecar не выбран: он не взаимодействует с fcntl HPT.

### 4. Формат, запись и восстановление

Разбирать little-endian поля явно, не зависеть от native struct layout/endianness. Сохранять все `.jdx` слоты, отдельно отмечать deleted; физический JAM номер определяется BaseMsgNum+слот, а не ActiveMsgs. Добавление — append-слот по длине индекса, с checked arithmetic; ActiveMsgs обновляется как число живых. Проверять размеры каждого файла, signature/revision, offsets+length, message_number, subfield limits и 32-bit bounds до allocations. Read-only доступ не требует записи companion files. Восстанавливать даты, attributes, numeric reply fields; хранить FTN MsgID отдельно от локального номера.

Прямой reader/writer сохраняется с исправлениями. Замена на SMAPI не выбрана автоматически: там есть глобальные состояния, и библиотека сама по себе не решает process/thread ownership или rollback. SMAPI используется как совместимый внешний участник в тестах.

Перед мутацией сохраняется durable intent в отдельном журнале операций SQLite: canonical base identity/generation, исходные размеры и base header, будущий MsgID/номер, payload hash и operation_id. SQLite journal synchronous=FULL; JAM запись идёт под lock: текст/заголовок, fsync, индекс, fsync, header, fsync, затем commit результата в журнале. `flush()` недостаточен. Клиент получает результат только после устойчивого commit. Уникальный FTN MsgID строится из назначенного адреса и случайного компонента, а не unix-секунды.

Recovery под той же JAM lock сравнивает journal, generation/inode, диапазоны и фактически записанное сообщение. Полностью записанную операцию завершает; точный незавершённый собственный append может откатить к сохранённым размерам/header только при доказанном отсутствии внешних изменений. Если HPT успел дописать, файлы заменены/упакованы или ownership хвоста не доказан — НЕЛЬЗЯ truncate/перезаписывать header: база переводится в read-only/quarantine с диагностикой и процедурой ручного восстановления. Это безопаснее слепого rollback рядом с внешним writer. Recovery не обещает глобальную атомарность JAM+SQLite.

После начала файловой мутации отмена RPC не прерывает commit произвольно; результат сохраняется для повтора. До мутации отмена/deadline не имеет побочных эффектов. Персональная прочитанность находится только в SQLite, `.jlr` не меняется для пользователей приложения.

### Дополнение: обязательная координация lifecycle HPT

Проверка установленных SMAPI 2.5.0/2.5.2 на искусственных базах выявила
cached-header write в JamCloseArea: после append второго сообщения stale close
возвращает ActiveMsgs с 2 на 1 даже при чужом first-byte lock. Пользователь
выбрал общий wrapper вместо изменения внешней SMAPI/HPT.

Все HPT-команды, обращающиеся к этим JAM-базам, SHALL запускаться через
`run_hpt.py` с той же конфигурацией FFIDO. Wrapper удерживает exclusive `flock`
от запуска HPT до окончания его процесса. FFIDO удерживает shared `flock`
координационного файла вокруг catalog open и каждого read/write/recovery,
затем получает process mutex и first-byte POSIX lock конкретной JAM-базы.
Каждый shared lease использует отдельный open-file description, чтобы
завершение одной операции не снимало блокировку другой. Это сохраняет
независимость разных баз внутри FFIDO, но исключает перекрытие полного
HPT lifecycle с JAM-операциями backend. Порядок: coordination → physical
mutex → byte lock → SQLite; ожидание coordination не удерживает JAM/SQLite.

Пути в конфигурации разрешаются относительно её файла одинаково в backend
и wrapper. Координационный файл нельзя удалять/заменять при работающих
процессах. Запуск HPT в обход wrapper не поддерживается. Pack/replacement
по-прежнему требует окна обслуживания и переоткрытия backend-каталога.

### 5. Метаданные и семантика API

Ключ read_status — `(user_id, conference_id, jam_message_number)` с generation при пересоздании базы; без склеивания строк. По уточнённому решению пользователя все старые отметки прочитанности сохраняются в отдельной backup-таблице; новая прочитанность начинается заново. Старая схема не сохраняла generation/FTN MsgID, а прежняя индексация могла смещать номера после удаления, поэтому даже синтаксически корректный ключ не доказывает личность сообщения. Закладки и история сохраняются. Backup выполняется транзакционно и идемпотентно, без изменения JAM. Deleted slots не учитываются в total/unread. После pack/replacement generation меняется и старые локальные ссылки/прочитанность не прикладываются к другому сообщению. FTN MsgID доступен отдельно для сопоставления.

SQLite: явные WAL, foreign_keys, busy_timeout, транзакции, проверка всех prepare/bind/step результатов; string_view передаётся с явной длиной, включая проверки INT_MAX. Ошибки не превращаются в false/empty. Чтение полного сообщения сначала читает snapshot JAM, затем транзакционно обновляет read/history; ошибка metadata возвращается вызывающему коду. Не держать SQLite lock во время ожидания JAM; закрепить порядок блокировок и тестировать отсутствие deadlock.

Идемпотентность CreateMessage по `(user_id, operation_id)` и hash содержимого, с сохранением результата в журнале. Retry после перезапуска получает тот же результат; изменение payload под прежним ключом отклоняется. Родитель должен существовать в той же базе. Threads строятся по MsgID/ReplyID и numeric headers с visited-set и pagination bounds; даты UTC, UTF-8 preview не режет codepoint. CHRS применяется при чтении; при отсутствии — configured default_encoding. Отправка формирует HPT-совместимые отдельные kludge-поля, line endings и CHRS. Точные fixtures подтверждают реальный HPT round-trip.

### 6. Клиент и жизненный цикл

Внедряемый transport/repositories вместо singleton, который может игнорировать новый канал/токен. Один владелец канала и session epoch; endpoint/token change отменяет текущие RPC, удаляет кеш и игнорирует поздние результаты. Domain models отделены от protobuf-мэппинга; кеш остаётся локальным JSON с версией и fingerprint endpoint/session, без токена. Старые кеш-ключи инвалидируются. Существующие правила last-query-wins/debounce/replies сохраняются.

Профиль, история, закладки и message screen подключаются к RPC вместо заглушек. Для CreateMessage UI сохраняет operation_id при неопределённом результате, не создаёт новый при retry; новая редактированная отправка — новая операция. Не заявлять «доставлено»: успех означает «сохранено в базе». Не выдумывать серверную статистику для полей, которых нет в контракте.

SIGINT/SIGTERM обрабатывает безопасный механизм ожидания сигналов/уведомления основного потока без spdlog в handler. Shutdown прекращает приём, ограниченно ждёт начатые commit, закрывает канал/хранилище и снимает locks. Ошибка bind/listen возвращает ненулевой exit status.

### 7. Локальная сборка и тестовый охват

Из `ivrws` переносится подход, а не его toolchain/посторонние зависимости: корневой CMake включает backend, core-library отдельно от main, contracts-library отдельно от сервисов, install target, BUILD_TESTING, compile_commands. `cmake/deps.cmake` централизует только зависимости FFIDO, фиксирует существующие версии; системный поиск использует совместимые версии и корректные exported targets, без Cellar путей. Генераторы проверяются при configure. В `ivrws` Docker-ветка содержит подозрительные imported targets gRPC/protoc без корректного executable location — её не копировать.

Корневой `build.sh`: build/test/check/format/proto/coverage и отдельные asan-ubsan/tsan builds, BUILD_DIR и JOBS (по умолчанию 4), работа независимо от cwd, configure/build/test через корневой проект. Frontend-команды выполняются из `apps/frontend`. check не меняет файлы и не считает отсутствие required formatter/analyzer успехом. Форматирование только выбранных исходников, generated/third_party/tmp исключены. ASan/UBSan и TSan несовместимы в одной сборке; core, tests и executable инструментируются согласованно.

Покрытие: baseline и отчёты backend lines/branches и Flutter lines, исключая generated/third_party/platform boilerplate. Цель для собственного кода: ≥90% строк обоих компонентов и ≥85% ветвей backend; для JAM/auth/idempotency/recovery ≥95% строк и ≥90% ветвей. Все критические сценарии specs обязательны независимо от процента. Недостижимые ветви требуют конкретного объяснения в отчёте, а не blanket exclusions. Это целевые критерии apply, а не утверждение о текущем покрытии.

Матрица: unit (parser/config/domain/auth/SQLite/mappers/repositories), integration (JAM fixtures и HPT/SMAPI в отдельном процессе), concurrency (barriers, read/write, lock-timeout, no sleeps-as-assertions), fault injection (short write, ENOSPC, fsync failure, kill на каждом этапе), fuzz (bounded parser corpus), real gRPC localhost и Web через шлюз, widget (loading/error/late responses/session change), platform release smoke. Linux/macOS проверяют HPT/file locks и sanitizer builds; недоступные платформы явно остаются непроверенными. Temporary files изолированы для ctest --parallel.

## Risks / Trade-offs

- [HPT-сборка может отключать sharing/locking] → SMAPI проверяет `mi.haveshare`; fixture должен подтвердить реальные конфликтующие locks, при неподтверждённом окружении запись не включать.
- [Упаковка HPT меняет inode/нумерацию] → окно обслуживания и generation; не обещать прозрачную работу при несогласованной замене файлов.
- [Recovery после вмешательства HPT] → только доказуемый rollback, иначе quarantine; никакого автоматического удаления чужих данных.
- [fsync latency и serial access одной базы] → ограниченный RPC concurrency, независимость баз, измерения без ослабления durability.
- [Web metadata и CORS] → настоящий browser smoke через Envoy; native tests не заменяют его.
- [Большая миграция] → последовательные этапы tasks, проверка каждого слоя, совместное переключение клиента/сервера.
- [Проценты покрытия не доказывают отсутствие гонок] → обязательные сценарии конкуренции/сбоев, sanitizer/fuzz результаты отдельными отчётами.

## Migration Plan

1. Сохранить baseline и резервные копии SQLite/конфигурации; реальные JAM не менять при разработке.
2. Внедрить core/storage fixes и тесты на искусственных базах, затем contracts/server/client.
3. Остановить backend и HPT для согласованной резервной копии; мигрировать SQLite schema/read keys/generation, выдать пользователям токены и назначить адреса локальной командой.
4. Настроить TLS/endpoint, allowed roots, HPT-compatible locking, лимиты и локальный gRPC-Web шлюз; прогнать staging round-trip на копии базы.
5. Запустить backend/HPT и обновлённые клиенты вместе, проверить native/Web и персональные данные. REST не остаётся рабочим fallback.
6. При откате остановить процессы. Предыдущую конфигурацию/API можно восстановить с согласованной копией SQLite; новые JAM-сообщения не удалять слепым восстановлением старой базы. Необратимый откат данных выполнять только с проверенной консистентной резервной копией в окне обслуживания.

## Open Questions

Перед apply нужно зафиксировать фактические версии HPT/SMAPI и совместимый набор protoc/gRPC/Dart plugin, доступный на целевых машинах. Это техническая проверка в конкретных задачах, не изменение выбранной архитектуры. TLS-hostnames, пути и токены остаются локальной deployment-конфигурацией; их не включать в артефакты.
