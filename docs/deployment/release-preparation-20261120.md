# Подготовка накопленных изменений к коммитам, 20.11.2026

## Область ревизии

Исходная ветка — `master`, HEAD `3926989`. До начала ревизии index пуст;
изменены либо добавлены 175 файлов. Активных OpenSpec changes нет. Завершённые
telegram-mini-app, safe-mailbox-restore и safe-signed-node-transition архивированы,
но их код, спецификации и отчёты ещё не зафиксированы в Git.

Ревизия не создаёт коммиты, не меняет рабочие службы amster2, firewall или guards,
не публикует ветки, Web-сборки и релизы. Исходники при этой проверке не исправлялись.
Новый файл этого отчёта учитывается дополнительно к исходным 175 файлам.

## Состав и приватные данные

Из исходного набора 175 файлов 76 уже отслеживаются Git, 99 — новые. Бинарных
файлов в наборе нет. Включены handwritten/generated исходники, тесты, конфигурация
Pages, публичный каталог backend, спецификации и эксплуатационные отчёты.

Проверены сигнатуры private keys, bot/GitHub tokens, Bearer-значения и присваивания
паролей/секретов. Все 14 найденных кандидатов разобраны: тестовые `fixture`,
`saved-secret`, отрицательные release/session fixtures либо имена файлов ключей.
Рабочих credentials среди них не обнаружено. Deployment JSON и публичный env с
digest образа проверены отдельно: bot_id, адреса и image IDs не являются токенами.
Это эвристический поиск с ручной проверкой кандидатов, не доказательство отсутствия
любых возможных секретов во всех форматах.

`git check-ignore` подтверждает исключение рабочего backend config, session key,
build/review материалов и Web build. Полные базы, изображения Docker, backup,
приватные QA-журналы и ключи из build не входят в набор для коммитов.

## План последовательных коммитов

Подготовлен список путей и владельцев групп:
`build/release-preparation-20261120/commit-groups.json`. Он содержит ровно исходные
175 путей, без credentials. Это план staging, а не уже созданные коммиты.

| № | Предлагаемое название | Полные файлы | Содержание |
| --- | --- | ---: | --- |
| 1 | `feat(web): add Telegram Mini App and schema 12 authentication` | 94 | Контракт и generated код, Telegram backend, Web workspace/profiles/drafts, UUE save/draft fixes и регрессии, каталог, Pages workflow, schema 12 release metadata и соответствующие спецификации |
| 2 | `feat(storage): add verified backup and mailbox restore` | 23 | Snapshot/deployment helpers, административное восстановление, inherited maintenance lease, logical generations, повтор UUE/crosspost после переноса JAM, тесты и архив safe-mailbox-restore |
| 3 | `feat(update): add safe signed backend and tosser transition` | 25 | Доверенная регистрация локальной пары, signed floor, подготовка обоих образов, журнал фаз, gating, rollback/reconciliation, QA runner и архив safe-signed-node-transition |
| 4 | `docs(ops): record Mini App deployment and acceptance` | 28 | Исторические отчёты, публичные шаблоны и проверенные материалы обслуживания amster2; дополнительно этот отчёт |

Оставшиеся пять общих файлов нужно разделить по содержимому:

- `apps/backend/CMakeLists.txt`: Telegram source/test/fixture — №1; restore source,
  backup/restore tests, fault library и install snapshot helper — №2.
- `apps/backend/src/main.cpp`: ConfigureTelegram — №1; include и привязка
  восстановленных generations — №2.
- `apps/backend/README.md`: разделы Telegram — №1, restore — №2, переход пары — №3.
- `docs/testing.md`: распределить результаты по соответствующим трём изменениям.
- `openspec/specs/node-backup/spec.md`: исходные четыре требования — №2,
  четыре требования delta safe-signed-node-transition — №3.

Shared-файлы нельзя добавлять целиком в первый коммит. Admin/restore helpers в №2
уже включают общий maintenance lease, необходимый следующему координатору; generic
deployment backup также относится к этой группе. Release metadata 9–12 входит
в №1 вместе с фактической миграцией schema 12, а не откладывается до №3.

Рекомендуется одна рабочая ветка `codex/…` и один PR с согласованным конечным
состоянием. Независимая сборка каждого промежуточного коммита ещё не проверена:
при фактическом staging нужно проверять каждый шаг из чистого дерева. Не создавать
четыре независимых PR без проверки зависимостей. Workflow release реагирует на
push в master, а публикация дополнительно зависит от publication-ready и environment
guards; merge и выпуск требуют отдельного разрешения.

## Среда и проверки

Проверки этой ревизии сохраняются в `build/release-preparation-20261120/*.log`
и `*.exit`. Используется закреплённый Flutter 3.47.7 / Dart 3.13.5, protoc 36.2,
подготовленный backend build и закреплённый HPT из publication-deps.

Dart MCP доступен, но его `run_tests --version` показывает Flutter 3.41.6 /
Dart 3.11.4. Поэтому его ошибки private named parameters относятся к несовпадению
SDK; основные analyze/tests выполняются явно закреплённым CLI. MCP-конфигурация
и настройки анализатора не менялись, автоматические fix/format не применялись.

Исторические результаты 19.11 не засчитываются как текущие. Проверки 20.11:

| Проверка | Текущий результат |
| --- | --- |
| `cmake --build build/backend --parallel 4` | Успешно; C++-исходники не новее проверенных binaries |
| `FFIDO_TEST_HPT=$PWD/build/publication-deps/prefix/bin/hpt CTEST_PARALLEL_LEVEL=4 python3 scripts/release/check_ctest.py build/backend` | 564/564, без skips; 400,25 с |
| `python3 scripts/check_cpp.py --build-dir build/backend` | Format/clang-tidy: 129 файлов / 65 translation units |
| Flutter `pub get --enforce-lockfile`, `analyze --no-pub` | Успешно, analyzer без issues; lock-файлы не изменились |
| Flutter `test --no-pub` | 763 passed, 2 skipped из-за отсутствующих E2E env; 10 мин 21 с |
| Те же два E2E отдельно с `FFIDO_E2E_BACKEND` и `FFIDO_TEST_HPT` | 2/2 passed; реальные локальные backend/HPT и изолированные данные |
| Flutter `test --no-pub --platform chrome` для четырёх browser test files | 12/12 passed |
| Flutter `build web --release --no-pub --base-href /ffido/` | Успешно, локальная сборка; без публикации |
| `python3 scripts/check_dart.py --check` с закреплённым Dart в PATH | 217 файлов, 0 изменений |
| `dart pub get --enforce-lockfile` в tools/proto и `tools/proto/generate.sh --check` с protoc 36.2 | Успешно; generated код воспроизводится |
| Python 3.12 suites `scripts/update`, `scripts/release` | 107 и 107 тестов |
| Python suites `tools/gateway`, `docs/deployment/amster2-miniapp` | 2 и 9 тестов; сетевые/host операции renewal подменены fixtures |
| `openspec validate --specs` | 31 passed, 0 failed; прежние предупреждения о длине требований api-transport/user-identity |
| `git diff --check` | Успешно |

Flutter-команды выполнялись из apps/frontend абсолютным SDK-путём
`/Users/yurik/development/flutter-3.47.7/bin/flutter`. Python suites — через
существующий `build/telegram-python/bin/python` (3.12). E2E запуск:

```sh
FFIDO_E2E_BACKEND=/Users/yurik/Projects/ffido/build/backend/apps/backend/fidoback \
FFIDO_TEST_HPT=/Users/yurik/Projects/ffido/build/publication-deps/prefix/bin/hpt \
/Users/yurik/development/flutter-3.47.7/bin/flutter test --no-pub \
  test/api/point_mailboxes_e2e_test.dart test/api/private_areas_e2e_test.dart
```

Browser запуск использовал CHROME_EXECUTABLE и файлы
`test/api/uue_files_browser_test.dart`, `test/widgets/web_draft_browser_test.dart`,
`test/widgets/web_mailbox_network_browser_test.dart`,
`test/platform/telegram_host_browser_test.dart`. Пропуски основного Flutter runner
не объявляются прошедшими: их покрывает отдельный явный E2E запуск выше.

В выполненных локальных проверках блокирующих ошибок не обнаружено. Полный
Docker-cycle safe-signed-node-transition заново в этой ревизии не выполнялся;
его отдельный отчёт сохраняет собственную дату и ограничения. После ревизии
Git index остался пустым; из новых изменений добавлен только этот отчёт.

## Границы готовности к выпуску

Подготовка групп не означает, что подписанный релиз уже существует. Для выпуска
ещё нужны фактические staging/коммиты, CI требуемых платформ и отдельно разрешённая
публикация. Версии и теги этой ревизией не повышаются. Полная повторная UI-приёмка
в Telegram и на телефонах здесь не выполняется.

Host coordinator запускается из версионируемого checkout `scripts/`, как описано
в runbook. Его не следует считать включённым в native install: CMake устанавливает
native updater и отдельный snapshot helper, а не весь Docker host coordinator.
При рабочей установке нужно фиксировать полный набор host scripts того же commit.

Дальнейший production-допуск остаётся описан в
[runbook перехода](amster2-miniapp/signed-transition.md): настоящий подписанный
совместимый релиз, свежая регистрация конфигурации и образов, расчёт места,
полный stopped-node backup, репетиция, затем отдельно разрешённое переключение.
Автообновления сохраняют паузу.

## Продолжение: ветка для публикации

После отдельного поручения продолжить подготовку создана локальная ветка
`codex/prepare-miniapp-release`. Состояние origin/master проверено чтением:
`3926989e518efb9607df739f7f3c1288c7a0b31e`, локальная база актуальна; тега v1.0.28
на origin нет. Push, PR, merge, создание тега и публикации не выполнялись.

Сформированы последовательные коммиты:

1. `2ec59f4` — Mini App, Telegram RPC, schema 12 и согласованная release metadata.
2. `9fca3ab` — backup/restore, maintenance lease и сохранение logical generations.
3. `1507b05` — согласованный переход backend/tosser на подписанный релиз.
4. Завершающий `chore(release): prepare 1.0.28 and Pages publication` — текущие
   эксплуатационные отчёты, этот документ, подготовка версии и workflow Pages.

Первый коммит собран и проверен отдельно в detached worktree, без кода следующих
этапов: 558/558 backend/HPT tests. Второй также собран отдельно: 564/564 tests.
В обоих gates заданы закреплённые FFIDO_TEST_HPT и FFIDO_TEST_ENVOY; скрытых
пропусков нет. У третьего C++-состав совпадает со вторым; дополнительно в отдельном
worktree прошли Python updater 107, release 109 без skips и 9 нативных
CLI/backup/restore/Telegram integration tests. Полный Docker-cycle из отчёта
safe-signed-node-transition при подготовке коммитов повторно не запускался.

В новом CMake-кеше первоначально обнаружился автоматически выбранный OpenSSL 4,
несовместимый с подготовленным gRPC. Первая попытка линковки завершилась ошибкой;
успешные проверки выполнены после явного выбора того же OpenSSL 3, что используется
основной проверенной сборкой. Зависимости не обновлялись. Сборка worktree использует
publication-deps cache, Debug, прежний compiler и Python 3.12.

Дополнительные изменения подготовки:

- Исправлен штатный source-export: в GitHub workflow строка разрешения
  `id-token: write` больше не считается литеральным токеном. Исключение ограничено
  стандартными значениями разрешения в workflow; настоящие literal credentials и
  исходная проверка сигнатур ключей остаются запрещены. Ошибка воспроизведена
  регрессией до исправления; добавлены положительный и отрицательные случаи.
  Полный export прошёл, 47 machine-reference warnings рассмотрены как существующие
  документированные пути, примеры и container defaults; это не файлы ключей.
- В pubspec подготовлено `1.0.28+1066`. 1066 — локальное значение versionCode;
  фактические build_number/update_sequence релиза задаёт прежний release workflow
  через GITHUB_RUN_NUMBER + offset. Signed floor и опубликованные manifests не менялись.
- Уточнено описание авторизации и персональных прав в backend README; убрано
  устаревшее утверждение про одинаковый доступ и «все 13 RPC».
- Из нового Python test-файла удалена только лишняя пустая строка в EOF,
  обнаруженная staged diff-check; поведение тестов не менялось.
- Workflow Pages сохраняет ручной запуск и publish=false по умолчанию. Теперь
  выполняет analyzer, 28 существующих тестов workspace/draft/pending/contract,
  12 browser tests и release build. Эти команды прошли локально на версии 1.0.28;
  GitHub Actions job ещё не запускался.

## Настройки GitHub перед фактической публикацией

Состояние проверено через read-only API 20.11.2026:

| Объект | Фактическое состояние | Необходимое действие |
| --- | --- | --- |
| Pages URL | https://hashev.github.io/ffido/, HTTPS включён | URL сохраняется, BotFather перенастраивать не требуется |
| Pages source | legacy, ветка codex/telegram-mini-app-pages, `/` | После проверки сборки и разрешения публикации переключить на GitHub Actions |
| github-pages environment | Разрешены ветки codex/telegram-mini-app-pages и gh-pages | Добавить master и релизные теги v*, сохранив прежние правила для отката |
| FFIDO_PUBLICATION_READY | true | Учитывать, что merge в master запускает Release и при успехе публикует dev-выпуск |
| release environment | Разрешены master и теги v* | Менять не требуется |
| Секреты release environment | Имена всех семи требуемых secrets присутствуют | Значения не читались; фактическую подпись и публикацию проверяет CI |

Ни одна из этих настроек не изменялась. Подготовленные JSON для review находятся
в `build/publication-preparation-20261120/`: pages-enable-actions.json,
pages-master-policy.json, pages-release-tags-policy.json и pages-rollback.json.
Rollback возвращает прежнюю legacy source-ветку; старые environment policies
не удаляются. Созданные при переходе новые policy IDs нужно сохранить и при
необходимости отката удалить только эти добавленные правила.

После отдельного разрешения последовательность следующая:

1. Push рабочей ветки и один PR; дождаться обязательного ci-required и всех
   платформенных проверок. Draft PR-текст подготовлен локально в build.
2. Merge разрешать с учётом автоматической dev-публикации: publication-ready уже true.
   Стабильный v1.0.28 потребует отдельного разрешения создать и отправить тег
   после успешных проверок; подготовка исходников тег не создаёт.
3. Запустить Pages workflow с publish=false на выбранном ref и проверить артефакт.
4. Отдельно применить Pages source/environment changes и выполнить publish=true.
   Для одинакового исходного состояния проверочной и рабочей сборки использовать
   один immutable release tag; перед deployment сверить head SHA запуска.
5. Проверить опубликованный клиент, HTTPS/gRPC-Web/CORS, HPT/Telegram-вход и профили.
   Отправка в FidoNet и возобновление автообновлений этим планом не разрешаются.

Рабочий backend amster2 не обновляется ни одним из перечисленных шагов. Его
переход на выпущенную подписанную пару остаётся отдельной процедурой с новым backup.
