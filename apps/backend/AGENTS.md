# BE: C++23

Эти правила дополняют корневой `AGENTS.md` для `apps/backend/`. Сервер использует C++23 и gRPC, а не Go/Python backend. Для Python helpers также действуют правила корневой инструкции.

## Контекст и реализация

- До правок читайте README компонента, корневой CMake и `CMakeLists.txt` компонента, `../../cmake/deps.cmake`, `../../cmake/BackendChecks.cmake`, CI, `.clang-format`, `.clang-tidy`, затронутые headers, consumers и регистрацию тестов. Сохраняйте C++23, ABI, поддерживаемые платформы и принятые ограничения exceptions/RTTI; не меняйте toolchain ради стиля.
- Сохраняйте слои `domain`, `service`, `storage`, `ftn` и gRPC mapping. Переиспользуйте действующие error types и `std::expected<..., domain::ApiError>` там, где они приняты. Не превращайте операционные ошибки в успешные пустые результаты.
- Предпочитайте простые value types, стандартные контейнеры, инициализацию и небольшие области видимости. Применяйте `const`/`constexpr` по смыслу; сохраняйте naming, расширения файлов и стиль проекта. Не вводите GSL, шаблоны, concepts, ranges или coroutines без упрощения реальной задачи.
- Управляйте ресурсами, блокировками и C handles через RAII. Предпочитайте value ownership и `unique_ptr`; `shared_ptr` используйте только при действительно общем lifetime. Явно обозначайте невладеющие указатели/ссылки и ownership C APIs/custom allocators.
- Проверяйте lifetime и invalidation для `string_view`, `span`, итераторов и lambda captures. Не возвращайте ссылки на локальные данные; не допускайте dangling views, use-after-free, UB, ошибочного narrowing/overflow и недопустимых bytewise операций.
- Предпочитайте rule of zero. Конвертирующие constructors делайте `explicit`, если преобразование не является намеренным; используйте `override` и корректный destructor полиморфных баз. Copy/move определяйте по необходимости; `noexcept` обещайте только при обоснованном контракте, destructors не должны бросать.
- Соблюдайте модель ошибок: exceptions, если применяются, бросайте по значению и ловите конкретные типы по const reference. Проверяйте ошибки platform/SQLite/JAM/OpenSSL APIs, сохраняйте необходимый `errno` и контекст. Не глотайте ошибки и не подавляйте значимые diagnostics.
- Headers должны быть самодостаточными, с прямыми includes и без глобального `using namespace`. Соблюдайте ODR, избегайте циклов и лишних output parameters. При изменении общих headers проверяйте потребителей.
- Для concurrency явно задавайте владельцев, synchronization, cancellation, shutdown и thread lifetime. Используйте scoped locks и принятые threading abstractions; по возможности не вызывайте callbacks под locks. Соблюдайте существующий порядок межпроцессных JAM/HPT и внутрипроцессных блокировок.
- Изменения SQLite operations, идемпотентности, JAM generations, recovery и чтения/записи проверяйте на изолированных fixtures, включая повтор, частичный сбой и конкуренцию. Не исправляйте рабочие FTN-базы как часть проверки и не меняйте raw JAM/CHRS ради UI-представления. Сохраняйте персональность прочитанности и разграничение доступа к приватным областям.
- Валидация входа, права, TLS, deadlines, лимиты и mapping gRPC errors должны оставаться согласованными с контрактом и FE. Generated C++ находится в build-directory и вручную не редактируется.
- Оптимизируйте после измерений. Избегайте лишних копирований/аллокаций там, где они существенны, сохраняя понятность; не заявляйте ускорение без замера.

## MCP для поиска причин BE-багов

- Для связей symbols/callers/callees и влияния изменений используйте Codegraph MCP по корневым правилам при наличии индекса. Для падений, зависаний, invalid memory/lifetime и подозрений на гонки используйте доступный LLDB MCP; простые compile/contract ошибки сначала проверяйте сборкой/анализом, без ненужного attach.
- Сначала выясните доступные debugger instances через `debugger_list` и реальные возможности `command` либо эквивалентных инструментов сервера. Явно выбирайте debugger/session; не полагайтесь на первый процесс по умолчанию. Отсутствие target/debug server укажите как ограничение.
- Воспроизводите проблему на собственном тестовом процессе или подходящем CTest/GTest executable с тестовыми config/JAM/SQLite. Используйте сборку с debug symbols и соответствующие ей исходники. Не подключайтесь к рабочему backend/HPT без разрешённого для этого объёма задачи.
- Снимите stop reason, backtrace затронутого потока и при необходимости всех потоков; исследуйте frames, значения, ownership и порядок блокировок. Ставьте прицельные breakpoints/watchpoints, проверяйте гипотезу наблюдением. Не используйте выполнение выражений с side effects как безобидное чтение состояния.
- Для гонок учитывайте, что debugger меняет timing: подтверждайте выводы воспроизводимым concurrency-тестом и TSan, когда среда поддерживается. Для memory/lifetime/UB используйте ASan/UBSan. Не заменяйте синхронизацию случайными sleeps и retries.
- После исправления повторите тот же сценарий и регрессионный тест; приложите краткие факты диагностики. Если LLDB MCP не работает, продолжайте через CLI LLDB/CTest/sanitizers и явно укажите, что MCP-проверка не состоялась.

## Сборка, анализ и тесты

Все команды ниже выполняются из корня монорепозитория, не из `apps/backend`. Переиспользуйте подходящую existing build configuration и её dependency prefix/toolchain; не подменяйте Release/Debug или compiler существующего кеша молча. Корневой CMake регистрирует backend и contract tests.

Для уже подготовленных зависимостей штатная Debug-сборка:

```sh
./build.sh build
ctest --test-dir build/backend --output-on-failure --parallel 4
python3 scripts/check_cpp.py --build-dir build/backend
```

- Если среда не подготовлена, следуйте `../../README.md` и CI: `bash scripts/release/dependencies.sh` устанавливает закреплённые зависимости в `build/release-deps`; CMake получает `-C build/release-deps/prefix/ffido-cache.cmake`. Не заменяйте их случайными системными gRPC/protobuf/Husky. Для нестандартной установки учитывайте `FFIDO_HUSKY_ROOT`, `FFIDO_SMAPI_VERSION_INCLUDE`, `CMAKE_PREFIX_PATH`; на macOS выбирайте требуемый Xcode через `DEVELOPER_DIR` по README.
- Для focused-проверок используйте зарегистрированные CTest cases с `ctest --test-dir build/backend -R '<имя/шаблон>' --output-on-failure`. После изменений shared storage/service/headers или контракта выполняйте полный набор и consumers. При изменении CMake сначала повторяйте configure/generate с прежней конфигурацией.
- `build.sh build` включает `CMAKE_EXPORT_COMPILE_COMMANDS=ON`. Для clang-tidy используйте соответствующий `compile_commands.json`, не конструируйте compiler commands вручную. `python3 scripts/check_cpp.py --build-dir build/backend` проверяет format и clang-tidy; `--format-check` — только format. Сохраняйте конфигурации `.clang-format`/`.clang-tidy`, форматируйте лишь изменённые файлы, исправляйте новые compiler warnings.
- Для полноценной HPT/SMAPI интеграционной проверки выполните `FFIDO_TEST_HPT="$PWD/build/release-deps/prefix/bin/hpt" python3 scripts/release/check_ctest.py build/backend` при подготовленных зависимостях. Скрипт отклоняет скрытые skips. Отсутствие HPT — непроверенная интеграция, а не зелёный результат.
- Для памяти/UB: `SANITIZER_DEPENDENCIES_PREFIX=<подготовленный-префикс> ./build.sh asan-ubsan`; для concurrency — отдельный `./build.sh tsan` с соответствующим префиксом. Подготовка описана в `docs/testing.md` и `scripts/build_sanitizer_dependencies.sh`. ASan/UBSan, TSan и coverage требуют отдельных build-directories и согласованно инструментированных protobuf/gRPC/Abseil; не смешивайте их и не подавляйте найденные ошибки.
- При затронутом JAM parsing используйте существующие fixture/oracle/fuzz-проверки по README, когда они относятся к риску. При performance-изменениях используйте измерения; для покрытия — существующий `./build.sh coverage` с подготовленной средой и действующими порогами. Не меняйте проверки, чтобы скрыть непокрытый код.
- Для изменений контракта выполняйте генерацию, `tools/proto/generate.sh --check`, backend contract tests и проверки FE из корневой инструкции. Изменения только инструкций не требуют повторного запуска C++/Flutter suite.
