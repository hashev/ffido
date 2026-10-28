# Локальные проверки FFIDO

Команды выполняются из корня монорепозитория. Зависимости клиента устанавливаются из `apps/frontend`; существующие версии не обновляются через `pub upgrade`.

## Исправление отображения JAM-сообщений, 15 октября 2026

CR/CRLF преобразуются в LF только в API-представлении; исходные JAM-тексты и writer не переписываются. При отсутствии OADDRESS адрес отправителя извлекается из корректного FTN MSGID; явный OADDRESS имеет приоритет. REPLY не интерпретируется как адрес получателя. Это также позволяет отвечать на старые эхосообщения без OADDRESS. Непредставленный адрес в UI обозначается явно, без пустых угловых скобок. Полный текст сохраняет абзацы, цитаты и отступы и отображается контрастным моноширинным шрифтом; список использует ограниченное превью.

Проверены 191 backend-тест (включая установленный HPT), 191 тест под ASan/UBSan, 124 Flutter-теста, flutter analyze и clang-tidy/format двух изменённых C++-файлов. macOS release пересобран. На тестовой копии nino.046.local нативный gRPC подтвердил многострочное тело и адрес отправителя из MSGID. Рабочие JAM-файлы сверены с manifest и не изменены. Предыдущие показатели покрытия ниже относятся к миграции 12 октября; для этого исправления покрытие повторно не измерялось.

## Текущее состояние итоговых проверок

После завершения миграции 12 октября backend содержал 189 CTest-тестов, Flutter — 123 теста. Исторические результаты и исправленные сбои ниже относятся к отдельным этапам реализации.

| Проверка | macOS | Linux (`amster2`, изолированный контейнер) |
|---|---|---|
| Обычная сборка и 189 CTest-тестов | Пройдены | Пройдены, GCC 14 |
| ASan/UBSan с инструментированными protobuf/gRPC/Abseil | Пройдены, 189 тестов | Пройдены с Clang 19: полный CTest и отдельно HPT/права от UID 1000 |
| TSan с инструментированными protobuf/gRPC/Abseil | Пройдены, 189 тестов | Пройдены, 189 тестов; проверки HPT и прав дополнительно пройдены от UID 1000 |
| HPT и общая координационная блокировка | Пройдены на временных базах | Пройдены на временных базах |

На Linux также прошли десять повторов 36 конкурентных/сигнальных/recovery-тестов и 25 повторов трёх регрессий жизненного цикла gRPC. TSan не использует подавления обнаруженных гонок. Для Linux ASan/UBSan используется Clang 19: GCC 14 не смог собрать инструментированную Abseil из-за ошибки constexpr; подробности ниже.

Итоговое покрытие: backend — 93,59% строк и 85,27% ветвей; критические JAM/auth/idempotence/recovery-компоненты — 96,11% строк и 90,03% ветвей; Flutter — 90,92% строк. Пороговые проверки пройдены. `./build.sh check`, native TLS RPC и браузерный gRPC-Web через Envoy с реальным HPT пройдены.

Release-сборки Web, macOS и Android пройдены. iOS не собран из-за отсутствующего SDK требуемой версии; Flutter desktop для Windows и Linux в доступной среде не проверен. Ручные проверки интерфейса установленных приложений на устройствах не выполнялись. Эти ограничения не следует считать пройденными проверками.

## Сохранение адреса получателя и персональные экраны, 16 октября 2026

SMAPI при перезаписи эхописьма может удалить DADDRESS/OADDRESS. Если DADDRESS отсутствует, backend читает адрес из исходного `header_append` **committed** операции SQLite по точному совпадению conference/generation/message_number/FTN MsgID. Адрес из текущего JAM имеет приоритет. Чтение не переписывает JAM и не выводит адрес из REPLY или текущего профиля. Существующие v4 журналы поддерживаются без миграции. Поэтому SQLite operations нужно сохранять вместе с копиями баз. После pack/перенумерации или замены файлов совпадение может отсутствовать: резервный адрес не переносится на новую идентичность автоматически.

В клиенте кнопки закладок доступны в карточках конференций и в разделе закладок; ошибка сохраняет прежнее состояние. История/закладки загружаются при открытии вкладки, список и счётчики обновляются при возврате из чтения с сохранением поиска. Регрессии покрыты `acceptance_regressions_test.dart`, ServicesTest и реальным HPT process-test с `FFIDO_TEST_HPT` (только временные базы). Проверка исправленной сборки: 194/194 backend с HPT, 194/194 ASan/UBSan, 131/131 Flutter, analyze/format/clang-tidy и macOS release; целевой ручной повтор и доказательства — в [manual-test-results.md](manual-test-results.md).

## Backend

```sh
cmake -S . -B build/backend -DCMAKE_BUILD_TYPE=Debug
cmake --build build/backend --parallel 4
ctest --test-dir build/backend --output-on-failure
ctest --test-dir build/backend --parallel 4 --repeat until-fail:10 --output-on-failure
```

Временные JAM/SQLite/config-файлы каждого теста располагаются в отдельном `mkdtemp`-каталоге и удаляются после теста. Тесты не обращаются к реальным FTN-базам.

Для ASan и UBSan:

```sh
JOBS=4 scripts/build_sanitizer_dependencies.sh asan-ubsan
SANITIZER_DEPENDENCIES_PREFIX="$PWD/build/asan-ubsan-dependencies/prefix" ./build.sh asan-ubsan
```

Для TSan:

```sh
JOBS=4 scripts/build_sanitizer_dependencies.sh tsan
SANITIZER_DEPENDENCIES_PREFIX="$PWD/build/tsan-dependencies/prefix" ./build.sh tsan
```

Основная библиотека, сервер и тесты используют одинаковые флаги инструментирования. ASan/UBSan и TSan требуют разных build-directory; одновременное включение запрещено при configure. Поддерживаются Clang/GCC; другие компиляторы с этими опциями отклоняются явно.

## Покрытие

Backend использует Clang source-based coverage. Нужны соответствующие компилятору `llvm-profdata` и `llvm-cov`; для AppleClang скрипт выбирает инструменты Xcode через `xcrun`, для другого Clang сначала ищет рядом с компилятором.

```sh
cmake -S . -B build/backend-coverage -DCMAKE_BUILD_TYPE=Debug -DFIDOBACK_ENABLE_COVERAGE=ON
cmake --build build/backend-coverage --parallel 4
python3 scripts/backend_coverage.py
python3 scripts/frontend_coverage.py
```

Backend-скрипт принимает `--build-dir`, запускает CTest, очищает только предыдущие raw-профили своего отчёта и создаёт `coverage/backend.json`, `backend.txt`, `html/`, `unmeasured.txt` внутри build-directory. В отчёт входят mappings тестового executable и сервера: невызванный сервисный код учитывается с нулевым покрытием. Учитываются только `apps/backend/src` и `include`, без tests/third_party/tmp/системных заголовков. Заголовки только с декларациями могут отсутствовать в mapping; они перечисляются отдельно, без искусственного процента.

Frontend-скрипт запускает `flutter test --no-pub --coverage` из `apps/frontend` и создаёт `coverage/summary.json`. Учитывается собственный `lib/`, исключаются generated protobuf-файлы. Отсутствующие mappings перечисляются как unmeasured, а не считаются пройденными. Оба отчёта — локальные сборочные файлы, в Git их не добавлять.

## Baseline до миграции API, 12 октября 2026

Среда: macOS, AppleClang 21, Flutter 3.41.6/Dart 3.11.4. Обычная, ASan/UBSan и TSan сборки прошли по 55 тестов; обычный набор также прошёл десять параллельных повторов. Flutter: 139 тестов.

| Компонент | Строки | Ветви |
|---|---:|---:|
| Backend | 833/2446 — 34,06% | 160/526 — 30,42% |
| Flutter | 572/954 — 59,96% | Flutter LCOV не измеряет ветви |

Backend: нулевое покрытие `main.cpp`, `http/router.cpp`, `service/{conference_service,message_service}.cpp`, `domain/{bookmark,pagination,profile}.cpp`, `include/SquishMessageBase.h`. JAM: 57,29% строк; SQLite: 76,24%. Flutter: `pages/message_screen.dart`, `repositories/message_repository.dart`, `models/api_response.dart` не покрыты; `lib/conference_repository.dart` — старый репозиторий с mock-данными, отсутствует в coverage mapping; его строки не входят в измеренный знаменатель Flutter.

Это baseline существующих тестов, а не доказательство безопасности многопользовательского режима. На этапе baseline HPT-конкуренция, сбои многофайловой записи, Linux и новые gRPC/gRPC-Web не проверялись; последующие результаты приведены ниже. После расширения тестов отчёты и матрица проверок должны быть обновлены.

При полном warnings-check выявляются существовавшие предупреждения: неиспользуемые `NowIso8601`/`user_id`, игнорирование `nodiscard` в SQLite-тестах; также остаётся CMake CMP0135 при загрузке SQLite. Они не подавлены флагами.

## Подготовленные зависимости gRPC

`cmake/deps.cmake` сохраняет прежние FetchContent-версии и требует экспортированные CMake targets для gRPC 1.84.0 и protobuf 36.2.0. `protoc` этой поставки сообщает `libprotoc 36.2`. Пути к Cellar не прописываются; нестандартный префикс задаётся через CMAKE_PREFIX_PATH. Отсутствующая или другая версия приводит к явной ошибке configure.

Dart-генератор изолирован в `tools/proto`, зафиксирован как protoc_plugin 25.1.0 вместе с lock-файлом. Подготовка:

```sh
cd tools/proto
dart pub get
```

`tools/proto/protoc-gen-dart` можно передать protoc через `--plugin=protoc-gen-dart=...`. Совместимый набор для будущего клиента: grpc 5.1.0 и protobuf 6.1.0. Генерация маленького RPC, его C++ линковка и Dart protobuf round-trip проверены на macOS. На Linux также проверены генерация, C++ линковка и настоящий localhost Echo RPC с русским текстом. FFIDO-контракт включён в общую сборку; контрактные тесты и воспроизводимая генерация описаны ниже.


## Linux через ssh amster2, 12 октября 2026

Проверка выполняется в отдельном временном контейнере Debian 13, GCC 14.2.0/CMake 3.31.6 на x86_64. В контейнер передаются только исходники и тестовые зависимости; реальные FTN/SQLite/config.json не используются. Системные пакеты хоста и работающие службы не изменяются. Это окружение проверки, Docker не является частью сборки или поставки FFIDO.

Для ускорения использованы Linux-пакеты Homebrew gRPC 1.84.0/protobuf 36.2 с проверкой опубликованных SHA-256. CMake получает префиксы окружения через CMAKE_PREFIX_PATH; исходники FFIDO не содержат Cellar-путей. Исполняемые файлы пакетов адаптированы к системному ELF loader внутри временного контейнера. Изначальная сборка этих зависимостей из исходников остановлена после успешной проверки готового набора.

Пройдено: корневые configure/build; 55 CTest, десять повторов каждого теста с parallel 4; generated C++ RPC с настоящим localhost client/server вызовом и Unicode. Логи сохранены локально в build/linux-reports/. Дополнительно GCC выявил существовавшую проверку порта >65535 после сужения к uint16_t в AppConfig.cpp; на этом этапе она ещё не была исправлена; текущая реализация проверяет диапазон до сужения.

Sanitizer-проверки и совместимость SMAPI locks подтверждены ниже. На этом историческом этапе конкурентная запись backend/HPT и crash recovery ещё не проверялись; текущие результаты приведены ниже.

## Генерация общего контракта

Источник — contracts/ffido/v1/ffido.proto; ffido_contracts генерирует C++ и descriptor в build-directory. Смена proto запускает генерацию и пересборку потребителей, проверено изменением mtime и повторной сборкой. Dart-файлы находятся в apps/frontend/lib/api/generated; Empty/Timestamp используются из protobuf runtime, без дублирующих generated-классов.

```sh
(cd tools/proto && dart pub get --enforce-lockfile)
tools/proto/generate.sh
tools/proto/generate.sh --check
```

Генератор проверяет protoc 36.2; режим --check сравнивает результат с сохранёнными файлами. Повторная генерация идентична. Пять контрактных тестов C++ и пять Flutter-тестов проверяют Unicode/Timestamp/Empty/ошибки полей/неизвестные enum. C++ также проверяет RPC surface и отсутствие доверенной личности в CreateMessageRequest. Полный набор теперь содержит 60 CTest и 144 Flutter-теста; Flutter analyze без замечаний. На Linux прошли 60 CTest (обычный режим, десять повторов), ASan/UBSan и TSan по 60 тестов. На этом историческом этапе проверялись storage и контракт; переключение server/client было выполнено позже.

## Совместимость SMAPI locks

Отдельный процесс apps/backend/tests/support/smapi_lock_probe.c использует установленную SMAPI, а scripts/check_smapi_locks.py создаёт собственную временную JAM-базу. Проверяются оба направления конфликта POSIX/SMAPI, read/write lock байта 0 длины 1, доступ к соседнему байту и освобождение lock. Sleep не используется как доказательство синхронизации; handshake и процессы имеют timeout. Helper отказывается продолжать при haveshare=0.

```sh
# SMAPI_PREFIX — префикс установленного Husky, например /usr/local.
# Для поставки без установленного smapi/version.h добавьте её исходный каталог.
cc -D__UNIX__ -I"$SMAPI_PREFIX/include" ${SMAPI_VERSION_INCLUDE_DIR:+-I"$SMAPI_VERSION_INCLUDE_DIR"} \
  apps/backend/tests/support/smapi_lock_probe.c \
  "$SMAPI_PREFIX/lib/libsmapi.a" "$SMAPI_PREFIX/lib/libhusky.a" -lm \
  -o build/smapi_lock_probe
python3 scripts/check_smapi_locks.py build/smapi_lock_probe
```

Подтверждено на macOS: hpt/mac 1.9 2024-03-02, SMAPI 2.5.2 (runtime 2/0x252, date 2022-01-23), haveshare=1. На Linux amster2: hpt/lnx 1.9.0-cur 17-02-17, SMAPI 2.5.0 (runtime 2/0x250, date 11-09-15), haveshare=1. Пользователь подтвердил, что Linux-образ содержит используемую сборку HPT. Проверка выполнялась на искусственных базах с соответствующими библиотеками; рабочие базы и HPT-конфигурации не изменялись.

На этом этапе результат подтверждал только совместимый протокол блокировки; владелец дескрипторов, process mutex и journal/recovery были реализованы и проверены позже. HPT pack/replacement требуют окна обслуживания; сторонний writer, игнорирующий locking, несовместим. При смене сборки или режима sharing проверку нужно повторить.

### JAM ownership и обслуживание pack

`JamCatalog` открывает разрешённые файлы до начала RPC и объединяет hard-link
aliases по физическому `.jhr`, проверяя совпадение companion files. `JamAccess`
удерживает этот owner, process mutex и первый байт `.jhr` до окончания работы.
Парсер использует borrowed descriptors с `pread/pwrite`: представления не
открывают, не дублируют и не закрывают файлы. Read lock — `F_RDLCK`, write —
`F_WRLCK`; ожидание ограничено deadline и stop token, интервал backoff ≤10 ms.
Instance lock использует отдельный `flock`-файл, который нельзя удалять при
работающем backend: unlink создал бы второй независимый lock inode.

Каждый запрос перечитывает base header/index под lock и повторно проверяет
путь относительно открытого корня. Замена любого JAM companion file даёт
`ChangedBase`; backend не переключается на другой inode во время запроса.
Generation включает физический header identity, DateCreated и BaseMsgNum;
обычный append не меняет generation. HPT pack/replacement выполняется только
в окне обслуживания: остановить backend/HPT, сделать согласованную копию,
упаковать, затем заново открыть каталог. Переписывание существующего inode с
сохранением идентичности/DateCreated/BaseMsgNum не поддерживается как online
операция. Полный migration/recovery workflow проверен на следующих этапах (см. ниже).

Подтверждено: 98 тестов ASan/UBSan Linux после parser/SQLite fixes; bounded
libFuzzer Clang 19 — 10 000 итераций, без crash/UB. Новый ownership/locking
слой дополнительно проверяется после этих изменений; прежние результаты
не считаются проверкой ещё не включённых изменений.

### Durable append и quarantine

Перед изменением JAM SQLite сохраняет operation intent с user/operation ID,
payload digest, FTN MsgID, generation, исходными размерами и точными байтами
append/base header. SQLite WAL работает с `synchronous=FULL`. Writer публикует
текст → fsync `.jdt`, заголовок/subfields → fsync `.jhr`, index → fsync `.jdx`,
base header → fsync `.jhr`, затем подтверждает operation journal. После durable
intent commit не прерывается отключением клиента. Любая ошибка исключает
успешный ответ и блокирует новые представления базы до recovery.

Recovery под эксклюзивным lock сравнивает identity/generation, base header и
каждый surviving suffix с точным intent. Полностью записанный append повторно
синхронизируется и подтверждается. Неполный append откатывается только если
весь хвост доказуемо принадлежит операции. Чужие байты, большие размеры,
изменённый base header или generation дают persistent quarantine без truncate.

При quarantine остановите backend/HPT, сохраните согласованные копии всех
четырёх JAM-файлов и SQLite вместе с WAL/SHM до их закрытия. Сопоставьте
незавершённую запись `operations` с сохранёнными файлами; установите происхождение
каждого хвоста и проверьте сообщения через SMAPI/HPT на копии. Рабочая база
остаётся закрытой для записи. Автоматического снятия quarantine или удаления
неизвестного хвоста нет: согласованную восстановленную копию вводят в отдельном
окне обслуживания с проверкой generation и всех подтверждённых сообщений.
Не удаляйте operation journal и не заменяйте отдельный JAM companion file
слепым восстановлением — это может потерять поздние сообщения HPT.

Подтверждены artificial-fixture проверки: short writes, ENOSPC, fsync failure
на каждом этапе; `_exit` процесса после каждого из восьми write/fsync boundaries;
повторное открытие SQLite/catalog; quarantine после полного чужого append,
неизвестного хвоста и смены generation. Это не тест физического отключения питания.

### Выявленное ограничение SMAPI cached close

`scripts/check_smapi_cached_header.py` вместе с режимом `cached-close` SMAPI
helper воспроизводит устаревший base-header write на изолированной базе.
Последовательность: SMAPI открывает базу с одним сообщением и меняет highwater;
другой процесс публикует второе сообщение; SMAPI закрывает прежнее открытие.
Результат на **обеих установленных сборках**, macOS 2.5.2 и Linux 2.5.0:
`ActiveMsgs before=2, after=1, physical slots=2`, причём closing process
завершается даже при чужом exclusive first-byte lock. В исходной SMAPI
`JamCloseArea` вызывает `Jam_WriteHdrInfo` с кешированным `HdrInfo` без
дополнительного lock/refresh. Совместимость byte locks сама по себе не
подтверждает безопасность полной конкурентной работы с HPT.

Пользователь выбрал обязательный общий wrapper. Реализованы отдельные shared
leases FFIDO и exclusive flock через exec HPT; byte locks остаются вторым
уровнем. Concurrent HPT round-trip прошёл отдельную приёмку на Linux и macOS. Рабочие
FTN-файлы при воспроизведении не использовались.

Защищённый повтор `check_smapi_cached_header.py --protected` прошёл на обеих
установленных SMAPI: wrapper не допускает backend shared lease между SMAPI
open и cached close; после завершения HPT выполняется append, итоговый
`ActiveMsgs=2`, два физических слота. Это подтверждает исправление выявленного
cached-close сценария; полный HPT scan/export round-trip также прошёл на обеих ОС (см. ниже).

### Сквозная приёмка native / Web / HPT

Прошёл `scripts/check_acceptance.py` с production TLS backend, настоящим
Dart gRPC-клиентом, Chrome и Envoy 1.39.3. Два пользователя вызывают все 13 RPC:
профиль, conference/message lists, чтение с изолированной прочитанностью,
закладки/история и их timestamps, thread/reply, повтор с прежним operation_id.
Русские строки сохраняются, Empty и binary error trailers обрабатываются,
чужой HTTPS Origin отклоняется. На общей искусственной JAM-базе остаются
ровно четыре сообщения; установленный HPT экспортирует все четыре с Unicode,
FTN MsgID и двумя REPLY. Токены и TLS material существуют только во временном
каталоге; доверие ОС не меняется. Chrome использует pin только временного
сертификата fixture; native клиент проверяет отдельную временную CA.

Воспроизводимая команда после сборки backend и JS harness:

```sh
(cd apps/frontend && dart compile js tool/web_acceptance.dart -o ../../build/web-acceptance.js)
python3 scripts/check_acceptance.py \
  --envoy /absolute/path/envoy \
  --chrome '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
  --hpt /absolute/path/hpt
```

Отчёт последнего успешного полного сценария:
`build/native-browser-hpt-acceptance.log`. ProcessTest HPT round-trip отдельно
проверяет BaseMsgNum=42, UTF-8/cp866, 22 сообщения, десять HPT scan рядом с
backend reads/writes и повторными RPC. Прошёл на macOS HPT/SMAPI 2.5.2 и на
amster2 HPT/SMAPI 2.5.0; `build/linux-reports/hpt-roundtrip.log`. Требуется
`FFIDO_TEST_HPT=/absolute/path/hpt`, иначе optional test явно SKIP.
`scan -w` нужен из-за обнаруженного SMAPI high-water поведения при BaseMsgNum != 1;
Sent attribute не допускает повторного экспорта отправленных сообщений.

### Матрица платформ клиента

| Платформа | Release build | RPC smoke |
|---|---|---|
| Web | прошёл | Chrome → Envoy → TLS backend, все 13 RPC |
| macOS | прошёл | native Dart TLS harness, все 13 RPC; установленный app отдельно не запускался |
| Android | APK release прошёл | устройство/эмулятор не предоставлены, запуск APK не проверен |
| iOS | недоступен: установленному Xcode не хватает SDK iOS 26.5 | не проверен |
| Linux desktop | toolchain Flutter desktop в проверочной среде отсутствует | не проверен |
| Windows | Windows host/toolchain отсутствует | не проверен |

Android release содержит INTERNET, macOS Release sandbox — network client.
Native/web каналы выбираются условным импортом. Отказ недоверенному TLS
сертификату проверен настоящим gRPC client/server тестом; permissive callback
в production коде отсутствует. Успешная компиляция не считается проверкой
запущенного приложения на устройстве.

### Соответствие сценариям delta-specs

Таблица связывает каждый сценарий с проверкой. Названия test suites относятся
к CTest, клиентские файлы — к `apps/frontend/test/`. Недоступные платформы
перечислены отдельно выше; они не считаются прошедшими smoke.

| Delta spec и сценарии | Проверка |
|---|---|
| api-transport: Нет тела ответа; Русский текст без charset; Согласованные клиенты | `acceptance_flow.dart` через native и Web, Contract tests, ApiClient all typed RPCs |
| api-transport: Ошибка авторизации; Ошибки полей | GrpcTest, ApiClient status/field violations tests, browser acceptance trailers |
| api-transport: HTML вместо JSON ошибки | Chrome HTML upstream negative case в `check_acceptance.py` |
| api-transport: Неизвестный серверный статус; Некорректное успешное тело; Отмена и deadline | ApiClient tests: raw status 99, malformed protobuf, cancellation/session/deadline с именем RPC |
| api-transport: Старый маршрут | production backend содержит только gRPC service; HTTP routers/legacy bindings удалены, контракт содержит 13 RPC |
| api-transport: Превышение лимита; Некорректная пагинация | GrpcTest.TlsTrustAndResourceLimitsAreEnforced, ServicesTest.DeletedSlotsAndExtremePageBoundsKeepRealCounters |
| conference-browsing: Другой размер страницы; Повреждённый кеш; Сеть недоступна при обновлении | `repositories/conference_repository_test.dart`: schema/TTL/page-limit/fallback |
| conference-browsing: Смена пользователя или сервера; Требуется авторизация; Запрос отменён | repository и MainScreen tests: epoch, late response, cancellation, no auth fallback |
| jam-storage: Имя и файл различаются; Выход за разрешённый каталог | JamCatalog mapping/traversal/symlink/replacement tests |
| jam-storage: HPT держит блокировку; Конкурирующие отправки; Несколько операций backend | JamLock/JamAccess/Coordination suites, concurrent ServicesTest и ProcessTest.HptRoundTripAndConcurrentExportWithSharedWrapper |
| jam-storage: Удалённая запись в середине | JamWriteIntegrationTest.DeletedPhysicalSlotsKeepNumbersWithNonunitBase, SmapiDeletedMarkersAndHeaderFlagsDoNotReuseSlots |
| jam-storage: Огромная длина; Усечённый индекс | JamWriteIntegrationTest bounded/truncated/oversized cases, 10 000 bounded fuzz iterations |
| jam-storage: Сбой каждого этапа | JamRecoveryTest ENOSPC/short-write/fsync/process-exit matrix, recovery retry/quarantine tests |
| jam-storage: Русский текст HPT; Отправка через backend | actual HPT round-trip UTF-8/cp866/MsgID/REPLY на Linux/macOS и native/browser HPT export |
| jam-storage: SMAPI закрывает кешированную базу | `check_smapi_cached_header.py --protected` на обеих установленных SMAPI |
| jam-storage: Timeout wrapper или backend | HptWrapper, Coordination, JamLock и ProcessTest external lock wait |
| message-access: Поиск и последняя страница; Детали конференции | ServicesTest.EmptyFilterAndPaginationTotals, SearchCountsDatesAndConferenceSortsAreConsistent |
| message-access: Одинаковые номера в разных базах; Повторное чтение | SQLiteStoreTest.ReadKeySeparatesUserConferenceAndGeneration, ServicesTest.ReadHistoryCountersAndBookmarksArePersonal |
| message-access: Несуществующий родитель | ServicesTest.ReplyUsesParentSenderAndRejectsMissingParent |
| message-access: Ответ потерян | ServicesTest.IdempotencyHandlesConcurrentRepeatLostResponseAndDifferentUser, IdempotencySurvivesActualMetadataReopen; native/browser same-operation retry |
| message-access: Циклическая цепочка | ServicesTest.ThreadBranchPaginationMissingParentCyclesAndDeletedNodes |
| message-access: Ошибка отправки | Compose/widget/repository tests сохраняют draft/operation ID; backend fault/recovery не сообщает успех |
| user-identity: Действующий токен; Недействительный доступ; Попытка подмены | AuthServiceTest, GrpcTest auth-before-mutation и assigned sender tests |
| user-identity: Два пользователя | native/browser acceptance, ServicesTest personal data isolation |
| user-identity: Выход | ApiClient session/cancel tests, settings/profile/personal screens/widget tests |
| user-identity: Старые номера без generation; Повтор и сбой миграции | SQLiteMigration.BacksUpEveryLegacyReadWithoutReassigningNumbers, BackupCollisionRollsBackWholeMigration |
| platform-runtime: Производственная сеть; Остальные нативные платформы; Web release | platform matrix выше: сетевые permissions и три release builds; RPC только в перечисленных проверенных средах |
| platform-runtime: Недоверенный сертификат | GrpcTest.TlsTrustAndResourceLimitsAreEnforced |

Browser acceptance дополнительно проверяет HTML gateway response как
контролируемую ошибку `GetProfile`, без HTML в публичной диагностике.

### Окно миграции и резервная копия

1. Остановите backend и все HPT jobs, убедитесь, что никто не обращается к базам.
   Нельзя получать согласованную копию независимым копированием companions
   во время записи. Не удаляйте lock-файлы для обхода работающего процесса.
2. Сохраните конфигурацию, SQLite и все `.jhr/.jdt/.jdx/.jlr` каждой базы
   в отдельный каталог. Если SQLite ещё открыт, его WAL/SHM являются частью
   состояния; проще дождаться закрытия всех соединений. Для закрытой SQLite
   можно сделать самостоятельный snapshot стандартным backup API:

   ```sh
   python3 - /absolute/path/metadata.db /absolute/path/backup/metadata.db <<'PY'
   import pathlib, sqlite3, sys
   source, target = map(pathlib.Path, sys.argv[1:])
   if not source.is_file() or target.exists():
       raise SystemExit('Source missing or backup already exists')
   with sqlite3.connect(source.as_uri()+'?mode=ro', uri=True) as incoming:
       with sqlite3.connect(target) as outgoing:
           incoming.backup(outgoing)
           if outgoing.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
               raise SystemExit('Backup integrity check failed')
   PY
   ```

3. Сначала работайте с копией, отдельным config и lock, отдельными TLS ports.
   `ffido-admin provision` открывает metadata store и выполняет ту же migration,
   что backend. Проверьте `PRAGMA user_version=4`, наличие всех старых строк в
   `read_status_legacy_backup`, пустую новую `read_status`, сохранённые
   bookmarks/history. Выдавайте рабочие токены только после проверки копии.
4. Проверьте wrapper и реальную установленную SMAPI, запустите backend,
   native/Web клиент и HPT export на копии. Production HPT schedules должны
   вызывать wrapper с тем же coordination path. Самостоятельный HPT в обход
   wrapper делает гарантию целостности недействительной.
5. После проверки примените конфигурацию в окне обслуживания и одновременно
   переключите клиенты на gRPC. При pack/replacement остановите backend,
   сохраните новый согласованный backup и перезапустите каталог: generation
   изменится, старые персональные ссылки не будут приложены к другим номерам.
6. Для отката остановите процессы и восстановите согласованные данные из копии
   в отдельную staging-папку. Если после backup были новые подтверждённые
   сообщения, слепое восстановление старых JAM потеряет их; сначала сопоставьте
   MsgID и сохраните новые записи. Quarantine требует ручного расследования,
   автоматического снятия через config/admin нет.

Миграция на искусственной legacy SQLite проверена тестами сохранения всех
backup-строк, bookmarks/history, нового read state, повторного запуска и
rollback при конфликте backup. Durable recovery проверен отдельными
process/fault tests; тестирование не изменяет реальные FTN-файлы.

### Текущее покрытие после gRPC/JAM миграции

Отчёт включает core, production server и `ffido-admin`; CTest запускается
с `FFIDO_TEST_HPT`, поэтому optional HPT round-trip не пропускается. Generated,
third_party и test code исключены; production ошибки остаются в знаменателе.

| Область | Строки | Ветви | Gate |
|---|---|---|---|
| Backend | 3795/4055 = 93,59% | 1853/2173 = 85,27% | 90% / 85% — прошёл |
| JAM/auth/idempotency/recovery | 2124/2210 = 96,11% | 1111/1234 = 90,03% | 95% / 90% — прошёл |
| Flutter | 1151/1266 = 90,92% | не измеряются | 90% — прошёл |

Для повторения: `FFIDO_TEST_HPT=/absolute/path/hpt ./build.sh coverage`.
HTML/JSON backend reports находятся в `build/backend-coverage/coverage/`,
Flutter LCOV/summary — `apps/frontend/coverage/`. Gate проверяет реальные
covered/count, возвращает ненулевой exit code при нарушении. Baseline выше
сохранён для сравнения; старые количества тестов относятся к этапам внедрения.
Текущий набор: 188 CTest и 123 Flutter tests.

SQLite allocation fault tests используют документированный allocator API,
по одному отказу в prepare/bind/step/transaction и 350 позициям startup.
Lookaside отключается только внутри fault test и возвращается к зафиксированному
дефолту bundled SQLite; production настройки не меняются. I/O adapters дают
контролируемые короткие чтения/записи, EINTR, ENOSPC, fstat/read/truncate/fsync
failures. Проверки требуют отсутствия ложного успеха и сохранения подтверждённых
данных; после снятия отказа проверяется recovery и integrity_check.
OpenSSL provider failures проверяются отдельным exec, без изменения provider
state родительского тестового процесса.

Список `unmeasured.txt` перечисляет 16 заголовков без coverage mapping:
большинство содержат declarations/POD; `SquishMessageBase.h` не включён в
активную JAM-only сборку. Во Flutter отсутствуют executable lines в
`api_constants.dart`; web-only channel дополнительно проверен browser acceptance,
его исполнение не добавляется искусственно в Flutter LCOV. Непокрытые guards
для недоступных/невозможных состояний остаются в отчёте: например, неверная
длина результата SHA256, gmtime failure для uint32 timestamp на 64-bit OS,
ошибка системной настройки сигналов. Blanket exclusions и suppressions нет.

### TSan и согласованные зависимости

У protobuf generated messages поле `PROTOBUF_TSAN_DECLARE_MEMBER` зависит от
sanitizer compilation. Смешивание generated/core TSan с обычным protobuf runtime
может менять layout и приводить к падению `CheckHasBitConsistency`, поэтому
это не подтверждённый TSan-прогон. Не отключайте sanitizer macro и не подавляйте
сообщения. Все три runtime — protobuf, gRPC, Abseil — собираются теми же версиями
с TSan. OpenSSL 3 используется для сборки исходников gRPC 1.84 (его исходники
несовместимы с const API OpenSSL 4); это отдельная тестовая сборка в `build/`,
обычные проектные версии и установленные пакеты не меняются.

```sh
JOBS=4 scripts/build_sanitizer_dependencies.sh tsan
SANITIZER_DEPENDENCIES_PREFIX="$PWD/build/tsan-dependencies/prefix" ./build.sh tsan
```

Требуются существующие package dependencies c-ares/re2/zlib и OpenSSL 3.
`SANITIZER_OPENSSL_ROOT` меняет путь к OpenSSL, `SANITIZER_BUILD_DIR` — workspace сборки.
Зависимости не устанавливаются глобально. `sanitizer_cache.py` проверяет наличие
memory instrumentation выбранного sanitizer в трёх библиотеках и записывает точные CMake
package paths. Без такого prefix `build.sh tsan` останавливается с ясной ошибкой,
а не запускает заведомо несовместимую смесь библиотек.

После итогового review добавлен регрессионный сценарий неопределённой отправки:
INTERNAL/UNKNOWN/DATA_LOSS и неизвестный status могут прийти после durable intent.
Клиент сохраняет прежние operation_id/payload и блокирует редактирование до
подтверждения; subsequent quarantine rejection не снимает это состояние.
Definite validation rejection до записи по-прежнему позволяет исправить draft.
Все шесть новых widget-сценариев прошли; всего 123 Flutter tests.

Предыдущий ASan/UBSan до финального исправления instrumentation contract:
188 CTest macOS прошли с actual HPT; Linux 188 CTest прошли
(два optional/permission tests root-прогон явно SKIP). Оба пропущенных случая
отдельно прошли direct GTest от UID 1000: HPT round-trip и настоящие read-only
permissions. Отчёты: `build/current-asan-command.log`,
`build/linux-reports/current-asan-tests.log`,
`build/linux-reports/current-asan-hpt-permissions.log`.

Итоговый `./build.sh check` после исправления неопределённой отправки прошёл:
59 C++ files / 30 translation units, генерация контрактов без изменений,
Flutter analyze без замечаний и все 123 tests. Release Web и native/browser/HPT
acceptance также прошли. Логи: `build/current-final-check.log`,
`build/final-web-release.log`, `build/final-native-browser-hpt-acceptance.log`.

При финальном CMake review исправлен `ffido_contracts`: generated C++ target
теперь получает те же sanitizer/coverage flags, что core и tests. Это обязательно
для одинакового protobuf layout под TSan; инструментирование только потребителей
недостаточно. Generated исходники остаются исключёнными из итогового покрытия.

Полный повтор coverage после инструментирования C++ contract прошёл (188 CTest,
123 Flutter tests); критический порог остаётся выполнен без новых исключений.
Текущий отчёт: `build/final-contracts-coverage-repeat.log`.

TSan macOS с согласованными protobuf 36.2/gRPC 1.84.0/Abseil 20260817.0
и инструментированным generated C++ contract: все 188 CTest прошли с HPT,
без TSan suppressions (67,63 с). Отчёт:
`build/final-instrumented-tsan-command.log`.

Для ASan/UBSan применяется такая же отдельная подготовка runtime; protobuf
36.2 включает `PROTOBUF_MESSAGE_GLOBALS` под ASan, поэтому обычный release
runtime нельзя смешивать с инструментированным generated C++ contract.
Флаги instrumentation отделены от строгих warnings собственного кода;
`gtest_list_tests` имеет discovery timeout 30 с для первого старта этих библиотек.

Финальная Linux TSan matrix выявила гонку выхода startup fixtures: OpenSSL
atexit cleanup освобождал rwlock параллельно с trailing TLS cleanup EventEngine.
Одного `grpc_is_initialized()` оказалось недостаточно. `GrpcRuntime` удерживает
EventEngine до закрытия всех channels/servers, ждёт release references с deadline
и уничтожает engine на вызывающем потоке; destructor engine joins workers.
То же владение используется production main. Regression охватывает deadline,
живой reference, repeated shutdown и 25 повторов двух ранее падавших процессов.

После владения EventEngine: TSan macOS все 189 tests passed (113,27 с);
Linux — 25 повторов каждого shutdown regression и все 189 CTest прошли
(41,04 с, read-only test root SKIP проверяется отдельно UID 1000).
HPT был включён в оба полных прогона. Отчёты:
`build/final-instrumented-tsan-command.log`,
`build/linux-reports/final-tsan-race-regression.log`.

Финальный coverage с `GrpcRuntime` прошёл: 189 CTest, 123 Flutter tests,
backend 3795/4055 lines (93,59%), 1853/2173 branches (85,27%),
critical 2124/2210 lines (96,11%), 1111/1234 branches (90,03%).
Отчёт `build/final-runtime-coverage.log`; новые guard/error branches
остались в знаменателе. Непройденных coverage gates нет.

Linux GCC 14 ASan/UBSan runtime dependencies: Abseil 20260817.0 не собирается
с обоими sanitizers из-за constexpr comparison function pointer в
`hash_policy_traits.h:158`; это ошибка компиляции, не OOM. Full ASan/UBSan
matrix выполняется установленным Clang 19 с теми же pinned libraries;
обычная и TSan Linux matrix остаются GCC 14. Dependency optimization -O1
используется в отдельной диагностической сборке, core — Debug. Никакие
sanitizers/checks не отключены, installed toolchain не меняется.

Финальный macOS ASan/UBSan с согласованными instrumented runtimes и
`GrpcRuntime`: все 189 CTest прошли с HPT (24,00 с). Public dependency script
с pinned tags, install RPATH и nm memory-instrumentation validation также
успешно завершён. Отчёты: `build/final-instrumented-asan-command.log`,
`build/mac-instrumented-asan-dependencies-resumed.log`.
Обычная Linux сборка: 189 CTest прошли (30,51 с), 36 конкурентных/lock/signal
сценариев по 10 повторов прошли (78,62 с), HPT включён.
Отчёт `build/linux-reports/final-normal-command.log`.

Release builds текущего Flutter-клиента после последнего исправления retry:
Web прошёл, macOS `fido.app` 42,7 MB и Android `app-release.apk` 49,9 MB
успешно собраны. Отчёты: `build/final-web-release.log`,
`build/final-macos-release.log`, `build/final-android-release.log`.
Device/UI acceptance packaged apps не заявляется как пройденный;
iOS SDK и Windows/Linux Flutter desktop ограничения указаны в matrix выше.

## Финальная Linux ASan/UBSan-проверка с Clang 19

Инструментированные Abseil 20260817.0, protobuf 36.2 и gRPC 1.84 собраны публичным `scripts/build_sanitizer_dependencies.sh` в изолированном контейнере `amster2`. Core и сгенерированный контракт используют те же флаги. CTest завершился без ошибок: 189 зарегистрированных тестов, 38,30 с; read-only permissions пропущен при root и затем успешно выполнен вместе с HPT от UID 1000 (2 теста, 3,43 с). Отдельный запуск актуального JAM parser fuzzer с этим набором библиотек прошёл 10 000 итераций под ASan/UBSan за 5 с.

Первый запуск обнаружил ODR violation до начала тестов: gRPC 1.84 включал `descriptor.upb_minitable.c` одновременно в `libgrpc` и `libupb_descriptor_lib`. `scripts/grpc_shared_dependencies.cmake` исключает повторную компиляцию descriptor в трёх gRPC runtime-targets и добавляет зависимость на единственную библиотеку descriptor. Это изменение графа сборки, а не подавление диагностики: ASan ODR detection остаётся включённым, версии и исходники зависимостей не изменены. Повторный запуск успешно завершился. Та же конфигурация повторно проверена на macOS: ASan/UBSan — 189 тестов, 26,28 с; TSan — 189 тестов, 92,61 с.

Локальные журналы: `build/linux-reports/final-asan-clang-command.log`, `final-asan-clang-hpt-permissions.log`, `final-matched-fuzz.log`. Журналы, инструментированные библиотеки и тестовые данные исключены из Git.

После исправления дублирующего descriptor Linux TSan также повторно прошёл полный CTest: 189 зарегистрированных тестов, 76,65 с, без сообщений TSan. Пропущенная от root проверка прав вместе с HPT дополнительно прошла от UID 1000: 2 теста, 4,66 с. Журналы: `build/linux-reports/final-deduplicated-tsan-command.log` и `final-deduplicated-tsan-hpt-permissions.log`. Финальный `./build.sh check` повторно прошёл C++ formatting/clang-tidy, генерацию контрактов, Dart formatting/analyze и все 123 Flutter-теста.

## Авторизация HPT и независимые сессии (17 октября 2026)

Общий `ffido.v1.Ffido` теперь включает Login, RestoreSession и Logout.
Login принимает имя, FTN-адрес и пароль HPT без Bearer; остальные RPC используют
внутреннюю сессию. Ошибки полей типизированы, неизвестный адрес и неверный пароль
возвращают одинаковый UNAUTHENTICATED, превышение попыток — RESOURCE_EXHAUSTED.
Пароль не передаётся в metadata или URL. Ручная выдача токена удалена из CLI и UI.

Миграция SQLite v5 транзакционно нормализует адреса, сохраняет прежние user_id
и личные данные, отклоняет дубли и отзывает legacy-токены. AuthService-тесты
проверяют два устройства, независимый выход, конкурирующие первые входы,
сохранение имени, перезапуск, истечение, смену/удаление пароля, замену ключа,
отсутствие пароля/секрета сессии в SQLite и проверку прав ключа.
`GrpcTest.HptLoginTwoDevicesShareServerDataAndLogoutIsIndependent` проверяет
вход через TLS и общие письма, прочитанность, историю, закладки и независимый
Logout. `HptAuth` проверяет Include/условия HPT, пустой SessionPwd, наследование,
исключение виртуальных линков, закрытую диагностику, сбой и таймаут помощника.

Нативный и браузерный acceptance harness теперь получают сессии настоящим Login
из искусственных HPT-линков; старый `ffido-admin provision` не используется.
Секреты тестовых конфигураций находятся только во временном приватном каталоге.

Итоговые результаты этого изменения: 210/210 backend-тестов с
`FFIDO_TEST_HPT=/Users/yurik/ftn/usr/bin/hpt`, 141/141 Flutter-тестов,
`flutter analyze --no-pub` без замечаний, проверки clang-format/clang-tidy,
формата Dart, воспроизводимости generated proto и OpenSpec strict пройдены.
Web, macOS и Android release собраны. Для нативного release после integration
используется обычный `flutter build ... --release` с штатной перегенерацией
плагинов; `--no-pub` может сохранить регистрацию dev-плагина integration_test
от предыдущего отладочного запуска в установленной версии Flutter.

Повторить реальный прогон двух клиентов с уже запущенным Android-эмулятором:

```sh
python3 scripts/check_two_devices.py --android emulator-5554
```

Сценарий использует Android bridge `10.0.2.2`, действительную цепочку тестового
CA и отдельные запуски приложений без удаления их данных. После успешного
прогона обе тестовые сессии отзываются и удаляются из хранилищ. Детальные этапы
и ограничения записаны в `docs/manual-test-results.md`. Физический Android и
публичный VPS этим прогоном не проверены; iOS/Linux/Windows недоступны здесь.

## Отображение путей FTN и KOI8-R — 19 октября 2026

Change `configure-ftn-path-mappings-and-koi8-r` проверяется только на синтетических
конфигах и временных JAM. Рабочие `hpt.cfg`, `areas.cfg`, JAM и Docker Compose
ноды amster2 не менялись. Пример конфигурации, UID/GID, общий lock и команды сборки
адаптера приведены в `apps/backend/README.md`.

Проверки охватывают границы префикса, вложенные правила без каскадов, HPT basedir,
условия и относительные/вложенные include, циклы, лимиты, приватность ошибок,
соответствие areacfg активному include, каталог с `-p`, inode/dev-сверку,
JAM-корень и симлинки. Проверены provisioning и полный почтовый цикл с mapping.
Отдельный helper без адаптера проверяет явный отказ mapped-режима и прежнюю загрузку.

KOI8-R проверяется фиксированными байтовыми эталонами тела/темы/имён, приоритетом
CHRS CP866/UTF-8, fallback IBMPC/отсутствующего CHRS, отсутствием перезаписи истории,
публикациями/ответами gRPC и отказом непредставимых символов без мутации JAM.
UUE проходит загрузку, публикацию, сборку и проверку SHA-256. Установленный HPT
через SMAPI читает/экспортирует синтетические KOI8-R-письма; сырые байты сравниваются
до и после scan/pack, проверяются пакет и повторное чтение API.

Docker bind-mount-проверка выполнена на amster2 с отдельными временными файлами
и одноразовыми контейнерами `fido:120`: shared lease на хосте блокирует exclusive
в контейнере, а exclusive в контейнере блокирует wrapper на хосте до timeout.
Воспроизведение на машине с Docker и образом с `sh`/`flock`:

```sh
FFIDO_TEST_DOCKER_IMAGE=fido:120 python3 scripts/test_hpt_wrapper.py scripts/run_hpt.py
```

Без переменной Docker-проверка явно отмечается как невыполненная; обычные проверки
wrapper продолжают работать без Docker. Успешный bind mount не доказывает безопасность
фонового `exec -d` или наследование fd через Docker exec. Полный point_mail `--cycle`
требует одной среды выполнения HPT и admin, как описано в README.

Для локальной macOS-сборки потребовалось задать
`DEVELOPER_DIR=/Library/Developer/CommandLineTools`: выбранный по умолчанию Xcode
требовал принятия лицензии. Системный выбор developer directory не менялся.
Существующее предупреждение `test_process.cpp` о неиспользованном nodiscard-результате
в тесте остановки процесса не относится к изменению; проверки не отключались.

На macOS итоговая Debug-сборка прошла **350/350 CTest** с
`FFIDO_TEST_HPT=/Users/yurik/ftn/usr/bin/hpt`. Форматирование изменённых участков,
clang-tidy всех затронутых translation units и `openspec validate --strict` прошли.

Первый полный Linux-прогон от UID 1000 дал **344/350**, без пропусков.
Шесть ошибок имели общую причину: установленная в тестовом контейнере Husky
отвергала `Route nopack`. Прямой контроль показал одинаковый отказ у helper
с адаптером и без него; обычную маршрутизацию оба читали. Падали
`HptAuth.ExposesEffectiveMailTransportWithoutInventingOwnPointAka`,
`HptRoutingFixtures`, `PointMailboxProvision`, `PointMailboxCycle` и два mapped-варианта.

Для устранения причины в контейнере `ffido-check-dG62Kh` собран отдельный
статический комплект Husky в
`/tmp/ffido-path-mapping-20261019/husky-test/prefix`. Использованы исходники
из тех же ревизий, что и в успешном локальном окружении:

| Компонент | Ревизия |
| --- | --- |
| huskylib | `d3c0c1c3b643d7fce45f82d6c8378802e85d9205` |
| smapi | `c2fc9ecb0dd1ec8909e9e9709bfdd0031d5b9bf2` |
| fidoconf | `62c963a6f078905660f2c0b3a6929383823190c5` |
| areafix | `cd178f92e01d73b39bfc00b4d6359efd543dd990` |
| hpt | `c2a91d64cee0e6cd357376d30c9285ee3f9c624f` |

В сборку переданы чистые Git-снимки, без локальных изменений CMakeLists.txt.
Компоненты собираются в порядке таблицы с `BUILD_SHARED_LIBS=OFF`,
`CMAKE_INSTALL_LIBDIR=lib`, `CMAKE_INSTALL_PREFIX=<prefix>`,
`CMAKE_PREFIX_PATH=<prefix>` и `CMAKE_C_FLAGS=-I<prefix>/include`.
Параметры `husky_LIB`, `smapi_LIB`, `fidoconfig_LIB`, `areafix_LIB` явно указывают
на соответствующие `.a` в `<prefix>/lib`. CMake запускается из каталога исходников
каждого компонента: upstream получает дату сборки через `git log`.
Системные `/usr/local` и зависимости рабочего тоссера не заменялись.

При повторном конфигурировании FFIDO нужно заменить также закэшированные пути,
а не только `FFIDO_HUSKY_ROOT`. После установки согласованного комплекта:

```sh
# husky_src — каталог с исходниками компонентов из таблицы; prefix — их установка.
cmake -S . -B build/backend \
  -DFFIDO_HUSKY_ROOT="$prefix" \
  -DFFIDO_FIDOCONFIG_INCLUDE="$prefix/include" \
  -DFFIDO_FIDOCONFIG_LIBRARY="$prefix/lib/libfidoconfig.a" \
  -DFFIDO_HUSKY_LIBRARY="$prefix/lib/libhusky.a" \
  -DFFIDO_SMAPI_INCLUDE="$prefix/include" \
  -DFFIDO_SMAPI_LIBRARY="$prefix/lib/libsmapi.a" \
  -DFFIDO_SMAPI_VERSION_INCLUDE="$husky_src/smapi/smapi" \
  -DFFIDO_FIDOCONFIG_SOURCE="$husky_src/fidoconf"
cmake --build build/backend --parallel 1
FFIDO_TEST_HPT="$prefix/bin/hpt" ctest --test-dir build/backend --output-on-failure
```

Linux-контейнер ограничен 2,5 GB RAM: сборка с четырьмя GCC-процессами
завершалась OOM, поэтому используется `--parallel 1`. Тесты запускаются после
полного завершения сборки, от UID 1000; прогоны, пересёкшиеся с перелинковкой,
не используются как итоговые результаты. Исходные предупреждения upstream Husky
о `strncpy`, fallthrough и `mktemp` не скрывались и не исправлялись в рамках этой
проверки. Тесты и безопасные требования point_mail не ослаблялись.

Шесть исходных ошибок после смены тестовых зависимостей: **6/6 успешно**,
6,29 секунды. Заключительный полный Linux-прогон от UID 1000 с настоящим HPT:
**350/350 успешно, 0 ошибок, 0 пропусков**, 123,03 секунды. Итоговый macOS-прогон
предыдущего этапа: **350/350 успешно**, 66,43 секунды; после исправления Linux
код FFIDO и тесты не менялись.

Рабочая нода в `/home/yurik/fido`, её конфигурации, базы и контейнеры не менялись.
Все новые установки и сборки находятся в `/tmp/ffido-path-mapping-20261019`
тестового контейнера; на хост передавались только временные исходные архивы и
сценарии в `/tmp`. Команд к рабочему тоссеру не выполнялось.
Журналы сборок, точные команды, проверка статической линковки и полный результат
сохранены локально в `build/backend/ftn-path-mapping-reports/` (исключено из Git),
включая `ffido-linux-all-fixed.log` и `linux-husky-linkage.txt`.

## Подготовка публичного репозитория — 19 октября 2026

Change `prepare-github-publication-and-releases`: владелец выбрал MIT, новую
публичную историю без прежней `.git`, ID `io.github.hashev.ffido` и unsigned desktop.
Рабочая нода amster2 не использовалась и не менялась. Пустой `hashev/ffido` уже
настроен; исходники, commits и workflows пока не загружались.

Проверки реализации подготовки:

- 17 unittest для экспорта, исключения runtime/истории/секретов, governance,
  версий, неполных/смешанных пакетов, draft/resume, отказа подмены публичного
  релиза, release-сертификата APK, трёх ABI, вложенного MIT notice, read-only dylib
  runtime-имени перелинкованной библиотеки и обязательных legal gates — успешно.
- actionlint 1.7.11: три workflow без ошибок; shell syntax и Ruby Podfile — успешно.
- Локальные ссылки README/CONTRIBUTING/publication guide проверены; OpenSpec strict
  и whitespace-check прошли.
- C++ format/clang-tidy: 99 файлов / 51 translation unit успешно. Для штатного
  formatter исправлен только порядок двух includes в test_hpt_auth.cpp.
- Из отдельного проверочного экспорта: Flutter pub get с lock enforcement,
  analyze без замечаний, 230 тестов успешно; два существующих теста skipped.
  CMake Debug build и полный CTest с настоящим HPT: **350/350**, без пропусков,
  109,16 секунды. Использованы установленные закреплённые зависимости, новый bootstrap release-deps проверен отдельно (см. ниже).
- Android release build и macOS arm64 release build из экспорта успешны.
  MacOS baseline проекта/Pods — 15, архитектура каждого пакета соответствует
  native runner. Штатная release-перегенерация Flutter обязательна: --no-pub
  после тестов сохранял регистрацию dev-плагина integration_test.
- Созданы локальные validation APK и DMG. APK содержит три ABI и собственный
  MIT notice, но имеет debug-подпись и **не допускается к публичному выпуску**.
  DMG прошёл checksum, mount, проверку bundle ID, arm64 и ad-hoc codesign.
  Local-validation metadata имеет нулевой SHA и не обозначает публичный commit.

Локальные пакеты и журналы собираются в исключённом из Git
`build/publication-validation/`. Исторические предупреждения Flutter plugins и
upstream зависимостей не отключались. Homebrew runtime-библиотеки на этой машине
имеют minimum macOS 26: упаковщик вычисляет реальный максимум minos, а не обещает
macOS 15 по строковой метке. CI на macOS 15 должен подтвердить свой реальный baseline.

На этой машине нет Windows/Linux desktop и Intel macOS runner. Их package builds,
полная матрица GitHub Actions, реальные правила первого PR, запуск распакованных
пакетов на всех ОС и публичные anonymous downloads остаются непроверенными.
Постоянный Android release-key ещё не предоставлен. FFIDO_PUBLICATION_READY
остаётся false; workflow не выдаёт debug APK за публичный релиз.

Дополнительно bootstrap release-deps собрал из зафиксированных commit SHA
Abseil, Protobuf, gRPC, grpc-proto и весь тестовый Husky. После переключения
CMake cache на новый prefix backend пересобран и прошёл **350/350**, без пропусков,
59,59 секунды. Текущий Linux/macOS CI использует именно этот bootstrap, но
его запуск на GitHub ещё не выполнялся. Полные upstream warning logs сохраняются
в сжатом CI-артефакте, а не отключаются.

Собран и распакован validation server tar.gz macOS arm64 (Debug). Проверены
отсутствие ссылок на Homebrew/рабочие пути в runtime dependencies, загрузка
сервера до ожидаемого отказа на отсутствующем конфиге, исходные архивы и лицензии,
вложенные объектные файлы, успешная перелинковка трёх бинарников и загрузка
перелинкованного сервера. Первый холодный старт ждал проверки ad-hoc подписей
в dyld около 13 секунд; повторный быстрый запуск корректен. Это не был deadlock
в gRPC. Для smoke используется 30-секундный бюджет старта.

Серверный validation-пакет требует macOS 26.0 из-за локальных библиотек;
клиентский DMG сообщает macOS 15.0. Это локальные результаты, не доказательство
работы server Release на macOS 15. Пересборка/проверка всей release-матрицы
остаётся обязательной до объявления публичного набора готовым.

Release environment разрешает master/v* без ручного approval; через GitHub API
проверены active tag rulesets (stable creation владельцем, update/delete v*
запрещены). Master пока нельзя назначить default в пустом репозитории. Секреты
Android не добавлялись, публикация выключена.


## Первый публичный PR: проверки GitHub CI (20 октября 2026)

Новая публичная история начинается коммитом `137312c`; старая история и рабочее
дерево сохранены отдельно. [PR №1](https://github.com/hashev/ffido/pull/1) открыт
из `codex/prepare-publication` в защищённую `master`. Аудит настроек GitHub,
анонимное скачивание исходников и manifest всех 526 исходных файлов прошли.
Публичный выпуск выключен (`FFIDO_PUBLICATION_READY=false`); Releases не созданы.

Проверенные результаты GitHub runners:

| Компонент | Платформа | Проверки |
| --- | --- | --- |
| Клиент | macOS arm64 и x86_64 | analyze, 230 тестов (2 существующих пропуска), format, release build, DMG, копирование и запуск `.app` |
| Клиент | Windows x86_64 | те же проверки, ZIP, запуск распакованного exe |
| Клиент | Linux x86_64 | те же проверки, tar.gz, запуск под Xvfb |
| Клиент | Android universal | те же проверки, три ABI, встроенная лицензия, установка и запуск APK в эмуляторе Android 35 x86_64 |
| Сервер | Linux x86_64, macOS arm64 и x86_64 | build, 350/350 CTest с настоящим HPT без пропусков, format/clang-tidy, generated proto, tar.gz и полный smoke |
| Инструменты выпуска | Linux | 18 тестов экспорта, метаданных, настроек GitHub, публикации, лицензий и повторной линковки |

Клиенты, инструменты, серверы Linux/ARM macOS проверены в
[прогоне 39342682660](https://github.com/hashev/ffido/actions/runs/39342682660).
Сервер Intel macOS также успешно проверен в
[предыдущем задании](https://github.com/hashev/ffido/actions/runs/39340935463/job/118362024364).
Итоговый статус **актуального коммита PR** всегда проверяется через обязательный
`ci-required` в [проверках PR](https://github.com/hashev/ffido/pull/1/checks).

Smoke проверяет SHA-256, распаковывает пакет в новый временный каталог, фиксирует
`ldd`/`otool`, выполняет три команды `relink.sh`, запускает повторно слинкованный
admin и проверяет поставляемые admin/helper/wrapper. Сервер запускается из пакета
на синтетических базах: strict CA verify, HTTP/2 ALPN, отказ без сессии,
Dart gRPC login/read/post, bookmarks и read state. Реальные FTN-базы и amster2
для этих проверок не использовались. Все журналы содержат только тестовые данные;
закрытые ключи и рабочие конфиги в пакеты не включаются.

Выявленные CI различия устранены без отключения проверок: для C++23 backend
закреплён Xcode 26.3; объявления совместимы с clang-format 19/23; нумерация UUE
явно инициализирована перед захватом лямбдой (31 локальный UUE-тест также прошёл).
Переносимая линковка выбирает действующий macOS SDK и удаляет build-only
`--dependency-file` в формах `-Wl` и `-Xlinker`. Идентичность Linux библиотек
сравнивается по исходным байтам до `patchelf`; настоящая коллизия имён остаётся
ошибкой. Windows пути корректно обрабатываются через `url2pathname` и UTF-8.

TLS fixture использует отдельный OpenSSL config с явными CA/server extensions,
SKI/AKI и SHA-256. Локальный smoke дополнительно прошёл с LibreSSL 3.3.6 и
OpenSSL 3.5.9; macOS CI использует Homebrew OpenSSL CLI. Проверка сертификатов
и авторизации сохранена. Регрессии проверяют обработку linker-аргументов,
выбор SDK и изменяемые копии библиотек.

Пакеты пока являются временными артефактами CI. Desktop не подписан издателем
(macOS ad-hoc); APK имеет только тестовую подпись. Постоянный Android release-key
нужен перед включением публичного выпуска. Apple/Windows сертификаты и
публичная загрузка Releases в этой задаче не проверялись.

## Управляемые обновления: проверки 21 октября 2026

Изменение `add-managed-updates` находится в реализации. Проверки выполнялись
с Flutter 3.47.7 / Dart 3.13.5 и Python 3.15 в `build/update-venv`;
cryptography закреплена на 50.0.2. Production private key не создавался,
`scripts/update/public_keys.json` пока пуст: публичный выпуск намеренно
останавливается до настройки доверенного ключа по docs/github-publication.md.

Локальные результаты:

- 34 release-теста и 40 updater-тестов прошли. Проверены подписи, replay,
  выбор версии/платформы, traversal и лимиты архивов, переключение комплекта,
  блокировки, отказ миграции, журналы и совместимый rollback.
- `flutter pub get`, `flutter analyze --no-pub` прошли; 247 Flutter-тестов
  прошли, два существующих теста пропущены. Проверка форматирования 96 Dart
  файлов прошла. Использовался SDK `/Users/yurik/development/flutter-3.47.7`.
- Корневая CMake-сборка прошла. Обязательный wrapper check_ctest.py с
  FFIDO_TEST_HPT выполнил все 351 тест без пропусков. clang-format/clang-tidy:
  99 файлов / 51 translation unit. Native TLS gRPC acceptance прошёл,
  включая отказ readiness при неверном имени сертификата.
- Android release A→B (versionCode 41001→41002) реально выполнен через
  FFIDO native bridge / PackageInstaller на изолированных arm64 эмуляторах
  API 24, API 25 и API 36. Сохранены отдельный sentinel preferences и синтетическая
  сессия SecureSessionStore. Проверены STATUS_PENDING_USER_ACTION, отмена,
  чужой сертификат, другой package ID, равный и меньший versionCode; на API 36
  также отказ и выдача разрешения неизвестного источника. APK собраны с R8
  в release mode и переподписаны одним эфемерным RSA QA-ключом; это не выпуск
  с production release-key. Ключи удаляются в finally. Результаты:
  build/managed-updates-android-release-qa5/result.json и
  build/managed-updates-android-release-api24/result.json и
  build/managed-updates-android-release-api25/result.json.
  На API 36 Play Protect предложил сканирование незнакомого тестового ключа;
  выбран штатный Install without scanning, APK во внешний сервис не отправлялся.
  Play Protect глобально не отключался; API 24 использовал штатную глобальную
  настройку разрешения неизвестных источников в тестовом эмуляторе.
- Release-проверка выявила и устранила две ошибки: R8 менял имена Kotlin
  JNI descriptor/runtime classes для shared_preferences 2.5 / jni 1.1,
  а Directory.systemTemp Dart не совпадал с разрешённым Android cacheDir.
  Теперь действуют точечные keep rules без отключения shrinker; путь private
  staging сообщает native bridge. Проверка принадлежности APK кешу сохранена.
- Собран локальный linux/amd64 Docker image `ffido:managed-updates`.
  Container smoke проверил TLS, внешнее состояние и сохранность сессии,
  SQLite, сообщения, metadata/uploads после пересоздания. Дополнительный
  A→B smoke прошёл с образом B, отличающимся version/build metadata при том
  же бинарнике; это не проверка обновления между различными версиями кода.
  Дополнительно из текущих серверных исходников собран
  ffido:managed-updates-final (v1.0.1/build 41002), Docker build выполнил все
  351 CTest без пропусков. Container smoke старый A→свежий B прошёл,
  включая сохранность сессии/SQLite/сообщения/metadata/uploads и readiness
  с отказом при неверном TLS имени; это два отдельно собранных бинарника.
  Лог: build/managed-updates-container-final-upgrade.log.

macOS использует Sparkle 2.10.0 и сохраняет sandbox. Ранний Cocoa probe A→B
с ad-hoc подписями подтвердил замену bundle и ограничение legacy Keychain:
запись читалась A, а B при запрете системного UI получил errSecAuthFailed
(-25293). Пользователь согласовал системный запрос Keychain или повторный
вход после обновления. Настройки остаются на месте, токены не переносятся
в незащищённое хранилище. Рабочие записи и пароли не использовались;
отдельная тестовая запись удалена.

Сквозной Flutter macOS QA запускается отдельно:

```sh
build/update-venv/bin/python scripts/update/test_macos_flow.py \
  --flutter /path/to/flutter \
  --directory build/mac-update-qa-arm64 --architecture arm64
```

Сценарий создаёт два реальных Flutter sandbox bundle A/B с отдельными bundle ID
и эфемерным ключом, подписывает DMG и appcast, запускает default/p2 и проверяет
блокировку установки занятым профилем, повтор, восстановление обоих профилей и
preferences. Loopback HTTP разрешён только при compile-time
FFIDO_UPDATER_TESTING в QA-сборке; обычная сборка принимает только HTTPS GitHub.
Для x86_64 используется отдельный каталог и `--architecture x86_64`.
После QA нужно восстановить обычную сборку `flutter build macos --release`.
Не считать саму сборку доказательством успешной установки: результат успешного
QA записывается в result.json, отсутствие этого файла означает незавершённый тест.

Настоящий Flutter A→B с подписанным DMG успешно выполнен на arm64 и
x86_64 (Rosetta на arm64-хосте), без снятия sandbox. В обоих случаях сначала
проверен отказ при занятом p2, затем одна установка, перезапуск default/p2 и
сохранность отдельных preferences. Доказательства:
`build/managed-updates-macos-qa8/result.json` и
`build/managed-updates-macos-qa-x64/result.json`.
Sparkle наблюдает один процесс, поэтому peers согласованно закрываются перед
созданием его updater и открываются снова при ошибке. Для восстановления
профилей применяется очередь в private container: sandbox игнорирует
[NSWorkspace OpenConfiguration.arguments](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/arguments).
Обычная production-сборка из lib/main.dart восстановлена после QA, без QA
bundle ID, ключа и loopback-разрешения. Реальный package.py сформировал arm64
DMG; smoke.py проверил его checksum, identity, build number, embedded Sparkle,
sandbox/XPC entitlements, обязательную проверку подписанного feed/архива,
затем запустил извлечённое приложение с изолированным профилем. Проверка прошла
(`build/managed-updates-macos-package-smoke.log`). Публичный ключ в этой локальной
сборке пуст, поэтому она не может установить неподписанное обновление.

Системное подтверждение legacy Keychain после настоящего Flutter A→B остаётся
ручной проверкой; ранний probe подтвердил ожидаемое ограничение ad-hoc.

Остаются обязательными реальные Windows/Linux A→B полного desktop bundle,
публичный Android release-key и полный запуск CI, проверка macOS на физическом Intel-хосте и запуск итоговой платформенной CI-матрицы. Они не
отмечаются завершёнными по результатам unit-тестов или одной сборки.


Установленный native CLI дополнительно проверен через настоящий fidoback
(не прямым вызовом Python-функции): macOS arm64 и Linux x86_64. На отдельном
managed layout с тестовыми доверенными ключами выполнены --version,
отказ apply при удерживаемом running lock, apply 1.0.0→1.0.1 и rollback.
Хеши синтетических SQLite/JAM не изменились. Для macOS использован корневой
CMake install; для Linux — копия полного runtime из свежего образа, без
container marker только в тестовых копиях native layout. Service managers
в этой проверке не запускались; stop/start/readiness отдельно проверены
native/container acceptance. Результаты:
`build/managed-updates-native-qa/mac-flow2/result.json`,
`build/managed-updates-native-linux-result.json`.

Проверка отказа SecureSessionStore дополнена тестом реального initializeApp:
PlatformException не блокирует экран входа и не удаляет адрес/имя/endpoint.
macOS получает инструкцию Keychain/повторного входа, Android — сообщение о
защищённом хранилище без упоминания Keychain. Оба случая прошли.


macOS negative QA прошёл на настоящих Flutter release bundle: запуск из
read-only DMG вернул Sparkle 1003 с инструкцией переноса в Applications,
A и preferences сохранились. Подписанный правильным feed-ключом appcast
с неверной подписью DMG отклонён Sparkle (4005, improperly signed), A не
заменён. NSError recovery suggestion теперь передаётся в Flutter вместе
с domain/code, поэтому пользователь видит способ продолжения.
Доказательства: build/managed-updates-macos-readonly2/result.json и
build/managed-updates-macos-bad-signature2/result.json.


Linux x86_64: полный Flutter bundle собран на Ubuntu 24.04 в отдельном Docker
контейнере под эмуляцией amd64. Frozen updater с закреплёнными dependencies
собран PyInstaller и реально выполнил A→B, проверил подпись и весь tar.gz,
запустил новый Flutter, получил подтверждение первого рабочего кадра и
сохранил внешний state и файл preferences. В тесте добавлен sentinel и cache
в настоящий preferences JSON: B прочитал его, очистил только cache и сохранил
sentinel. A/B используют один Flutter binary с разными подписанными metadata
и embedded identity; Windows ZIP ещё требует реального прогона.
Результат: build/managed-updates-linux-qa/flow3/result.json, A.log/B.log/freeze.log.
Повторная сборка Linux под эмуляцией остановилась с Unexpected EINTR errno;
для frozen-flow использован ранее успешно собранный и сохранённый bundle.
Это ограничение повторной сборки, не успешная проверка всей CI-матрицы.

При проверке desktop исправлены неподдерживаемый --parent, отсутствие
startup acknowledgement и размещение lock внутри заменяемого каталога.
Теперь running/operation locks находятся рядом с установкой, operation lock
удерживается до подтверждения запуска, а running lock не мешает старту B.
--preflight проверяет права до завершения клиента. Recovery распознаёт
prepared/switched journal, возвращает прежний комплект и позволяет повторить
операцию после сбоя между rename; чужой backup/root не заменяется.
40 updater unit-тестов включают ENOSPC со staging cleanup и повтором,
read-only parent, live process/operation lock, recovery и отказ чужой identity.

CI дополнен реальными Android release QA на API 24/25/35, frozen desktop QA
на Linux/Windows и installed native CLI apply/rollback на Linux/macOS.
Новый CI-код локально проверен actionlint/bash -n, удалённый CI не запускался.
Windows QA предназначен для одноразового CI-профиля, поскольку Windows known
folders не изолируются одной подменой APPDATA. Реальный signed registry/Compose
check→apply→rollback и Windows x86_64 A→B остаются непроверенными.

Итог локального этапа 2026-10-21: пользователь подтвердил отсутствие
одноразового Windows-окружения и Linux с systemd. Поэтому задачи 5.1–5.3,
6.5, 7.4 и 8.2 остаются открытыми; успешные частичные проверки выше
не заменяют их полные критерии. Финально прошли flutter analyze, 247 Flutter
тестов (2 пропущены), 40 updater и 34 release Python-теста; обычные release
сборки macOS и Android успешно собраны. Свежая Docker-сборка выполнила
351 CTest. Коммиты, публикация и удалённый CI не выполнялись.


Продолжение локальной приёмки 2026-10-21: registry/Compose полностью прошёл
на loopback registry: docker run → Compose с теми же четырьмя bind mounts
и UID/GID → check → apply v1.0.0→v1.0.1 → rollback. После каждого перехода
реальный Flutter ApiClient восстановил сессию, сообщение, read metadata,
bookmark и загрузку. Исходный Compose и ID соседнего контейнера не изменились; фактические mounts,
UID/GID и привязки портов также совпадают после apply и rollback.
Неверная Ed25519-подпись отклонена до остановки, несовместимая schema — без
переключения с повторным стартом A. Доказательство:
`build/managed-updates-compose-qa5/result.json`, команды в `commands.log`.
Скрипт: `scripts/update/test_compose_flow.py`, повтор по docs/docker.md.
Этот прогон снимает прежнее ограничение о непроверенном registry/Compose.
GitHub transport заменён fixture, registry allowlist — адресом loopback только
в QA-копии; production код/ключи не менялись. Внешней публикации нет.
A использует старый compiled server с QA-normalized BUILD/OCI identity,
B — свежий compiled server; bind mounts в этом сценарии работают с UID/GID 0:0.

macOS launchd также проверен: собственный временный LaunchAgent запускает
полный managed server, running apply отклоняется; bootout → apply → bootstrap
→ TLS gRPC readiness и bootout → rollback → bootstrap → readiness успешны.
После остановки скопированы синтетические SQLite/JAM; sentinel и integrity_check
подтверждены в backup и текущем состоянии после A→B→A. HPT в fixture не работает,
его совместная остановка не заявляется проверенной. Результат:
`build/managed-updates-launchd-qa3/service-result.json`, daemon/service-command logs.
Скрипт: `scripts/update/test_service_flow.py --bundle <native bundle> --directory <new directory>`.
Задача 6.5 остаётся открытой из-за systemd/Linux и полного сценария с HPT;
Windows и удалённая CI-матрица также остаются открытыми.


Итоговое ревью add-managed-updates (2026-10-21): исправлены следующие ошибки.

- При повторной проверке уже обнаруженного C более старый B, который всё ещё
  новее установленного A, больше не блокирует результат из-за sequence.
  Источник только с устаревшими кандидатами по-прежнему даёт ошибку.
  Исправлены Python discovery и Flutter UpdateService; проверены оба порядка
  B/C. Исторические версии пропускаются до проверки подписи, чтобы удалённый
  после ротации старый ключ не блокировал новые выпуски. Новые кандидаты
  по-прежнему требуют корректную подпись и совпадение manifest/tag/assets.
- Desktop recovery после ошибки запуска теперь использует общий recover с
  running lock. Он не заменяет каталог B поверх нового открытого окна и
  сохраняет сообщение для следующего запуска. Регрессия проверяет сохранность
  B и backup A при занятой блокировке, без повторного запуска клиента.
- Compose сохраняет подписанные manifest/signature до остановки A и до
  публикации prepared journal; ошибка записи этих файлов не останавливает A.
  Ошибка записи журнала/override после остановки запускает A снова.

Повторный сквозной loopback registry/Compose после исправлений прошёл:
`build/managed-updates-compose-review/result.json`. Production trust anchors
и allowlist не менялись. Windows/systemd и полная удалённая CI-матрица
остаются открытыми; 25/30 задач. Коммиты и внешняя публикация не выполнялись.

Проверки после ревью: flutter analyze без замечаний; 248 Flutter-тестов успешно,
2 пропущены; 45 updater и 34 release Python-теста успешно; Dart format,
Python compile, строгая валидация OpenSpec и whitespace-проверка изменённых
файлов прошли. C++/Kotlin/Swift в этом ревью не менялись; новые платформенные
сборки и CTest повторно не запускались.

Проверка release-сборок после итогового ревью (2026-10-21): Flutter 3.47.7
pub get, build macos --release и build apk --release выполнены успешно.
Android universal APK 55 587 425 байт: apksigner verify успешен (v2),
io.github.hashev.ffido, minSdk 24, armeabi-v7a/arm64-v8a/x86_64;
встроенные identity и trust anchors совпадают с исходниками.
Это локальный release-mode APK с Android Debug certificate, не публичная
сборка с постоянным release keystore.

macOS arm64: сырой Flutter .app после incremental build не прошёл строгую
проверку внешнего seal (App.framework); после пересоздания bundle seal также
не включал добавленный Sparkle.framework. Поэтому проверен именно конечный
DMG, созданный штатным scripts/release/package.py: его существующий шаг
ad-hoc codesign --force --deep --preserve-metadata=entitlements --sign -
формирует окончательный seal. Приложение из read-only mounted DMG успешно
прошло codesign --verify --deep --strict. Sandbox, application ID,
Sparkle Installer.xpc/Downloader.xpc и встроенная identity проверены.
Сырой Flutter .app без финального packaging/signing не предназначен для раздачи.
В этом прогоне x86_64 macOS не пересобирался, новую установку A→B не выполняли.

Машиночитаемый результат и SHA-256:
build/managed-updates-release-final-result.json; логи release-final-* в build/.
Production trust anchors по-прежнему пусты, локальная identity check-only:
обновления и публичный выпуск не включены. Готовность: локальная реализация
и доступная приёмка подтверждены, публичный выпуск пока не готов. Остаются
25/30 задач; Windows (5.1–5.3), systemd/Linux и полный HPT backup-сценарий
(6.5), полная удалённая CI-матрица (8.2) не закрыты. Ключи выпуска требуют
отдельного provisioning по docs/github-publication.md. Коммитов, внешней
публикации и запуска удалённого CI не было.

Реальная установка release A→B после итогового ревью (2026-10-21):

- macOS arm64 и x86_64 (Rosetta на ARM Mac): два настоящих ad-hoc release bundle
  с разными CFBundleVersion 1→2, подписанный одноразовым QA Ed25519 ключом DMG,
  установка Sparkle и перезапуск двух профилей default/p2. Занятый p2 блокирует
  обновление; после разрешения оба процесса запускаются как B. Сохранены marker,
  endpoint, имя и адрес каждого профиля. A записала и прочитала разные синтетические
  токены настоящим SecureSessionStore в legacy login Keychain; B не перезаписывала
  токены и прочитала прежние значения (SecItemCopyMatching status 0 для обоих
  профилей на обеих архитектурах). Повторный вход в успешных прогонах не потребовался.
  Проверка чтения B выполняется QA-only native probe с теми же account/service,
  что у SecureSessionStore; она не обращается к серверу и не проверяет server-side
  срок действия синтетического токена. Системные настройки Keychain не менялись,
  SecurityAgent автоматически не подтверждался. В текущем QA probe используется
  LAContext.interactionNotAllowed; production SecureSessionStore не менялся.
- Android API 36 arm64 emulator: настоящие release APK 41001→41002, один
  одноразовый QA сертификат, PackageInstaller и стандартное подтверждение ОС.
  После запуска B SharedPreferences и токен настоящего SecureSessionStore
  совпали со значениями A. Пройдены permission denial, permission grant,
  STATUS_PENDING_USER_ACTION, отмена установки, отказ чужого сертификата,
  package ID, равного и меньшего versionCode. Play Protect предложил scan
  неизвестного QA сертификата; использован штатный Install without scanning,
  APK в Google не отправлялся. Первый прогон прерван конфликтом диагностики
  UIAutomator (exit 137); повтор прошёл полностью, это не ошибка APK.

Доказательства:
- build/managed-updates-macos-ab-final-arm64/result.json
- build/managed-updates-macos-ab-final-x86/result.json
- build/managed-updates-android-ab-final-api36-retry/result.json и device.log

Сценарии используют отдельные QA entrypoints с текущими production bridge/updater,
синтетические сессии, уникальный macOS bundle ID и зарезервированный invalid
endpoint. Live-аккаунты не использовались. Удалены только созданные QA Keychain
accounts, временные Android keystore/password; эмулятор и QA-процессы закрыты.
Тестовые публичные ключи в production trust store не добавлялись.
Эти результаты снимают прежнее ограничение release-final-result.json о том,
что после последнего ревью новая установка A→B не выполнялась.
Windows/systemd и полная CI-матрица остаются открытыми; коммитов и внешней
публикации не выполнялось. Количество закрытых задач остаётся 25/30.

После QA восстановлены обычные main-target release-выходы macOS и Android
(application ID io.github.hashev.ffido, build 1). Обе сборки успешны.
Flutter analyze чистый; 248 Flutter-тестов успешно (2 пропущены),
45 updater Python-тестов успешно, Dart format/Python compile/OpenSpec strict
и whitespace-проверки прошли.

Подключение production trust anchor (2026-10-21): публичный ключ
ffido-prod-2026-01 из внешнего update-public.json добавлен в
scripts/update/public_keys.json и выбран через settings.json:update_key_id.
Штатным build_identity.py обновлены только публичные client assets и Sparkle
xcconfig; существующие локальные identity сохранены (check-only build).
Приватный seed читался только локально в память для --check-only и load_key;
его содержимое не выводилось, не копировалось в checkout и не передавалось GitHub.
Проверены совпадение пары и локальная подпись/верификация служебного challenge,
который не является release manifest. Подпись challenge не сохранялась.

Release macOS и Android собраны с подключённым публичным ключом. Реальные
встроенные public_keys.json обоих клиентов совпали с источником; macOS
Info.plist:SUPublicEDKey совпал с выбранным ключом. Android APK в этом локальном
прогоне использует обычный debug signing, production Android signing job не
запускался. Flutter analyze чистый, 248 Flutter-тестов успешно (2 пропущены),
42 release и 45 updater Python-тестов успешно, OpenSpec strict прошёл.
Тест resume Docker теперь использует изолированный trust anchor вместо
предположения, что production trust store пуст.

Read-only проверка GitHub на этом этапе:
- Repository FFIDO_PUBLICATION_READY уже равен true, значение не менялось.
- Environment release: FFIDO_UPDATE_KEY_ID отсутствует;
  secret FFIDO_UPDATE_PRIVATE_KEY отсутствует.
- Четыре Android secrets присутствуют; ANDROID_CERT_SHA256 совпадает с локальным
  сертификатом ранее использованного release keystore. Содержимое secrets API
  не возвращает, поэтому их значения удалённо не проверены.

Локальная production-конфигурация согласована, GitHub provisioning не завершён.
До подготовки полного выпуска рекомендуется FFIDO_PUBLICATION_READY=false.
Полный publish.py --check-only по inventory не запускался: Windows/полная
CI-матрица остаются открытыми. Коммитов, запусков workflow, внешней публикации
и изменений GitHub settings не выполнялось. Результат:
build/managed-updates-production-config-result.json; read-only GitHub snapshot:
build/managed-updates-production-github-check.json (только имена secrets и
публичные variables). Этот этап заменяет прежние записи о пустых trust anchors.


Реальный локальный A→B с production-ключами (2026-10-21):

- macOS arm64 и x86_64/Rosetta: appcast и DMG подписаны ключом
  ffido-prod-2026-01 из внешнего каталога ключей; Sparkle установил release
  bundle 1→2 и восстановил default/p2. Busy peer блокирует установку до
  разрешения. Настройки endpoint/name/address/marker обоих профилей сохранились.
  A записала и прочитала синтетические токены настоящим SecureSessionStore;
  B не переписывала их, SecItemCopyMatching вернул прежние значения/status 0.
  Повторный вход в этих прогонах не потребовался.
- Android API 36 и API 25: APK 41001→41002 подписаны существующим постоянным
  сертификатом 61f1f10c15f8d3724dfe19938f9923ed2878dd9c81113c90489aded29af3fbd0.
  QA entrypoint проверяет release-manifest.json/signature библиотекой
  UpdateManifest.verify со встроенным production Ed25519 anchor, размером и
  SHA-256 APK перед передачей native installer. PackageInstaller обновил A→B;
  SharedPreferences и токен реального SecureSessionStore сохранились.
  На API 25 исходные A-source/B-source собраны непосредственно через Gradle
  publicRelease/FFIDO_PUBLIC_RELEASE=true; подпись исходников проверена отдельно
  до/независимо от завершающего apksigner. На API 36 использовано финальное
  переподписание release-mode APK постоянным ключом.
- Пройдены отмена, STATUS_PENDING_USER_ACTION, отказы чужого сертификата/ID,
  равной и меньшей версии; API 36 дополнительно проверяет denial/grant источника.
  Play Protect на API 36 предложил scan: выбран штатный Install without scanning,
  APK не отправлялся Google.

На API 25 стенд слишком рано вызвал am start -W: versionCode уже изменился,
но завершающий broadcast pkg removed остановил ранний запуск. Повтор обычного
Open после завершения замены запустил B и подтвердил сохранность данных. Это
гонка стенда; launch_updated теперь повторяет неблокирующее открытие с ограничением
по времени. Два регрессионных теста проверяют повтор и timeout без ложного успеха.

Доказательства: build/managed-updates-prod-ab-result.json и отдельные result.json
в managed-updates-prod-ab-macos-arm64, managed-updates-prod-ab-macos-x86,
managed-updates-prod-ab-android25, managed-updates-prod-ab-android36. Проверка
Gradle certificates — android25/gradle-signing-result.json.

Это изолированные QA entrypoints с текущими production bridge/updater и настоящими
ключами; не публичные release candidates. macOS bundle ID уникален для стенда,
Android запускается только на выбранных одноразовых эмуляторах. Сессии синтетические
в реальных хранилищах; live-account/server-side token validity не проверяется.
Fixtures обслуживаются loopback HTTP, GitHub/CDN discovery этим прогоном не
проверяется. Приватные seed/keystore не копировались в QA output и не выводились;
пароли передаются apksigner/Gradle через environment, а ключевые файлы читаются
на месте. Синтетические Keychain accounts и временные foreign keys удалены.
FFIDO_PUBLICATION_READY проверен read-only: false. Windows/systemd и полная
CI-матрица открыты; коммитов, workflow dispatch и публикации нет.

Финальные проверки этапа production-key A→B: обычные main-target macOS/Android
release-выходы восстановлены; Android собран через Gradle publicRelease,
постоянный сертификат конечного APK подтверждён. Это локальные check-only
identity, не готовые к публикации release candidates. Flutter analyze чистый,
248 Flutter-тестов успешно (2 пропущены), 47 updater Python-тестов успешно;
Dart format, Python compile, OpenSpec strict и whitespace-проверки прошли.
В 61 текстовом QA output не найдено production seed/паролей Android; SHA-256
production keystore совпадает с исходными метаданными. Приватные значения при
проверках не выводились. Количество задач остаётся 25/30.


Итоговое ревью после подключения production-ключей (2026-10-21):

1. Исправлен silent fallback build_identity.py: опечатка в update_key_id или
   несколько anchors без выбора раньше давали пустой SUPublicEDKey. Теперь
   generator и signer используют select_update_key; проверяются все key IDs,
   canonical Base64/32 bytes и выбранный ID. Неверная конфигурация останавливает
   генератор до изменения identity, assets, xcconfig или GITHUB_ENV. Tests
   запускают настоящий generator в изолированном дереве и проверяют отсутствие
   частичных записей; отдельный valid case проверяет экранирование slash.
2. QA output directory теперь обязательно новый, с правами 0700, без пересечения
   с production key directory. Старый result.json нельзя принять за новый
   успешный прогон после ошибки. Тесты подтверждают сохранность прежнего отчёта
   и каталога ключей при отказе.
3. macOS cleanup находит все процессы точного пути изолированного bundle,
   включая перезапущенный B до записи status JSON; похожий путь fido2 и
   обычный /Applications/fido.app не затрагиваются.

Проверены текущие production key selection, локальный signer и настоящий
generator с публичной конфигурацией в изолированном дереве. Приватный seed
не выводился и не копировался. Read-only GitHub check подтвердил key ID
ffido-prod-2026-01, наличие секрета и FFIDO_PUBLICATION_READY=false; удалённые
настройки не менялись.

Проверки: 46 release и 50 updater Python-тестов успешно; Flutter analyze
без замечаний, 248 Flutter-тестов успешно (2 пропущены), Python compile и
OpenSpec strict прошли. Изменены tooling/QA и документация; native/client
установщики не менялись, release-сборки и реальные A→B в этом ревью повторно
не запускались. Предыдущие production-key A→B proofs сохраняют силу, ключи
не изменены. Windows/systemd и полная CI-матрица остаются открытыми; 25/30.
Коммитов, публикации и workflow dispatch не было.


Повторные реальные production-key A→B после последних исправлений (2026-10-22):

- macOS arm64 и x86_64 через Rosetta: release A build 1 → B build 2
  установлены Sparkle из DMG с production Ed25519-подписью. Настройки двух
  профилей сохранены; занятый профиль блокирует замену до разрешения.
  A записала и прочитала сессии через SecureSessionStore, B прочитала те же
  значения из login Keychain: preserved=true и keychain_status=0 для обоих
  профилей на обеих архитектурах. Повторный вход не потребовался.
- Android API 25 и 36: release A versionCode 41001 → B 41002 установлены
  системным PackageInstaller. Обе пары исходных Gradle APK (A-source/B-source)
  подписаны постоянным production-сертификатом. Клиент проверил манифест
  production Ed25519-ключом; настройки и защищённый токен сохранились.
  Отмена установки, чужие сертификат/applicationId, равная и меньшая версия
  отклонены; API 36 дополнительно проверяет отказ разрешения установки.
  На API 25 исправленный retry запуска B сработал без ручного открытия.
  На API 36 выбрана локальная установка без отправки APK в Play Protect.
- Каждый прогон использовал новый отдельный каталог; все четыре процесса
  завершились с кодом 0. Отчёты: build/managed-updates-prod-recheck-{macos-arm64,
  macos-x86,android25,android36}/result.json; сводный отчёт:
  build/managed-updates-prod-recheck-result.json. QA-эмуляторы остановлены.

Это реальные release-бинарники с QA entrypoint, локальным HTTP fixture и
синтетическими сессиями в настоящем защищённом хранилище. Проверена сохранность
токенов, а не их авторизация на живом сервере; загрузка с публичного GitHub/CDN
в этот локальный прогон не входит. Windows/systemd и полная CI-матрица остаются
открытыми; задачи OpenSpec 25/30. Коммитов и публикации не было.

После QA восстановлены обычные main-target release-выходы macOS и Android;
Android APK повторно проверен по production-сертификату. Identity остаётся
локальной check-only, эти выходы не предназначены для публикации.
Дополнительные проверки: 46 release + 50 updater Python-тестов прошли,
Flutter analyze без замечаний, OpenSpec strict и whitespace checks прошли.
В 62 текстовых QA output не найдено production seed/паролей; keystore SHA-256
не изменился. Контролируемых macOS QA-процессов после cleanup не осталось.


Отправка add-managed-updates в PR и первые CI findings (2026-10-22):

- В экспорт добавлен deploy/ с regression test: Compose-конфигурация входит
  в checkout для PR. Несвязанный архив prepare-github-publication исключён.
- Widget-тест уведомления теперь завершает настоящий desktop startup I/O через
  tester.runAsync до проверки UI. На Linux/Windows виртуальное время Flutter
  не дожидалось filesystem futures; проверки уведомления/черновика сохранены.
  Повторный CI подтвердил 248 passing Flutter tests и 2 существующих skip.
- Windows smoke выявил WinError 32 при удалении .ffido-ready: Flutter ещё держал
  handle записи. Теперь маркер публикуется rename временного файла после
  завершения writeAsString, поэтому updater видит только закрытый целый файл.
  Локально после исправления analyze и 17 update Flutter-тестов прошли;
  результат повторной Windows smoke должен оцениваться по последнему CI SHA.

Windows/systemd acceptance остаются открытыми. PR не означает merge или выпуск;
FFIDO_PUBLICATION_READY=false, публикация и workflow Release не запускались.


### Сверка приёмки после первого managed prerelease (2026-10-22)

Эта запись актуализирует прежние отметки об открытых Windows/CI-проверках;
исторические результаты выше сохранены.

- **5.1 и 5.3:** в CI на Windows x86_64 и Linux x86_64 успешно выполнены
  `test_desktop_flow.py` и smoke упакованного клиента. Замороженный отдельный
  updater заменяет весь ZIP/tar.gz bundle с DLL/lib/data, запускает B,
  подтверждает readiness и сохранность внешнего состояния/preferences.
  README описывает полную распаковку и первый ручной переход на updater.
  Windows-отчёт: `build/windows-timeout-fixed-diagnostics/result.json`;
  журнал подтверждён, helper завершился, B продолжает работать без DLL из
  временного runtime PyInstaller. Это один Flutter-бинарник с различными
  метаданными A/B, а не две независимо собранные версии и не проверка
  защищённой Windows/Linux-сессии.
- **5.2:** `scripts/update/test_desktop.py` покрывает неверные подпись/пакет,
  неполный bundle, отказ между rename и восстановление после прерывания,
  нехватку места, read-only каталог, параллельный updater, работающий процесс,
  ошибку запуска B и безопасный rollback. Эти тесты и desktop smoke прошли
  в CI; исходная причина Windows timeout устранена без увеличения таймаута.
- **8.2:** полная матрица прошла на master `a564b0f`:
  [CI после merge](https://github.com/hashev/ffido/actions/runs/39761453319)
  и [Release](https://github.com/hashev/ffido/actions/runs/39766799249).
  Локальные сохранённые результаты: `build/managed-updates-master-ci-result.json`
  и `build/managed-updates-first-prerelease-ci-result.json`.
  Реальные macOS arm64/x86_64 A→B с двумя профилями и Android API 25/36
  release A→B с production-ключами подтверждены отдельной записью выше и
  `build/managed-updates-prod-recheck-result.json`: настройки и токены
  сохранены в настоящих защищённых хранилищах. Сессии синтетические;
  авторизация живого аккаунта и переход между двумя публичными managed
  релизами этим локальным прогоном не проверялись.

**6.5 остаётся открытым:** настоящая systemd-проверка не выполнена.
Эта сверка изменяет документацию и чек-лист, новых сборок/установок,
коммитов и публикации не выполняет. Итог: 29/30 задач, без архивации.

## Закреплённые входы CI

`scripts/release/dependencies.lock.json` — перечень существующих native-ревизий,
CMake-зависимостей и выбранных инструментов. Изменение версии делается явно в lock,
с проверкой совместимого набора Protobuf/gRPC. Не запускайте обновление зависимостей
для устранения промаха кеша. Flutter по-прежнему устанавливает `pubspec.lock` с
`--enforce-lockfile`.

```sh
python3 scripts/release/dependency_lock.py native grpc revision
python3 scripts/release/cache_key.py --describe
python3 -m unittest discover -s scripts/release -p test_cache_key.py -v
```

Fingerprint проверяет профиль Linux Clang 19 либо Xcode 26.3 на macOS и включает
фактические compiler/SDK, target, ABI стандартной библиотеки, версии системных
библиотек и параметры. Нужны C/C++ compiler, CMake, pkg-config и системные re2,
c-ares, OpenSSL, zlib. Для macOS выбирайте требуемый Xcode через `DEVELOPER_DIR`.
Неподдерживаемое окружение завершается с указанием ожидаемого и фактического
профиля; lock не меняется. Метка образа runner и ядро ОС не являются входами.
Подробные значимые входы записываются в `build/native-profile.json`.

Тесты `test_cache_key.py` проверяют совпадение поддерживаемого профиля, отказ для
другого компилятора/Xcode и инвалидацию компонентов по транзитивным зависимостям.
На текущей локальной машине SDK 27.0 отличается от выбранного CI Xcode 26.3;
успешный fingerprint этого CI-профиля локально не подтверждён.

### Кеши сборки и анализа

Workflow `native-dependencies.yml` прогревает компоненты из master (или вручную).
Каждый компонент содержит prefix и соответствующие исходники с completion
manifest. Восстановление проверяет все файлы и checksums, затем собирает общий
prefix и заново создаёт `ffido-cache.cmake`. Cache hit не запускает CMake для
библиотек. Частичный или повреждённый компонент пересобирается; отсутствие кеша
разрешено. Для локального cold build выберите новый `FFIDO_DEPS_WORK`; для CI
удалите соответствующий `native-v2-*` cache через GitHub Actions. Не копируйте
PR-кеши в доверенный namespace. В snapshots входят только сборочные исходники и
prefix, без конфигурации пользователя, FTN-баз и production-ключей.

Backend использует закреплённый ccache 4.14.2 (500 MiB на платформу), который сам
проверяет compiler content, flags и заголовки. Широкое восстановление object cache
не означает совместимость native-prefix: для него разрешены только точные ключи.
C++-анализ кешируется целиком по платформе, исходникам/заголовкам, generated
contracts, compile database, lock, compiler/SDK/ABI, clang-tidy и правилам проверки.
Отрицательные/неполные записи не принимаются. Тесты, сборки и smoke не заменяются
кешированным статусом. После configure/build можно принудительно повторить анализ:

```sh
python3 scripts/release/analysis_cache.py run --force
```

Для команды необходим `build/native-profile.json` текущей сборки. Проверка ключей
и обхода кеша без подходящего SDK выполняется через `test_analysis_cache.py`.

### Общие Android fixtures

В CI producer готовит два QA APK A/B и негативные варианты, затем три отдельных
runner проверяют API 24/25/35. Полный набор пяти APK и `fixtures.json` передаётся
artifact с retention 2 дня; закрытые QA-ключи и password удаляются и не загружаются.
Изменённый SHA, origin, версия или checksum отклоняются. Production-ключи с этим
режимом несовместимы; прежний отдельный ручной production-сценарий сохранён.

```sh
(cd apps/frontend && flutter pub get --enforce-lockfile)
python3 scripts/update/test_android_flow.py --prepare-only --flutter "$(command -v flutter)" --sdk "$ANDROID_HOME" --directory build/android-fixtures
python3 scripts/update/test_android_flow.py --fixtures build/android-fixtures --sdk "$ANDROID_HOME" --serial emulator-5554 --directory build/android-update-qa-local
FFIDO_ANDROID_SMOKE_API=24 FFIDO_ANDROID_FIXTURES="$PWD/build/android-fixtures" bash scripts/release/android_smoke.sh
```

Второй шаг выполнения требует явно выбранного одноразового эмулятора. Полный smoke
также требует Linux/KVM, `RUNNER_TEMP` и упакованный validation APK в build/packages.
QA origin всегда `http://127.0.0.1:8765`; занятый порт считается ошибкой.
Build-tools — 36.0.0. Emulator Linux 37.2.12 и образы x86_64 API 24/default r8,
25/default r1, 35/google_apis r9 закреплены URL и опубликованной Google SHA1 в lock.
`scripts/release/android_sdk.py` проверяет архив и revision перед заменой SDK;
готовые версии кешируются раздельно. ADB повторяет только безопасные команды при
распознанной потере транспорта (не более трёх попыток, до 30 секунд на команду).
Установка APK имеет отдельный лимит 120 секунд без повторной установки; ошибки
установки, приложения и assertions остаются ошибками. UIAutomator XML передаётся
через adb pull и полностью разбирается, очистка logcat ограничена буфером main. Диагностики — artifacts
`android-qa-api*`, `android-fixture-build-logs`; исходная ошибка не маскируется
ошибкой получения logcat.

### Измерение ускорения

Исходный стабильный run: [40305500091](https://github.com/hashev/ffido/actions/runs/40305500091),
SHA `835af21fb1f5fe26c68474c369c13339de1cc880`: native Linux 46м22с, clang-tidy
macOS Intel 19м01с, Android smoke 10м24с, release APK после матрицы 4м21с.
Это baseline одного запуска. После внедрения требуются холодный запуск и три
сопоставимых тёплых PR-прогона без backend-изменений, отдельно backend-изменение.
Сравниваются SHA/матрица, queue/execution, `ci-metrics`, native restore и
runner-minutes. Цель: медиана тёплого execution critical path ≤20 минут,
native restore ≤3 минут. Итоговая серия GitHub-прогонов приведена ниже;
локальные unit-тесты и сборки не заменяют измерение CI.

Онлайн-сводка timings предварительная, пока выполняются metrics и финальные
агрегаторы. Для приёмки нужны окончательные данные Jobs API завершённого запуска:
они включают длительности metrics/gates. Время ожидания зависимостей вычитается
из ожидания runner; runner-minutes означают сумму исполнения без тарифного округления.
На macOS brew не обновляет metadata и уже установленные формулы автоматически;
фактические версии по-прежнему входят в fingerprint.

### Локальная проверка реализации, 26 октября 2026

- Flutter 3.47.7: установка с enforce-lockfile, analyze без замечаний,
  275 пройденных тестов и 2 существующих skip.
- Корневой Debug backend на macOS: 364/364 CTest с настоящим HPT.
- Из одного producer-комплекта fixtures выполнены реальные системные обновления
  A→B на отдельных одноразовых ARM64-эмуляторах API 24 и 25, с сохранением настроек
  и secure session и отклонением негативных APK. API 35 и x86_64 здесь не проверены.
- ccache 4.14.2: повтор идентичной компиляции дал hit, смена flags и compiler —
  miss; результат объекта с изменённым define отличается.
- Native Linux ARM64/Clang 19: холодная сборка всех восьми компонентов прошла;
  повторная проверка/сборка prefix заняла 4,94 с, восемь hits без CMake для библиотек.
  Это локальный BuildKit cache mount, а не время загрузки GitHub cache.
- Архивы Linux emulator 37.2.12 и API 24 x86_64 r8 скачаны и проверены;
  avdmanager создал AVD из установленного таким способом комплекта. Для emulator
  installer создаёт package.xml, который обычно создаётся sdkmanager; без этой
  регистрации generic package не распознаётся. Сам Linux-эмулятор на macOS не запускался.

Первый полный Docker/Linux ARM64 CTest дал 363/364: SIGABRT в
`ProcessTest.SignalsAtIdleAndInstanceLockIsReleased`. Двадцать изолированных
повторов этого теста прошли; причина первого сбоя не установлена. Это ограничение
проверки, а не основание отключать тест или автоматически повторять CI.

Повторный полный Linux ARM64 CTest прошёл 364/364; исходный единичный SIGABRT
остаётся отмеченным как невоспроизведённый сбой. Нативный prefix затем перенесён
в другой каталог с удалением старого пути и build directories библиотек;
CMake заново создал и собрал сервер и helper с новым prefix. Обычная Docker-упаковка
на ARM64 ожидаемо отклонена: поддерживаемый контейнерный пакет — Linux x86_64.
Его сборка/упаковка и полная CI-матрица требуют GitHub runner; обход архитектурной
проверки для локального теста не добавлялся.

Docker использует отдельный профиль, рассчитанный внутри toolchain image.
Компоненты `docker-native-v1-*` переносятся GitHub cache → import target →
BuildKit cache mount; после сборки snapshot target экспортирует их обратно,
и сохраняются только новые завершённые компоненты с совпавшими входами.
Основной image build сохраняет обычный BuildKit cache. Это необходимо потому,
что сам `type=gha` не переносит cache mounts между daemon.

Локально экспортированы 424 MB snapshots, создан новый BuildKit daemon без
локальных слоёв, восстановлены все восемь компонентов, проверены manifest и
точные ключи. Сборка native-prefix на этом daemon дала восемь hits за около
5 секунд без компиляции библиотек. Тестовый builder после проверки удалён.
Workflow прогрева включает Docker-профиль и выполняется из master; его manual
запуск также выбирает master. Эти проверки не заменяют измерение GitHub cache
transfer и целевой Linux x86_64-сборки.

Итоговые локальные проверки: 80 release-tools и 60 updater Python-тестов,
`actionlint`, Python compile и `git diff --check` пройдены. Итоговый набор изменений
проверен на случайные секреты; рабочие конфигурации и FTN-данные не включены.
Целевая Linux x86_64-упаковка, Windows/macOS Intel и GitHub cache transfer/тайминги
остаются предметом CI-приёмки.

### Промежуточное измерение GitHub CI, 26 октября 2026

Source SHA `2df4c4f1e94f35cb0a2d4cf5b95847db79fc5380`, проверенный merge SHA
`e4585851c415a5d88d2b767654ed8fcfe1a449f0`. Оба запуска используют одинаковые
входы и полную матрицу: пять client jobs, три backend jobs, Docker, один producer
APK A/B, три независимых Android API 24/25/35 и обязательные проверки/агрегаторы.
Все задания завершились успешно.

Данные взяты из окончательного Jobs API, включая metrics и финальные gates:
[холодный attempt 1](https://github.com/hashev/ffido/actions/runs/40345336652/attempts/1),
[тёплый attempt 2](https://github.com/hashev/ffido/actions/runs/40345336652/attempts/2).

| Показатель | Холодный | Тёплый №1 |
|---|---:|---:|
| Execution critical path, без очереди | 110 мин 20 с | 20 мин 41 с |
| Суммарное исполнение runner, без тарифных множителей | 364,90 мин | 94,18 мин |
| Максимальное ожидание runner отдельным job, без dependency wait | 37 с | 12 с |
| Backend Linux job | 76 мин 40 с | 4 мин 38 с |
| Backend macOS ARM job | 47 мин 33 с | 7 мин 11 с |
| Backend macOS Intel job | 110 мин 04 с | 20 мин 27 с |
| Docker job | 76 мин 49 с | 4 мин 20 с |
| Native prepare Linux | 59 мин 33 с | 27 с |
| Native prepare macOS ARM | 30 мин 30 с | 44 с |
| Native prepare macOS Intel | 71 мин 34 с | 1 мин 46 с |

Показанные GitHub 1 ч 55 мин 57 с первого запуска включают ожидание отмены
предыдущего PR-прогона до выдачи jobs. Оно отдельно от runner queue в таблице.
Критический путь сократился примерно на 81%; native prepare всех трёх платформ
уложился в 3 минуты. Каждый комплект дал восемь проверенных hits. C++-анализ
переиспользован по точному совпадению входов, CTest и smoke запускались заново;
Docker исполнил тесты с новым `FFIDO_TEST_RUN` для attempt 2.

Первый тёплый критический путь превышает целевые 20 минут на 41 секунду.
На этом промежуточном этапе медиана трёх прогонов и отдельное backend-изменение
ещё не были измерены. Итоговая приёмочная серия приведена ниже.

По журналам подготовлены дополнительные исправления:

- Ccache получал версию `pr.16.e4585851` из GitHub-переменных FFIDO и каждый раз
  отвергал собственный сохранённый бинарник как не соответствующий 4.14.2.
  Только в subprocess его сборки удаляется `GITHUB_REF`, версия выводится из
  закреплённого Git tag. Реальная локальная сборка с окружением PR дала 4.14.2;
  повтор занял 0,06 с и не изменил бинарник.
- Установка Linux GUI-пакетов через Azure mirror заняла 7 мин 50 с в холодном
  прогоне и более 10 минут в тёплом, задерживая старт Android QA. Клиент получает
  тот же официальный Ubuntu archive и ограниченные сетевые таймауты, что backend.
- Backend после brew использовал Python 3.14 вместо объявленного в lock 3.12.
  Подключены закреплённый Python и pip cache по requirements. Для cryptography
  50.0.2 PyPI не публикует macOS Intel wheels: смена Python сама по себе не устраняет
  компиляцию, кеш pip сохраняет собранный wheel для последующих запусков.

Эффект этих дополнительных правок на GitHub пока не измерен. Локально прошли
83 release-tools теста, actionlint, bash syntax и git diff --check; сценарий
ccache проверен реальной холодной и тёплой сборкой с GitHub-переменными.


Отладочный [прогон 7bb0cf3](https://github.com/hashev/ffido/actions/runs/40374891128)
не входит в успешную тёплую выборку: API 25 превысил прежний общий лимит установки
APK 30 секунд, API 24 сообщил ошибку очистки logcat. Артефакты обоих API сохранили
emulator.log и device-all.log после ошибки. Установка Linux GUI-пакетов в этом
прогоне заняла 24 секунды, подтвердив устранение задержки Azure mirror.

При локальной проверке дополнительно воспроизведён обрыв чтения UIAutomator XML
через adb shell cat на 4096 байтах с кодом 255. После замены на adb pull, ограничения
очистки logcat буфером main и отдельного конечного лимита установки APK оба
одноразовых ARM64-эмулятора API 24/25 прошли полный системный сценарий A→B.
62 updater-теста проверяют в том числе отказ при неполном XML и отсутствие повтора
установки после таймаута. Для следующих CI сохранение полного inputs.json анализа
вынесено перед запуском clang-tidy, чтобы можно было объяснять расхождения ключей.

Путь интерпретатора входит в compile database как FFIDO_PYTHON для C++-тестов.
Его смена правомерно инвалидирует полный анализ; при закреплении Python CMake
получает явный Python3_EXECUTABLE из того же окружения, что smoke и скрипты.
Дальнейшие сопоставимые замеры выполняются после стабилизации этих входов.


После завершения отладочного job подтверждено: ключ macOS Intel анализа
22e6aa3a12425735e00ce5ab9e3365369f7d397c79305967ab51eb932fc7ca37 совпал с
предыдущими прогонами, но запись отсутствовала и была создана заново. Поэтому
конкретный промах этого job не объясняется сменой Python или backend-входов.
Cache Usage API сообщил 9 902 644 919 байт и 75 записей; среди них SDK Flutter
занимали 2,22 GB (macOS ARM), 2,22 GB (macOS Intel) и 1,72 GB (Linux).
Это соответствует вытеснению записей при заполнении общего хранилища:
[политика GitHub cache eviction](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#usage-limits-and-eviction-policy).

В build/release отключено сохранение полного Flutter SDK, сохранён отдельный
pub-cache закреплённого action. SDK устанавливается тем же action с той же
версией Flutter из lock; CI не увеличивает платный лимит хранилища. Удаляется
только неиспользуемый SDK-кеш текущего PR, чтобы освободить запас; native,
analysis, pub и кеши других refs сохраняются. Повторные успешные замеры должны
подтвердить, что полезные записи переживают всю матрицу.


Все установки CI Linux-пакетов (portable clang-format, клиент, backend,
container, публикация и прогрев) используют scripts/release/linux_packages.sh.
В подготовительном запуске 566cdd9 все Android API уже прошли, но переносимая
проверка более 30 минут ждала apt update через ещё не заменённый Azure
mirror. Общий helper устраняет это расхождение между jobs без смены пакетов.
Тесты проверяют замену только нужного mirror, сохранение прочих репозиториев,
передачу пакетов/таймаутов и прекращение установки при ошибке update. Пройдены
88 release-tools тестов и отдельный запуск трёх helper-тестов в Linux-контейнере.


Первый полный тёплый запуск 0efeb53 (40386292479/attempts/1) прошёл с критическим
путём 11 мин 54 с и native prepare 25–134 с. Во втором запуске тот же SHA дал
Windows WinError 32 при удалении .ffido-launch-probe в исходном desktop smoke.
Этот ошибочный запуск не входит в успешную выборку; первый остаётся промежуточным
измерением до исправления, окончательная серия начинается заново.

Причина — confirmDesktopStartup вызывался и main после initializeApp, и UpdateShell
в loading/reader UI. Второй читатель мог удерживать probe после появления ready.
Из UpdateShell удалён дублирующий вызов; единственный publisher остаётся после
инициализации main. Удаление файлов и readiness assertions desktop smoke не менялись.
Регрессионный widget-тест проверяет отсутствие probe I/O при создании оболочки;
контрольный post-frame callback подтверждает работу перехвата I/O. Локально прошли
276 Flutter-тестов, 2 существующих skip, enforce-lockfile и analyze без замечаний.


Запуск b7de212 (40391324741) подтвердил исправление Windows readiness, но был
исключён из приёмки из-за ошибки Android API 35: ожидание результата foreign-key
истекло при вытеснении старых Flutter-событий из main logcat. Повторный snapshot
кольцевого буфера менял длину records(), поэтому срез по предыдущему count мог
пропустить новый результат. Assertions и их таймауты не ослабляются.

QA теперь ведёт непрерывный logcat main/flutter в flutter-stream.log, открытый
после очистки буфера и до запуска A. События читаются из сохраняемого файла;
неполная последняя строка ожидает завершения, повреждённый полный JSON — ошибка.
Остановка потока — явная ошибка, завершение reader-процесса ограничено 5 секундами
с последующим kill и конечным ожиданием. Все logs сохраняются прежним artifact
правилом. Пройдены 64 updater-теста и реальные локальные A→B на API 24/25 с
сохранением настроек/session и всеми негативными APK-проверками.


### Итоговая приёмочная серия ускорения CI

Три последовательных полных PR-прогона выполнены без изменений исходников между
attempts: source SHA `5828d7c55028aca35bc0ac2e502fb58348891b1c`, merge SHA
`08c39be33a5b6bed75133ff6c65364a6c1d50a5b`. Каждый завершился success:
18 jobs, пять клиентских целей (Linux, Windows, Android, macOS ARM/Intel), три
backend-платформы (Linux x86_64, macOS ARM64/x86_64), Docker, portable/release-tools,
общая подготовка A/B и отдельные Android API 24/25/35, metrics и итоговые gates.
CTest, packaged smoke и реальные обновления запускались заново в каждом attempt.

| Прогон | Критический путь исполнения | Max очередь runner | Native prepare Linux / ARM / Intel | Docker native prepare | Runner-minutes |
|---|---:|---:|---:|---:|---:|
| [Тёплый 1](https://github.com/hashev/ffido/actions/runs/40395297896/attempts/1) | 12 мин 27 с | 3 с | 39 / 30 / 65 с | 34 с | 75.17 |
| [Тёплый 2](https://github.com/hashev/ffido/actions/runs/40395297896/attempts/2) | 15 мин 58 с | 17 с | 34 / 37 / 110 с | 38 с | 80.02 |
| [Тёплый 3](https://github.com/hashev/ffido/actions/runs/40395297896/attempts/3) | 11 мин 25 с | 63 с | 34 / 42 / 94 с | 29 с | 72.88 |

Медиана критического пути — **12 мин 27 с**, максимум — **15 мин 58 с**:
цель ≤20 минут выполнена всеми тремя запусками. Native prepare включает restore,
проверку целостности восьми компонентов и сборку итогового prefix; максимум
**110 с**, цель ≤180 с выполнена. На каждой из трёх backend-платформ во всех
attempts подтверждены восемь уникальных native hits и точное совпадение полного
набора входов C++-анализа. Хранилище кеша сохраняло 9 799 565 160 байт на каждом
замере; полезные записи пережили повторные полные матрицы.

Очередь в таблице — максимальное ожидание свободного runner отдельной задачей,
без ожидания зависимых jobs; это не слагаемое, которое нужно просто прибавить к
execution critical path. Runner-minutes — суммарное исполнение всех jobs без
тарифных коэффициентов и округлений. Метрики пересчитаны по окончательным Jobs API,
а не по предварительному отчёту ещё работающего workflow.

Холодный [40345336652/1](https://github.com/hashev/ffido/actions/runs/40345336652/attempts/1)
с source `2df4c4f1e94f35cb0a2d4cf5b95847db79fc5380`, merge
`e4585851c415a5d88d2b767654ed8fcfe1a449f0` имел execution critical path
110 мин 20 с и 364,90 runner-minutes (подробности выше). Это исторический холодный
замер до исправлений ccache, Python, mirror, давления SDK-кешей и QA; он не
выдаётся за идентичную финальной конфигурацию. Сопоставимость медианы обеспечена
тремя финальными attempts на одном source/merge SHA. Промежуточные ошибочные
запуски и ранний тёплый 20:41 исключены из этой серии, причины описаны выше.


Отдельный [backend-прогон](https://github.com/hashev/ffido/actions/runs/40401711369/attempts/1) проверил изменение общего заголовка:
source `2dab68057c39b65cb9a94209f6cf2c903feafb97`, merge `c46112a65f79e2035713432f03768d42f423eb23`.
Все 18 jobs успешны; критический путь **30 мин 37 с**, runner-minutes
**113.82**, max очередь runner **4 с**. Native prepare
Linux/ARM/Intel — **35/35/100 с**, Docker prepare — **37 с**. На каждой платформе
сохранены восемь native hits, но получен ожидаемый analysis miss и выполнен
полный C++-анализ. Сравнение artifacts `analysis-inputs-*` с тёплой серией
показало единственное изменение — SHA `apps/backend/include/domain/message.hpp`;
`database`, `native`, `tidy` и остальные файлы идентичны. Это проверка корректной
инвалидации, а не тёплый PR без backend-изменений; время не включается в медиану.
Проверочный комментарий удалён побайтным восстановлением исходного заголовка,
итоговый diff backend пуст. Cache Usage API после этого прогона —
10709392460 байт; для окончательного коммита
дополнительно проверяется повторное использование исходного ключа анализа.

## Текстовый кросспостинг, 27 октября 2026

Добавлены проверки выбора нескольких эх, формата GoldED+, частичного результата,
стабильности operation_id/MSGID и отсутствия дублей после повторов. Серверные
тесты охватывают 1/20/21 дополнительных адресатов, предварительные отказы без
записи, непредставимый текст, REPLY только в исходной эхе, отзыв прав во время
публикации, смену поколения базы, quarantine, конкурентные повторы и снимок
профиля при продолжении. SQLite-тесты проверяют неизменяемый план, изоляцию
пользователей и сохранение после повторного открытия БД. Прогресс группы
определяется по durable дочерним операциям, без отдельного дублирующего флага.

Для воспроизведения отдельного smoke-теста на временных JAM/SQLite-файлах:

```sh
python3 scripts/check_crosspost_acceptance.py \
  --build-dir build/backend --envoy /absolute/path/to/envoy
```

Нужны Dart из закреплённого Flutter, protoc и собранный сервер. Скрипт создаёт
временный CA/сертификат и тестовую конфигурацию HPT, проверяет native TLS gRPC
и бинарный gRPC-Web через штатный TLS Envoy, затем повторяет запросы после
перезапуска процесса сервера, имитируя потерю ответа. Проверяются три копии,
блок Originally/Crossposted, стабильные ссылки/MSGID и ровно два сообщения в
каждой эхе (по одному от каждого транспорта). Секреты не выводятся, рабочие
FTN-базы не используются. Оба транспортных сценария пройдены локально.

Для локальной сборки использован существующий cache preset
`build/publication-deps/prefix/ffido-cache.cmake` с gRPC 1.84 и OpenSSL 3 из
`/opt/homebrew/opt/openssl@3`; системные gRPC 1.85/OpenSSL 4 не соответствуют
этому набору. Dart-проверки выполняются установленным Flutter 3.47.7.
Проверка gRPC-Web здесь выполняется протокольным клиентом через Envoy;
ручная проверка интерфейса в браузере и на устройствах не выполнялась.

Итоговые проверки: Debug-конфигурация и сборка корневого CMake, все 378 CTest
с закреплённым HPT, штатные проверки форматирования и clang-tidy (99 файлов,
51 единица трансляции; изменённый позднее gRPC-тест проверен отдельно),
`tools/proto/generate.sh --check`, форматирование Dart и `flutter analyze --no-pub`
пройдены. Полный Flutter-набор: 296 пройденных тестов и два штатных пропуска платформенных сценариев;
результат полного набора и ограничения относятся к локальной macOS-среде.

## План ускорения CI выпуска кросспостинга 1.0.4

Наблюдение для [прогона 40486774998](https://github.com/hashev/ffido/actions/runs/40486774998):
это первая сборка ветки `codex/echo-crossposting-v1.0.4`, основанной на ещё
не слитом PR #16. Подготовка native-зависимостей Linux началась в 10:14:43 UTC
27 октября и превысила целевые 3 минуты восстановления тёплого кеша.
Cache API показал все три платформенных `native-v2-grpc-*` только в
`refs/pull/16/merge`; новая ветка не может использовать их как кеш master.
Поэтому этот прогон нельзя считать тёплым замером. Суммарный кеш репозитория
на момент проверки занимал 9 388 387 290 байт (181 запись), близко к лимиту;
отдельно нужно контролировать вытеснение полезных записей.

План следующих улучшений и проверки результата:

- [ ] После согласованного слияния #16 прогреть штатным workflow Native dependencies
  доверенные кеши master для Linux x86_64 и обеих macOS; проверить точные ключи,
  manifests, происхождение и отсутствие configure/build/install при hit.
  PR-кеши вручную в доверенную область не переносить.
- [ ] До следующего стабильного тега проверить наличие всех компонентов master
  через Cache API и один сопоставимый PR-прогон: native restore ≤3 минут,
  медиана тёплого критического пути ≤20 минут; отдельно учитывать очередь и
  холодную сборку. Сохранить конечные jobs/metrics, а не промежуточную оценку.
- [ ] Если общий backend-заголовок снова приводит к длительному полному clang-tidy,
  спроектировать повторное использование результатов по единицам трансляции с
  полным транзитивным хешем заголовков, флагов, compiler/SDK и контрактов; доказать
  тестами обязательную инвалидацию зависимых файлов. CTest и обязательные gates
  продолжать выполнять на каждом прогоне.
- [ ] Проанализировать размер и частоту использования compiler/native/analysis кешей.
  После подтверждённого прогрева master очистить только устаревшие PR-записи,
  установить бюджет хранения и предупреждение о близком вытеснении. Не кешировать
  повторно полный Flutter SDK и не удалять активные кеши до появления замены.
- [ ] При подготовке стабильного тега исключать одновременную сборку устаревшего
  dev-релиза того же дерева: отменять только явно заменённый прогон, сохраняя
  полный CI и проверки публикации итогового стабильного выпуска.

### Конечный холодный замер 27 октября

[Ручной CI 40486774998](https://github.com/hashev/ffido/actions/runs/40486774998)
для `56f08324ca992f28bd21d7a1e383bb2906a82d33` завершился неуспешно:
единственная исходная ошибка — clang-tidy macOS Intel в компараторе сортировки
эх (`clang-analyzer-cplusplus.Move`); зависимые агрегаторы также красные.
Остальные платформенные jobs, включая контейнер и Android QA, успешны.
Это не подтверждение готовности релиза: требуется новый полный зелёный прогон.

Конечные данные jobs, рассчитанные штатным `scripts/release/ci_metrics.py`:
критический путь исполнения **91,6 минуты**, суммарно **305,4 runner-minutes**.

| Backend | Native dependencies | Configure/build | C++ checks |
|---|---:|---:|---:|
| macOS ARM64 | 27 мин 20 с | 1 мин 34 с | 5 мин 56 с |
| macOS Intel | 60 мин 52 с | 4 мин 24 с | 16 мин 54 с |
| Linux x86_64 | 36 мин 33 с | 1 мин 53 с | 6 мин 8 с |

Контейнерный job занял 78 мин 2 с. Главная причина длительности этого холодного
прогона — подготовка зависимостей, а не компиляция собственного backend-кода.
Приоритет плана выше: доверенный прогрев master и проверка restore ≤3 минут,
затем сокращение повторного полного C++-анализа. Цели тёплой медианы нельзя
проверять по этому холодному прогону. Проверку компаратора исправляем без
отключения анализатора: лексикографическое сравнение через string_view без
создания копий перемещаемых std::string; тест максимальной группы дополнен
смешанным регистром имён эх и проверкой порядка.

## Разбор Play Protect: Pixel 6a, обновление 1.0.3 → 1.0.4 (2026-10-28)

Владелец подтвердил модель Pixel 6a и сценарий обновления из самого клиента
1.0.3 → 1.0.4. На предоставленном снимке Google Play Защита сообщает
«Вредоносное приложение заблокировано». Версия Android, канал, категория по
«Подробнее» и SHA-256 фактически устанавливаемого файла не получены; однозначно
сопоставить байты со скриншотом с официальным asset пока невозможно. Это ограничение,
а не доказательство подмены или ложного срабатывания. Подключённых устройств adb
на начало проверки нет; локальные AOSP API 24/25 не заменяют Pixel с активной защитой.

Официальный v1.0.4 имеет SHA-256
`3b5a867af40d60dad8d98dc63fbb21ccd8f0245563d04a6a2663bdeac3e6c39c`,
версию 1.0.4/build 1019 и commit `4da3372d57ae9da50490d6187a4733a4a8596827`.
Проверен apksigner (v2), постоянный RSA-4096 сертификат
`61f1f10c15f8d3724dfe19938f9923ed2878dd9c81113c90489aded29af3fbd0`,
minSdk 24/targetSdk 36, отсутствие debuggable/testOnly, ZIP-структура и packaged
identity. INTERNET и REQUEST_INSTALL_PACKAGES сопровождаются собственным
signature-разрешением AndroidX; SMS, accessibility и device admin отсутствуют.
Явного подтверждённого вредоносного дефекта данным аудитом не найдено. Это
ограниченный структурный анализ, не доказательство отсутствия вредоносного кода
и не замена проверки Play Protect.

### Аудит конечного APK и gate выпуска

`scripts/release/android_audit.py` использует установленные stable Android
build-tools (`apksigner`, `aapt`) и стандартную библиотеку Python. Команда требует
настоящий APK, JSON release identity и ожидаемый SHA-256 постоянного сертификата:

```sh
python3 scripts/release/android_audit.py \
  --apk /path/to/ffido-v1.0.4-client-android-universal.apk \
  --identity /path/to/identity.json \
  --certificate 61f1f10c15f8d3724dfe19938f9923ed2878dd9c81113c90489aded29af3fbd0
```

Нужны ANDROID_HOME и подходящий JAVA_HOME. При отсутствии инструментов проверка
завершается ошибкой; synthetic unit fixtures не считаются реальной проверкой APK.
Отчёт `<apk>.audit.json` содержит SHA-256/размер/имя конечного файла, identity,
сертификат, SDK, итоговые разрешения и компоненты, отладочные флаги и проверку
известных QA-маркеров в AOT/DEX и именах файлов. Поиск известных маркеров не
доказывает отсутствие произвольного постороннего кода. Baseline утверждён по
официальному APK v1.0.4; изменение разрешений/компонентов/SDK требует явного
пересмотра baseline с аудитом. Штатный exported ProfileInstallReceiver защищён
android.permission.DUMP и не считается открытым незащищённым receiver.

Публичный `package.py --public` проводит аудит конечного копируемого APK и
создаёт sidecar. `publish.py` требует sidecar, проверяет его identity, сертификат,
baseline и соответствие SHA-256/размера пакету до публикации. Release job передаёт
ANDROID_CERT_SHA256 и включает audit JSON в публичные файлы и SHA256SUMS.
Схема подписанного манифеста обновлений и клиент-серверный API не изменяются.
Отчёт всегда имеет `play_protect: not_checked` — CI не имитирует недоступный
публичный API антивирусной проверки.

### Раздельная приёмка установщика и Play Protect

Исторические записи выше о выборе Install without scanning подтверждают только
работу PackageInstaller и сохранение настроек/сессии. Они **не подтверждают**
успешное сканирование Play Protect. Поле `play_protect.status: not_checked` в
новых `scripts/update/test_android_flow.py` result.json отделяет fixture QA от
проверки защиты; APK B связан с ним SHA-256. Изолированные QA APK не отправляются
Google и не выдаются за публичные сборки. При предупреждении или блокировке
нужно записать результат, не отключать защиту и не засчитывать её как пройденную.

Отдельный ручной протокол для сертифицированного Pixel с включённой защитой:
чистая установка B, ручная установка A→B, встроенная установка A→B. Для каждого
записать дату, SHA-256 A/B, модель/Android, доступные версии Google Play services /
Play Store, канал, источник и исход (разрешено/предупреждение/блокировка/не проверено),
точный текст предупреждения и доступный код PackageInstaller. Не удалять рабочую
установку ради чистого сценария: использовать отдельное тестовое устройство или
профиль с синтетическими данными. ADB install и отсутствие GMS не заменяют этот
протокол. Результат сейчас: все три проверки Play Protect **не выполнены**.

Для запроса пересмотра подготовлен `docs/play-protect-appeal.md`; обращение не
отправлено. Нет оснований менять package ID/ключ, удалять встроенное обновление
или обещать, что снятие REQUEST_INSTALL_PACKAGES устранит классификацию.

### Сравнение официальных 1.0.3 и 1.0.4

Оба APK скачаны из GitHub Releases и проходят новый аудит с постоянным сертификатом.
Это сравнение официальных кандидатов A/B; совпадение с файлом на Pixel пока не доказано.

| Поле | v1.0.3 | v1.0.4 |
|---|---|---|
| versionCode | 1016 | 1019 |
| Размер | 55 587 525 | 55 620 341 |
| SHA-256 | `693f3de7d971990ad3dd20658f7257896e390fc97ba9a6756f0e7a3c0bcb9e3c` | `3b5a867af40d60dad8d98dc63fbb21ccd8f0245563d04a6a2663bdeac3e6c39c` |
| Commit | `835af21fb1f5fe26c68474c369c13339de1cc880` | `4da3372d57ae9da50490d6187a4733a4a8596827` |
| SDK, permissions, components, certificate | Совпадают | Совпадают |
| debug/testOnly/известные QA-маркеры | Отсутствуют | Отсутствуют |

Для arm64-v8a SHA-256 `libflutter.so`, `libdartjni.so` и
`libdatastore_shared_counter.so` совпадают; `libapp.so` отличается, что ожидаемо
при изменении Dart-приложения. Diff тегов не показывает изменения Android updater,
manifest, dependency lock и правил package.py. Не найдено подтверждения, что
блокировка вызвана новым разрешением или сменой SDK/сертификата в 1.0.4.
Зависимость от облачной классификации или содержимого AOT остаётся гипотезой.

Реальная fixture B из нового Android QA распознаётся `contains_qa()` по маркерам
внутри AOT, в отличие от обычного официального APK. Это дополнительно проверяет,
что release gate различает известный QA entrypoint и production entrypoint.

### Реализация и доступные проверки изменения

Реализованы: аудит подписанного конечного APK и проверка sidecar в publication;
различимые исходы отмены/запрета/ошибки; сохранение результата receiver при отсутствии
Flutter engine; восстановление активной сессии, отмены и успешной замены APK после
перезапуска. Успех после замены определяется по совпадению установленного build
с предварительно проверенным targetVersion, а не по отсутствию session/callback.
Сырой EXTRA_STATUS_MESSAGE не передаётся пользователю. Неизвестный результат не
превращается в антивирусный диагноз. Сведения о target в диагностике берутся из
проверенного манифеста; SHA-256 там — ожидаемая сумма пакета из этого манифеста.

Финальные результаты 2026-10-28:

- Flutter 3.47.7 / Dart 3.13.5, `flutter pub get`: успешно, lockfile не изменён.
  Системный Flutter 3.41.6 не подходит по SDK constraint; использован уже
  установленный проектный SDK без обновления инструментов.
- `flutter analyze --no-pub`: без замечаний. Полный `flutter test --no-pub`:
  306 успешно, 2 пропуска из-за незаданных FFIDO_E2E_BACKEND/FFIDO_TEST_HPT.
  После сборки backend оба пропущенных e2e отдельно прошли с реальными fidoback/HPT,
  OpenSSL 3 в PATH и синтетическими данными (2/2). Новые тесты проверяют отмену, permission denial,
  блокировку, ошибку, неизвестный исход, pending→terminal через native callback,
  восстановление сводки без приватных полей и её показ только по действию пользователя;
  stale result не прерывает новую активную загрузку.
- Release Python unittest discover: 92 успешно. Updater unittest discover:
  64 успешно. `py_compile` затронутых Python-модулей успешен.
- Настоящие официальные APK v1.0.3 и v1.0.4 прошли новый audit CLI, включая
  declared signature permission. Проверен QA-маркер в AOT настоящей fixture B.
  Отчёты сохранены локально в `build/play-protect/audit-v1.0.3.json` и
  `build/play-protect/audit-v1.0.4.json`, APK/секреты в Git не добавлены.
- Обычный main-target Android release собран: `flutter build apk --release
  --no-pub --build-name=1.0.4 --build-number=1020`. Это локальная сборка с debug
  сертификатом, не публичный выпуск и не доказательство приёмки Play Protect.
  После fixture QA восстановлен обычный main-target выход Flutter.
- На одноразовых AOSP arm64 API 24 и API 25 новые release fixtures A 41001→B 41002
  прошли системное подтверждение, отмену, восстановление отмены после SIGKILL
  процесса, отказы чужой подписи/пакета/равного и меньшего build. После установки B
  восстановлен `success`, сохранены SharedPreferences и SecureSessionStore.
  Результаты: `build/play-protect/qa-api24-verified/result.json` и
  `build/play-protect/qa-api25-verified/result.json`. Оба используют одноразовый
  QA-сертификат; `play_protect.status` явно `not_checked`.
- Корневые CMake configure/build выполнены. Первый CTest без FFIDO_TEST_HPT
  пропустил 5 HPT-зависимых тестов. Найден существующий native HPT в
  `build/publication-deps/prefix/bin/hpt`; полный повтор с этим FFIDO_TEST_HPT
  прошёл 378/378 без пропусков. В сборке есть прежнее предупреждение nodiscard
  в `apps/backend/tests/integration/test_process.cpp:244`; этот файл не менялся.
- `openspec validate investigate-android-play-protect --strict` и проверка diff:
  успешно. Секреты, рабочие FTN-данные, APK и сборочные кеши не добавлены в Git.

Первые попытки нового process-restart QA не засчитаны: `am kill` сохранял процесс
с ожидающим установщиком, затем условие проверки PID в adb shell было неверно
закавычено. Исправлен runner, состояние установщика очищено на одноразовом эмуляторе,
полные финальные прогоны повторены успешно. Это сбои нового тестового сценария,
а не результаты Play Protect.

Дополнительный тест остановки процесса включается явно `--process-restart` и
требует rootable **одноразовый эмулятор**. Он использует SIGKILL без force-stop,
чтобы сохранить доставку callback приватному receiver. Обычный fixture QA не
требует root. Пример после подготовки fixtures:

```sh
python3 scripts/update/test_android_flow.py \
  --sdk "$ANDROID_HOME" --serial emulator-5580 \
  --fixtures build/play-protect/fixtures-final --process-restart \
  --directory build/play-protect/qa-new-run
```

Ограничения: локального образа API 35 нет, CI-матрица API 24/25/35 на текущем
неопубликованном diff не запускалась. Нет подключённого сертифицированного Pixel,
не получены Android/канал/категория «Подробнее» и SHA-256 файла на устройстве.
Финальная production-подпись и Play Protect для нового APK не проверялись,
новый публичный выпуск не создавался. Поэтому задачи 1.3, 5.1 (частично) и 5.2
остаются открыты; результат Google не объявляется исправленным. Коммит,
публикация, апелляция и архивирование не выполнялись.

## Tagline/Origin и APK для Pixel 6a — 28.10.2026

Продолжение `investigate-android-play-protect`; результаты ниже дополняют прежний
аудит 1.0.3→1.0.4 и заменяют прежнее ограничение о недоступности release-ключа.
Tagline — именно строка после `---`. Автоматические значения: `FFIDO 1.0.5`
и `https://github.com/hashev/ffido`. Overrides сохраняются локально в существующем
хранилище текущего профиля; сохранение не требует входа или переподключения.
Пустой ввод/reset удаляют override, автоматическая версия следует обновлениям.
Несохранённые поля учитываются защитой выхода для обновления.

Новый сервер объявляет `supports_message_footer` в Login/RestoreSession;
необязательный `MessageFooter` добавлен без изменения прежних номеров полей.
Старый клиент сохраняет прежний footer и отпечатки операций. Новый клиент со
старым сервером и defaults использует прежний запрос с предупреждением;
явные overrides отклоняются до RPC, редактор остаётся открыт. Новый сервер
не добавляет эховый footer в netmail/local. Адрес берётся из подтверждённого
серверного профиля. Для пользовательского оформления нужен также обновлённый
бэкенд: установка только APK не обновляет сервер.

Проверки реализации:

- `flutter pub get`, `flutter analyze --no-pub`: успешно (Flutter 3.47.7).
- `flutter test --no-pub`: 315 успешно, 2 optional E2E пропущены штатно.
- Оба optional E2E отдельно с `FFIDO_E2E_BACKEND` и `FFIDO_TEST_HPT`: 2 успешно;
  сохранённые Flutter-настройки переданы настоящим gRPC-запросом, прочитанный
  JAM содержит custom Tagline/Origin и серверный адрес; netmail без echo footer.
- Корневые CMake configure/build и CTest с настоящим HPT: 380 успешно.
  Проверены управляющие символы, UTF-8/CP866, 256 байт, Н→H, конфликт raw footer,
  сохранение снимка при частичном crosspost и перезапуске, UUE recovery на
  стадиях append/commit без дублирования, прежние операции без нового поля.
- Unit/widget-проверки: defaults/upgrade/override/reset, профильные preferences,
  валидация и защита несохранённых полей; снимок обычной отправки/crosspost/UUE,
  старый сервер и отказ до RPC. Действующие проверки редактора охватывают
  обычную отправку, ответ, пересылку и сохранение черновика при ошибке.
- Python release: 92 успешно; update: 64 успешно, в существующем
  `build/update-venv` с зависимостями `scripts/update/requirements.txt`.
- Генерация protobuf `tools/proto/generate.sh --check`, Dart и C++ format checks:
  успешно. Использованы штатные версии зависимостей, обновлений toolchain нет.

Обычный universal main-target APK: `build/pixel6a/ffido-1.0.5-1020.apk`.
VersionCode 1020 выше опубликованного 1.0.4/1019 и известной установленной
версии владельца; QA-коды 41001/41002 не используются для этого APK.
Встроенная identity 1.0.5/1020 согласована с pubspec и общей release identity;
локальный dev tag не является опубликованным релизом. SHA в identity — базовый
HEAD; сборка содержит незакоммиченный diff. Фактические исходники фиксируются
в `build/pixel6a/source-tree.json` и `source.patch`, а не приписываются чистому HEAD.
Постоянный сертификат SHA-256:
`61f1f10c15f8d3724dfe19938f9923ed2878dd9c81113c90489aded29af3fbd0`.
Ключ/пароли прочитаны из внешней локальной директории и не копировались в Git.
`apksigner verify` и `scripts/release/android_audit.py` успешно проверили конечный
APK: прежний application ID/сертификат, versionCode, release manifest, три ABI,
identity, отсутствие QA entrypoint; audit JSON связан с файлом его SHA-256.

Play Protect для конечного APK пока `not_checked`: сертифицированный Pixel 6a
не подключён, категория предупреждения и хеш исходного файла неизвестны.
Успешные тесты установщика не доказывают изменение внешнего verdict Google.
Коммит, публикация, отправка апелляции и архивирование не выполнялись.

### Повторная Android-матрица после добавления footer

Свежие release fixtures собраны из текущего diff штатным
`scripts/update/test_android_flow.py --prepare-only` и использованы с
`--fixtures build/footer-api35-fixtures --process-restart`.
Результаты: `build/footer-api24-run/result.json`, `build/footer-api25-run/result.json`,
`build/footer-api35-run/result.json`. На всех трёх API успешно выполнены
системный PackageInstaller A/41001→B/41002, отмена, восстановление отмены
после kill процесса, отказы чужому ключу/пакету/равному/меньшему build,
восстановление успеха после замены пакета; обычные preferences, Tagline/Origin
и защищённая сессия сохранились. На API 35 также проверен отказ разрешения
установки из данного источника. Результат Play Protect у всех `not_checked`.

API 35: Android 15, Google APIs arm64-v8a revision 9 (extension 13), AVD
`ffido_footer_api35`, серийный номер `emulator-5584`, без окна, software GPU.
Образ получен из официального `sys-img2-3.xml` Google:
`https://dl.google.com/android/repository/sys-img/google_apis/arm64-v8a-35_r09.zip`,
SHA-1 архива `16f5bceca236b2737008977c4aaf826e46a8de7d` проверен перед установкой.
Первый медленный запрос sdkmanager остановлен; архив скачан частями,
собран и проверен целиком. Это локальная arm64-проверка настоящего API 35,
не запуск удалённой CI x86_64-матрицы и не замена её API 36.

Дополнительно на том же API 35 проверено `adb install` официального
v1.0.4/1019 и `adb install -r` конечного постоянного release APK 1.0.5/1020:
оба Success, PackageManager показывает повышение versionCode до 1020.
Этот дополнительный smoke подтверждает совместимость подписи конечного APK;
встроенный self-update отдельно проверен выше QA-пакетами. Отчёт:
`build/pixel6a/api35-production-replacement.json`.

SHA-256 конечного APK:
`6a9988fd1f473e0ae4e6f260ea3b6dd3a0343a902053aac0a1fc6a0e240ed009`.
Локальный комплект `build/pixel6a/` содержит APK, `.audit.json`, `SHA256SUMS`,
identity, результаты эмуляторов, source tree и инструкцию проверки на Pixel.
`git diff --check` и `openspec validate investigate-android-play-protect --strict`
успешны. Открыты только 1.3/5.2: приёмка Google Play Protect владельцем на
сертифицированном устройстве, включая чистую/ручную/встроенную установку.

### Приёмка владельцем и закрытие изменения

28.10.2026 владелец подтвердил успешное обновление до 1.0.5/1020 на Pixel 6a, затем явно поручил считать задачи 1.3 и 5.2 выполненными и архивировать изменение. Закрытие основано на его приёмке. Отдельные протоколы чистой/ручной/встроенной установки и подробный verdict Play Protect не предоставлены; автоматизированные отчёты сохраняют фактически измеренные результаты.

### Исправления по первому CI выпуска 1.0.5

PR #18, прогон 40653661376 выявил зависимость консольного Dart gRPC smoke от
Flutter services через новые настройки footer. Чтение Flutter preferences
отделено от транспорта и снимка операции условным импортом: приложение
продолжает использовать профильные настройки, standalone Dart tools не имеют
Flutter-профиля и сохраняют прежние запросы без оформления. Локально
`dart compile kernel tool/native_acceptance.dart` и настоящий
`scripts/check_acceptance.py --native-only` с TLS backend проходят.
`flutter analyze --no-pub` без замечаний, все 315 Flutter-тестов проходят.

В API 35 CI начальный QA-маркер присутствовал, но secure session и footer
отсутствовали ещё до первой попытки обновления. Runner теперь явно очищает
данные только свежей установки A на выбранном disposable-эмуляторе. Проверки
сохранности данных между A/B и после перезапуска не ослаблены. Повтор со свежими
release fixtures на локальном API 35 прошёл целиком, включая отказ разрешения,
отмену, kill процесса, негативные проверки подписи/пакета/build и успешное A→B;
Tagline/Origin и защищённая сессия сохранились. Update Python: 64 теста успешно.

### Уточнение аудита сертификата и выпуск 1.0.6

Стабильный прогон v1.0.5 (40658812708) остановил публикацию на новом аудите.
Предшествующая проверка подписи в package.py прошла; ошибка оказалась в
распознавании вывода apksigner. Проверенный официальный Linux build-tools
37.0.0 воспроизводит её на уже принятом APK: вместо `Signer #1` выводится
`V2 Signer:` с тем же постоянным SHA-256. Архив build-tools_r37_linux.zip
сверен с официальным repository2-3.xml: SHA-1
`70954e99f4c3d9d46ee70fa32624672fe7cd6ebe`.

Аудит поддерживает нумерованный, versioned и SDK-scoped вывод. Все сертификаты
подписантов обязаны совпасть с постоянным fingerprint; чужой сертификат в
любом SDK-диапазоне, отсутствующий/непонятный вывод и debug отклоняются.
Source stamp не подменяет подпись приложения. Release Python: 93 теста успешно,
включая новые негативные случаи. Полный аудит настоящего APK с официальным
Linux apksigner 37.0.0 и локальным aapt прошёл.

Тег v1.0.5 сохранён без перемещения. Для исправленного выпуска версия повышена
до 1.0.6; новые публичные пакеты будут привязаны к новому проверенному коммиту.
