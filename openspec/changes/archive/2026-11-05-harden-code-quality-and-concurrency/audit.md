# Аудит кода FFIDO, 5 ноября 2026

## Снимок и границы

Основа: HEAD `71ca4ffa50136234224483d8f326bbeef45af8a1` плюс текущее незакоммиченное рабочее дерево. До аудита уже изменены AGENTS, карточка конференции, её widget-тесты, персональные экраны, `docs/testing.md`, основная спецификация conference-browsing и добавлен архив исправления счётчиков. Эти изменения сохранены и входят в проверяемое состояние; результаты нельзя приписывать чистому HEAD.

Выполнены инвентаризация исходников монорепозитория, чтение инструкций/README/CI/команд проверки, обзор protobuf и контрактных тестов, прицельное чтение критических цепочек FE/BE и проверка штатных наборов. Инвентаризация `git ls-files '*.cpp' '*.hpp' '*.h' '*.dart' '*.py'` содержит 429 файлов. Это **не означает построчного ревью всех 429 файлов**, формального доказательства отсутствия ошибок или полного аудита зависимостей. Generated-код и сторонние библиотеки рассматриваются как зависимости и проверяются существующими контрактными тестами.

Основной фокус: авторизация и локальные секреты; смена сессий и отмена RPC; физические владельцы JAM, алиасы, recovery, SQLite; каталог и статистика; архивный поиск и MCP stdio; обновления и platform lifecycle. Разбор найденных межоперационных дефектов углублён воспроизводителями на искусственных данных. Проектный исполняемый код не изменялся.

## Подтверждённые дефекты

### F1 — P1: падение recovery при смене формата приватной области

- Источник: `apps/backend/src/storage/jam_writer.cpp:109–112`, `jam_catalog.cpp:182–184,287–293`.
- Условие: незавершённая операция относится к прежней JAM-области, а текущий каталог содержит тот же ID приватной области с неподдерживаемым форматом, например Squish. Каталог допускает такую область с `files=nullptr`; `Resolve` возвращает `kUnsupportedFormat`.
- Причина: ветка ошибки `Recover` проверяет наличие ID, но без проверки `files` вызывает `Quarantine(*entry->second.files, snapshot)`.
- Доказательство: отдельный C++ executable собран по текущей compilation database с текущей `libfidoback_lib.a`; временные каталог и SQLite, `AreaKind::kLocal`, формат Squish, pending snapshot того же ID. CLI LLDB: `EXC_BAD_ACCESS`, адрес `0x285`; `JamWriter::Quarantine` на строке 92, `owner=0x0`; вызывающий frame — `Recover:112`.
- Последствие: падение восстановления, потенциально блокирующее запуск backend; не удалённая область, а сохранившийся ID с изменённым форматом. Воспроизводитель моделирует pending snapshot непосредственно, не полный перезапуск сервера с сохранённым журналом.
- Исправление: отдельно обрабатывать отсутствующего физического владельца, устойчиво отмечать отказ операции без обращения к файлам; проверять ошибку метаданных. Постоянная регрессия должна пройти через настоящий сохранённый журнал и `RecoverAll`, включая удалённую область и ошибки SQLite.

### F2 — P1: позднее чтение секрета отменяет локальный выход

- Источник: `apps/frontend/lib/api/session_store.dart:84–100`.
- Условие: `restore` проверил tombstone и ждёт `store.read`; завершился выход без сети; затем пришёл прежний секрет.
- Причина: после `await store.read` не проверяются tombstone, поколение операции и актуальный endpoint. Старый секрет передаётся в `configure`.
- Доказательство: временный Flutter-тест с `Completer` на чтении, существующими `SessionClient`/`MemoryStore` fixtures и `offlineLogout=true`: после `logout`, завершения чтения и `restore` наблюдается `hasToken=true`.
- Ограничение: подтверждён контракт управляющего API с тестовым клиентом; штатный `initializeApp` ожидает restore до показа настроек, поэтому конкретная последовательность действий в одном стартовом экране не доказана. Риск остаётся при перекрывающихся владельцах операций и повторном использовании API.
- Исправление: общий для клиента порядок операций, повторная проверка актуальности после каждого асинхронного перехода; cleanup старого restore не должен удалять новую сессию.

### F3 — P1: позднее сохранение входа восстанавливает секреты после выхода

- Источник: `apps/frontend/lib/api/session_store.dart:117–148,157–171`.
- Условие: `connect` ждёт запись токена; локальный выход завершает удаление и ставит tombstone; запись завершается позднее.
- Причина: `connect` продолжает запись пароля и без проверки актуальности удаляет оба запрета восстановления.
- Доказательство: временный Flutter-тест с блокируемым `SessionStore.write` и выходом без сети: по завершении старого connect в store снова есть токен, `ffido_session_disabled:<endpoint>` отсутствует. Данные только синтетические.
- Последствие: при недоступном серверном отзыве возможен повторный автоматический вход; локальное сохранение пароля также отменяет намерение выхода. Не доказана удалённая компрометация или обход серверной проверки токена.
- Исправление: очередь операций защищённого хранилища на уровне клиента/профиля, версия намерения и приоритет выхода. Tombstone нельзя удалять из устаревшей операции; один mutex отдельного `SessionManager` недостаточен, поскольку экраны создают новые manager.

### F4 — P2: устаревший профиль после выхода во время завершения канала

- Источник: `apps/frontend/lib/api/api_client.dart:150–166`; `configure` публикует epoch, затем ожидает отмену вызовов и `previous.terminate()`.
- Условие: Login уже проверил свой ответ; configure устанавливает новый токен и ждёт завершения старого канала; в это время выполняется `clearAuthToken`.
- Причина: после `await configure` отсутствует проверка версии входа/сессии перед `session=result.session`.
- Доказательство: временный Flutter-тест с настоящим локальным gRPC-сервисом из существующей fixture и блокируемым `ClientChannel.terminate`: после выхода и завершения Login `hasToken=false`, но `session!=null`.
- Последствие: противоречивое состояние профиля и ошибочный успешный результат Login. Само по себе это не разрешает RPC без токена. Отдельно проверить dispose и повторный Login в той же точке ожидания.
- Исправление: проверять актуальный идентификатор операции после configure с учётом его собственного увеличения epoch; не сравнивать наивно с исходным epoch успешного входа.

### F5 — P2: установленная sanitizer-сборка MCP не запускается

- Источник: `apps/backend/CMakeLists.txt:208–217`, `scripts/test_mcp_install.py:18`, текущая ASan-конфигурация `build/backend-asan`.
- Доказательство: полный ASan/UBSan CTest и повтор `ctest --test-dir build/backend-asan -R '^McpInstall$' --output-on-failure` падают. Отдельная установка компонента ffido во временный prefix: запуск `bin/ffido-mcp` завершается с `returncode=-6`; dyld сообщает `Library not loaded: @rpath/libgrpc++.1.84.dylib`.
- В этой сборке зависимости находятся в `build/asan-ubsan-dependencies/prefix`. Объект запускается из build-tree, но после install runtime-поиск не разрешает gRPC. Конкретный способ доставки instrumented dylib/RPATH требует сверки CMake и packaging; production-пакет не объявляется неисправным по этому результату.
- Исправление: восстановить работоспособную установку с согласованными runtime-зависимостями, без подмены библиотеками из обычной сборки; тест должен показывать returncode/stderr при отказе, не только AssertionError.

## Риски и кандидаты на оптимизацию

Эти пункты подтверждают структуру кода, но **не** наличие измеренного slowdown, data race или пользовательского сбоя.

| ID / приоритет | Наблюдение и источник | Что проверить и критерий решения |
| --- | --- | --- |
| R1 / P1 | `mcp/server.cpp:165–170`: worker держит `active_mutex` во время `result`, который сериализует JSON и синхронно пишет/flush в stdout; отмена и EOF тоже требуют этого mutex | Process-тест заполняет pipe, отменяет другой активный RPC, затем возобновляет чтение; отмена должна дойти до RPC без освобождения stdout. Убрать I/O из общей блокировки и ограничить ожидающие ответы; одного переноса `result` недостаточно для полного backpressure |
| R2 / P2 | `conference_service.cpp:76–87`: для каждой записи читается header и выполняется `IsMessageRead`; сортировки date/unread рассчитывают статистику всех подходящих областей до пагинации | 1/100/1000 областей, 100/10000 писем, одна и несколько сессий; считать SQL-вызовы, байты JAM, p50/p95, время lease. Сохранить точные персональные счётчики; не включать тяжёлую статистику в лёгкий каталог |
| R3 / P2 | `sqlite_store.cpp`: одно соединение и общий mutex, отдельные обращения к профилю в `EchoAccess::Permissions`; `Dispatch` валидирует токен до захвата slots | Замер ожидания mutex, SQL/query count и задержек auth при 1/16/64 конкурентных чтениях. Сначала рассмотреть пакетное чтение read keys/профиля в рамках запроса; pool и новый кеш только при доказанной необходимости |
| R4 / P2 | `archive_search.cpp:98` удерживает единый `archive_mutex_` на протяжении проверки областей и сканирования; конкурентный поиск другого пользователя получает RESOURCE_EXHAUSTED | Две независимые сессии/курсора плюс тяжёлая база. Зафиксировать долю отказов и p95; при проблеме разделить синхронизацию registry и отдельного cursor, сохранив атомарность продолжения и общий лимит памяти |
| R5 / P2 | `grpc_service.cpp:133–164`: каждый Dispatch создаёт отдельный поток CancelMonitor с проверкой каждые 10 мс | Замер thread count, CPU, latency и отмены при 1/16/64 запросах. Семафор уже ограничивает вызовы; не объявлять создание потоков утечкой. Менять монитор только при измеренном эффекте |
| R6 / P2 | `jam_catalog.cpp:227–235`: при каждой новой области обходится глобальный registry для удаления expired weak_ptr | Каталоги 100/1000/5000 областей, число сравнений и время Build; потенциальная квадратичная работа, но реальная задержка не измерена. Оптимизация не должна создавать второй physical owner или закрывать POSIX-lock alias |
| R7 / P2 | `message_footer_snapshot.dart:17–29`: успешные snapshots растут по operation ID до смены epoch; `ManagedUpdater.swift` аналогично хранит `seenMessages` до конца процесса | Длительная сессия с тысячами операций и повтор uncertain send. Замер retained memory; освобождать только после определённого завершения, не менять footer при повторе той же операции |
| R8 / P2 | `AndroidUpdater.kt:87–130`: собственный Thread, callbacks и Activity lifecycle; `detach` снимает pending result; `MainActivity.kt` также хранит ожидающее сохранение файла | Изолированный Android-тест recreation/detach во время подготовки APK и системного сохранения; проверить ровно один результат, восстановление installer session и отсутствие callback в старый engine. Конкретная гонка на устройстве не воспроизведена |
| R9 / P3 | ASan build: `test_process.cpp:244` игнорирует nodiscard `request.get()` | Разобрать ожидаемые исходы сигнализированных отправок: учитывать результат/ошибку, сохранив проверки durable операций. Не подавлять warning и не подменять проверку произвольным EXPECT_TRUE |
| R10 / P2 | MCP Dart использует SDK 3.11.4 вместо закреплённого 3.13.5; `build.sh` берёт flutter из PATH | Настроить MCP-процесс на существующий закреплённый SDK и записывать версии при диагностике; автоматические изменения глобальной конфигурации в этом аудите не выполнялись |

Наличие atomic `JamFiles::writable/needs_recovery/role_read_only` проверено: чтение этих флагов до mutex **не** объявляется C++ data race. `AuthService::Configure` используется при старте до RPC; отсутствие mutex на startup-конфигурации само по себе также не является доказанной гонкой. Задержки mutex и backpressure — отдельные риски, не автоматически взаимная блокировка.

## Проверки текущего состояния

Таблица ниже относится к исходному аудиту. Дополнение по блокировкам и оптимизациям после неё основано на повторном чтении исходников; новые runtime-замеры и проверки исправлений в рамках дополнения не выполнялись.

| Проверка | Фактический результат |
| --- | --- |
| Dart MCP `add_roots`, `analyze_files`, `run_tests`, `list_running_apps` | Root настроен; MCP analyzer выдал несовместимые со SDK ошибки primary constructors; MCP tests отказал из-за Dart 3.11.4 против ^3.13.0. Приложений, запущенных через MCP, не найдено |
| Flutter 3.47.7: `flutter analyze --no-pub` | Без замечаний; прежняя MCP-диагностика не подтверждена |
| Flutter 3.47.7: `flutter test --no-pub` | 712 passed, 2 skipped; 5 минут. Команда через CLI использована после подтверждённого отказа MCP на неверном SDK |
| Три временных Flutter-сценария F2–F4 | 3/3 воспроизвели ошибочное состояние, затем завершились успешно, поскольку assert проверял наблюдаемый дефект; это **не** тесты исправления |
| `cmake --build build/backend --parallel 4` | Успешно, существующая Debug-конфигурация |
| `ctest --test-dir build/backend --output-on-failure --parallel 4` | 470 passed, 5 skipped, 0 failed; всего 475 |
| `python3 scripts/check_cpp.py --build-dir build/backend` | Format/clang-tidy прошли: 111 файлов / 57 translation units; инструмент печатает suppressed warnings зависимостей/действующей конфигурации |
| `PATH=<Flutter 3.47.7>/bin:$PATH python3 scripts/check_dart.py --check` | 197 файлов, 0 изменений |
| `cmake --build build/backend-asan --parallel 4` | Успешно; исходный nodiscard warning R9 |
| `ctest --test-dir build/backend-asan --output-on-failure --parallel 4` | 469 passed, 5 skipped, 1 failed (McpInstall); всего 475. Зелёный sanitizer gate не получен |
| `build/update-venv/bin/python -m unittest discover -s scripts/update -p 'test_*.py'` | 64 tests, OK; сообщения об ошибках ADB принадлежат тестовым fixtures |
| Аналогичная discovery в `scripts/release` | 99 tests, OK |
| LLDB MCP | debugger/1 обнаружен, target загружен и breakpoint разрешён; launch и запрос backtrace зависли в интерфейсе MCP. Созданный тестовый процесс остановлен, рабочие службы не затронуты |
| CLI LLDB | Снят backtrace JamLease; `JamLock.CancellationDuringMutexWaitAndOwnerLifetime` завершился успешно. Отдельно сняты stop reason/backtrace/null owner для F1 |
| Codegraph MCP | Индекса для этого repository нет; он не создавался |

Артефакты диагностических запусков временные: `/tmp/ffido-audit-{ctest,flutter,cpp,python-update,python-release,asan-build,asan-tests,races,lldb,recovery}.log`; воспроизводители `/tmp/ffido_audit_races_test.dart` и `/tmp/ffido_audit_recovery.cpp`. Они не являются постоянными регрессионными тестами проекта и могут исчезнуть после очистки системы. Достаточные для переноса последовательности и наблюдения приведены выше; постоянные тесты входят в tasks.

## Непроверенные области и ограничения

- HPT по закреплённому пути `build/release-deps/prefix/bin/hpt` отсутствует; `FFIDO_TEST_HPT` не задавался. Пропущены RealHptPack, HptRoundTrip, HptRoutingFixtures, PointMailboxCycle и Mapped. `check_ctest.py` release gate не пройден.
- TSan не запускался: соответствующий подготовленный dependency prefix отсутствует. CTest, LLDB и ASan не доказывают отсутствие data races.
- Нет подключённого Flutter runtime/DTD; widget tree, runtime errors и UI-действия через MCP не проверены. Приложение дополнительно не запускалось. Hot reload не нужен, так как `lib/` не менялся.
- Native Android/macOS и Windows/Linux release-сборки, реальные A→B обновления, браузер/Envoy, аппаратная клавиатура и screen reader в текущем аудите не проверены. Swift/Kotlin просмотрены выборочно по lifecycle; platform claims по ним не делаются.
- Не измерены CPU/memory/latency на производственном размере архивов; пункты R2–R8 нельзя представлять как доказанное ускорение или эксплуатационный инцидент.
- Тесты Python покрывают две CI-discovery директории, не все standalone acceptance-скрипты. Нет полного security-аудита криптографических библиотек, third-party кода и удалённого окружения.
- Исторические зелёные результаты в `docs/testing.md` не учитываются как результаты этого запуска. Конфликты устаревших упоминаний REST в purpose/config не разрешаются изменением протокола: фактический проект использует TLS gRPC.

## Дополнение: порядок блокировок и задержки отмены

Проверены конкретные области захвата и освобождения в `storage/{jam_access,jam_lock,coordination_lock,sqlite_store}.cpp`, `service/{mail_bridge,message_service,uue_service,archive_search,grpc_service}.cpp`, `mcp/{server,tools,config}.cpp`, `scripts/run_hpt.py` и desktop updater. Далее «наблюдается» означает путь по исходникам; воспроизведённого цикла deadlock дополнение не заявляет.

Повторная попытка LLDB MCP `debugger_list` завершилась timeout через 300 секунд; в этом дополнении стек через MCP не получен и attach не выполнялся. Codegraph повторно не запрашивался: отсутствие индекса уже установлено. Проверки дополнения — `openspec validate harden-code-quality-and-concurrency --strict`, проверка согласованности задач/ссылок и whitespace; приложение и его тестовые suites повторно не запускались для изменения одних планов.

### Карта наблюдаемых зависимостей

Стрелка обозначает захват или ожидание ресурса при удержании предыдущего, а не весь жизненный цикл запроса. SQLite-методы освобождают собственный mutex при возврате.

| Цепочка | Где наблюдается | Ограничение для изменений |
| --- | --- | --- |
| coordination SH → mutex физической JAM → POSIX byte lock → короткие вызовы metadata | `JamAccess::Open`, `JamLease::Acquire`, `ConferenceService::Describe`, `JamWriter::Append` | Не вводить SQLite transaction/mutex → ожидание JAM в обратном направлении; существующий предшествующий metadata-вызов, уже вернувшийся до Open, не является обратным вложением |
| archive mutex → coordination/JAM → metadata | `SearchArchive` держит lock от проверки cursor до завершения сканирования | Общая блокировка сериализует независимые cursor; её `try_lock` быстро отказывает, поэтому это contention/RESOURCE_EXHAUSTED, не доказанный deadlock |
| UUE stripe или crosspost operation mutex → metadata и последующие JAM-доступы | `UueService::Upload/Commit`, `MessageService::CreateCrosspost` | Замена схемы locking сохраняет взаимное исключение одной операции; не захватывать stripe/operation mutex из metadata callback |
| draft mutex → fsync/файлы черновика и RPC | `Client::Call`, `mcp/tools.cpp:296–350` | Отдельный lock на draft должен защищать durable attempted/result и неизменяемый operation ID; registry черновиков не удерживается на сети |
| active mutex → output mutex → stdout | `Serve` worker completion, `mcp/server.cpp:162–168` | Убрать I/O из active lock; ограничение очереди не должно перенести ожидание в reader |
| active mutex → CallContext mutex → TryCancel | `Serve` notifications/EOF и `CallContext::Cancel` | Не вводить callback из Cancel под context mutex обратно в active registry; сейчас такого обратного пути в просмотренном коде не найдено |
| HPT coordination EX → дочерний admin с inherited lock | `scripts/run_hpt.py`, `CoordinationLock::Inherit/Shared` | Дочерний admin должен использовать наследованный lease, а не ждать новый SH против EX родителя |

`MailBridge::Finish` явно делает `source.reset()` перед открытием target; аналогичные release есть в других переходах моста. Одновременный захват source A и target B для ускорения копирования **не предлагается**: он создаст новый порядок блокировок, особенно для alias одной physical base. В `JamCatalog::Build` registry mutex освобождается до `JamLease::Acquire`; удерживать registry во время ожидания lease нельзя.

### Уточнение R1: остановка вывода и завершение процесса

Возможная последовательность: клиент не читает stdout → worker блокируется в flush под active mutex → reader получает notifications/cancelled и ждёт active mutex → отмена другого RPC не доходит до CallContext. Даже после простого переноса worker write за mutex reader может сам заблокироваться на ответе ping/лимита, а EOF может ждать join writer. Риск относится к backpressure и shutdown, не к доказанному циклу двух mutex.

Тест должен управлять pipe и фазами через barriers: заполнить stdout, подтвердить активный второй RPC на локальном fake backend, отправить cancel, наблюдать его отмену **до** возобновления чтения. Затем проверить EOF, закрытый stdout/EPIPE, malformed request и flood ping без чтения. Требуются ограниченные queue bytes/messages и полное завершение всех своих threads; сообщения нельзя молча терять при продолжении соединения. Потерянный ответ send разрешается прежним durable operation ID.

### R11 — P1: общий draft mutex и непрерываемое ожидание

`mcp/tools.cpp:296` использует один `std::mutex` для всех prepare/send: внутри находятся PreviewMessage/CreateMessage и SaveSecret с fsync. Второй запрос другого draft ждёт не свою публикацию; обычное ожидание mutex не учитывает cancellation/deadline. CallContext создаётся до этой блокировки, и его deadline может истечь, пока worker ещё ждёт lock. Лимит четырёх calls ограничивает workers, но не делает отмену ожидающего worker быстрой.

Проверить: A остановлен внутри Preview/Create; B другого draft ждёт, затем отменён; C читает архив; EOF завершает процесс. Отдельно два send одного draft и retry после OUTCOME_UNKNOWN. Критерий: B освобождает слот без ожидания разблокировки A, чтение C не страдает; одну публикацию того же draft нельзя превратить в две. Предпочтительный кандидат — registry per-draft с ограниченным lifetime и отменяемым ожиданием; prepare ещё не имеет draft ID, ему не нужен общий send lock вокруг сети. Это вывод по исходникам, не новый воспроизведённый runtime-дефект.

### R12 — P2: UUE/crosspost ждут mutex до deadline после отмены

`UueService::Upload:426`, `Commit:540` и `CreateCrosspost:1058` используют `try_lock_until(RequestDeadline())`. Вызов не подписан на stop_token; отменённый запрос может оставаться ожидающим до освобождения mutex или deadline. У UUE 64 stripe по hash(user), поэтому независимые пользователи могут столкнуться; у crosspost ключ `(user, operation_id)` и межоперационная изоляция лучше.

Проверить занятую stripe, двух вычисленных в текущем процессе пользователей с одним bucket, разных bucket и два повтора crosspost. Deadline выставить заведомо длиннее окна cancel-теста; измерять и клиентский CANCELLED, и **серверное** время освобождения слота. Кандидат — общий по стилю проекта helper ожидания с короткими try-lock интервалами, stop notification и повторной проверкой RequestActive после захвата. Просто поменять mutex на рекурсивный или увеличить timeout нельзя. Корректную публикацию и идемпотентность по-прежнему защищает lock; отмена после durable commit не означает откат.

### R13 — P2: UUE Chunk копирует весь файл на каждую порцию

`uue_service.cpp:366–398`: `cached = found->second` копирует CachedFile, включая bytes, под общим cache mutex. Затем каждое исходное письмо читается через PeekMessage и хешируется заново. Для файла F и chunk C, K=ceil(F/C), полная загрузка копирует примерно K×F байт только на snapshots, помимо K порций ответа и повторных проверок sources. Это структурная стоимость порядка F²/C, **не** измеренная задержка. Одна копия в каждом из Q одновременных вызовов добавляет примерно Q×F памяти сверх кеша.

Первый кандидат — immutable payload с разделяемым lifetime и копирование лишь запрошенного chunk; ACL и fingerprints проверяются по-прежнему. Не удалять повторную проверку sources ради скорости: при изменении JAM или отзыве доступа кеш нельзя обслуживать без проверки. Проверить один/несколько sources, изменение generation между chunks, TTL/prune во время чтения, отзыв доступа, SHA-256 результата и quotas. Метрики: copied bytes, cache lock hold, JAM bytes/hashes, peak RSS, CPU и throughput. При уменьшении копий повторное чтение sources может остаться основным расходом — это отдельный измеряемый результат.

### R14 — P2: bulk-read задерживает все metadata-операции

`SQLiteMetadataStore::MarkConferenceRead` удерживает mutex и одну BEGIN IMMEDIATE транзакцию во время прохода по всем numbers. Внутри есть проверка active и rollback: утверждать полное отсутствие отмены было бы неверно. Но **ожидание самого mutex** в другом запросе не отменяется; `busy_timeout=250` ограничивает SQLite file contention, а не ожидание C++ mutex. `Dispatch` вызывает ValidateToken до slots и создания RequestBudget/CancelMonitor, поэтому собственный семафор не ограничивает этот участок auth-очереди.

Проверить bulk-read большой базы параллельно с auth, bookmark и небольшим чтением; отдельно внешний SQLite writer во временной БД. Снять время ожидания mutex, время транзакции, SQL count и p95 контрольных запросов. Кандидаты: сокращение подготовок/запросов, более эффективная вставка существующих ключей и отменяемый вход в metadata при сохранении текущей модели. Не дробить atomic bulk-read на частично committed batches, не отключать fsync/synchronous FULL и не передвигать auth после бизнес-операции ради замера. Изменение порядка admission/auth допускается только при сохранении защищённости и нормальных ошибок протокола.

### R15 — P2: длительные shared lease и голодание HPT

Backend держит coordination SH в течение JamAccess, включая тяжёлую статистику, scan и часть обращений к metadata; HPT wrapper ждёт EX с конечным timeout. Jam mutex сериализует даже читателей одной physical base. Постоянный поток новых SH может задерживать EX, а циклы try-lock по 10 мс не гарантируют FIFO. Это риск fairness, не доказанное бесконечное голодание и не основание заменить mutex на shared_mutex: POSIX record locks и закрытие дескрипторов требуют прежней модели physical owner.

Проверить поток чтений одной/разных баз и параллельный HPT-подобный процесс, запрашивающий только EX на временном lock; с настоящим HPT — отдельный gate. Записать max/p95 времени ожидания EX, число timeout и задержку независимой базы. Сокращать время lease можно только при сохранении согласованного snapshot/generation: не освобождать lock посреди чтения для продолжения по прежним offsets. Сначала уменьшить работу внутри lease; writer-preference требует отдельного решения межпроцессной координации и не вводится автоматически.

### R16 — P2: cache quota не ограничивает все временные буферы

UUE Assemble декодирует данные до проверки помещения в `files_`; Chunk создаёт полную копию вне учёта quota. Предел кеша и лимит RPC ограничивают части системы, но сами по себе не дают равного им предела process RSS. Аналогично очередь MCP на 4 MiB не включает одновременно живые protobuf/JSON, structuredContent плюс текстовый дубль, сериализуемый ответ и in-flight writer. Необходимо учитывать эти категории отдельно, а не объявлять 4 MiB лимитом памяти процесса.

Проверить near-limit attachment при Q=1/4/16 и максимальные разрешённые MCP-ответы, включая отмену и quota rejection. Снять peak и steady RSS после освобождения references; разделить удержание кешем, активным запросом и allocator high-water mark. Кандидаты: shared immutable buffers, ранняя reservation in-flight bytes с release на всех ошибках, предварительный ограниченный writer; новых произвольных лимитов без сверки действующего контракта не добавлять.

### Матрица приоритетов оптимизации

| Очередь / кандидат | Сначала доказать | Минимальный подход | Запрет и критерий завершения |
| --- | --- | --- | --- |
| 1: R1/R11/R12, latency отмены | Серверный worker/slot остаётся занят после cancel; источник ожидания различим | I/O вне registry, per-draft scope, отменяемый lock wait | Не ослаблять single-operation serialization; детерминированная регрессия на каждый путь |
| 2: R13, копии UUE | K×F copied bytes и cache-lock hold | Immutable shared payload, copy chunk only | ACL/fingerprint/TTL/quotas прежние; копии payload за загрузку порядка F, а не K×F |
| 3: R2/R3/R14, metadata | N+1 queries, mutex wait и ухудшение контрольных RPC | Пакетный scoped read status/profile, подготовка SQL вне повторяющегося цикла там, где безопасно | Точные счётчики, atomic bulk receipt; query count и p95 до/после |
| 4: R4/R6/R15, каталоги и search | Cross-user RESOURCE_EXHAUSTED, cost Build, длительность shared lease | Per-cursor locking при нужде, редкая очистка registry, меньше работы под lease | Current permissions, alias owner и устойчивость generation не меняются |
| 5: R5/R7/R16, threads и память | CPU/wakeups, retained heap и in-flight peak раздельно | Только доказанная замена polling/освобождение завершённых snapshots/учёт bytes | Не терять uncertain-send snapshot; возврат к исходной реализации при отсутствии эффекта |

Для load-тестов основной набор — 1000 областей с 100 письмами в каждой; 10000 писем использовать в одной горячей базе, а 5000 областей — отдельно для Build без тяжёлого наполнения. Не строить ненужное декартово произведение 5000×10000×64. Cold означает первый запрос после старта собственного процесса и холодные application caches; OS page cache не сбрасывать системными командами. Warm — повтор на тех же fixtures. Сохранять сырые samples, variance, throughput, RESOURCE_EXHAUSTED/deadline/cancel count; приёмка скорости не может опираться только на успешно завершившиеся запросы и отбрасывать отказы.

Отмена в детерминированном тесте должна завершить серверное ожидание до отпускания owner barrier; watchdog 1 секунда при RPC deadline 5 секунд служит пределом тестового окружения, а не новым SLA продукта. Для стоимостных замеров применять прежние критерии design с 20 повторениями; если эффект укладывается в разброс, результат — «выгода не доказана», без оптимизации.
