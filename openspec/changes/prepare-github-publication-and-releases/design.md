# Design

## Context

Мотивация — в proposal.md; публичные контракты подготовки и выпуска — в трёх delta specs.

Наблюдаемое состояние: корневой Git сохраняет историю старого Flutter-клиента; перенос в `apps/` ещё не закоммичен, remote отсутствует. Корневой README содержит машинные пути и историю локального переноса. `.github/` отсутствует. Android использует `com.example.fido` и debug signing даже в release. Flutter version — `1.0.0+1`. Backend использует POSIX, HPT и общий lock, рассчитан на Linux/macOS. Есть root CMake install-компонент `ffido`, `build.sh`, проверки C++/Dart/генерации proto. gRPC 1.84.0 и Protobuf 36.2.0 закреплены; Husky требует согласованных исходников и статической libfidoconfig для адаптера. Временный `apps/backend/tmp/bat-into-tokyonight` не является продуктом.

Последняя проверка backend: 350/350 Linux от UID 1000 и 350/350 macOS; это не доказывает сборку на GitHub или переносимость пакетов. Frontend Windows/Linux release ещё предстоит проверить на соответствующих runner. Существующий `platform-runtime` описывает работу приложения, но не управляемое распространение; его требования не меняются. Клиент и сервер сохраняют текущий protobuf/gRPC-контракт и выпускаются с одного SHA; новой миграции данных нет.

## Goals / Non-Goals

**Goals:** сборка из чистого checkout, публичные скачивания без аккаунта, проверяемая защита master, полный согласованный набор клиентских и серверных пакетов, воспроизводимая инструкция владельцу.

**Non-Goals:** перенос backend на Windows/Android, iOS/Web-пакеты, App Store/Google Play, автоматическое изменение рабочей ноды, переписывание истории без выбора владельца, принудительное обновление зависимостей. На этапе propose создаются только эти артефакты; README, workflows и каталог экспорта создаются при apply.

## Decisions

### 1. Публичный репозиторий и права

Public GitHub repository с `Pull requests → Collaborators only`. Для личного аккаунта — приглашения Collaborators; для организации — Write/Maintain/Admin только выбранным участникам. Остальные могут читать, скачивать и делать собственные копии, но не вносить изменения в upstream. Ограничение участия не запрещает использование кода согласно выбранной лицензии.

Активный branch ruleset для `refs/heads/master`: Require PR, ноль approvals, Require status checks, актуальность относительно базы, Require conversation resolution, Block force pushes, Restrict deletions, пустой bypass list. `Restrict updates` не включать как замену PR: без bypass это заблокирует и нормальное слияние. Владелец может слить собственный PR после CI. Владелец технически сохраняет право менять настройки репозитория; правила запрещают обход в обычном процессе, а не лишают его административных прав.

Альтернативы: private repo не даёт требуемого публичного кода; обязательный второй reviewer блокирует работу одного владельца и отвергнут пользователем. Свободные внешние PR не соответствуют выбранному доступу.

### 2. Pipeline и публикация

Планируемые `.github/workflows/ci.yml`, `release.yml` и общий reusable workflow сборки/проверок. PR: `pull_request` в master, минимум `contents: read`, никаких signing/release secrets, без исполнения кода PR через `pull_request_target`. Анализ Flutter, тесты, release build четырёх платформ, C++ build/test на Linux/macOS, format/static checks и проверка generated proto существующими инструментами. Интеграционные HPT/SMAPI fixtures обязательны; CI проверяет отсутствие неожиданных skipped tests. Полный набор тестов читается из текущей регистрации, число 350 не фиксируется навсегда.

Один стабильный итоговый check `ci-required` с `if: always()` проверяет все обязательные jobs, включая cancelled/skipped/failure; без path filters, оставляющих check pending. Именно он указывается в ruleset, источник — GitHub Actions. Тестовые конфиги только синтетические; контейнеры локальны runner, UID для проверки прав непривилегированный.

После merge защищённой master событие `push` запускает release workflow на фактическом SHA, повторно вызывает проверки и матрицу сборки. Закрытый без merge PR не создаёт push. Начальный seed и ручной retry явно отличимы от обычного merge. У каждого запуска своя идентичность; concurrency не отменяет выпуски разных merged SHA. Publication job сериализуется и не подбирает «последние» артефакты другого запуска. Долгие сборки не используют amster2 или пользовательский компьютер как runner.

Для стабильного релиза — `push` тега, строгая проверка `^v[0-9]+\.[0-9]+\.[0-9]+$`, доступность SHA в истории origin/master, соответствие версии исходников и успешные повторные проверки. Создание стабильных тегов ограничить владельцем/уполномоченным release actor через отдельный tag ruleset; запрещены переписывание/удаление выпущенных тегов. Не создавать тег через GITHUB_TOKEN в надежде, что он вызовет другой workflow: итоговый job сам публикует нужный релиз.

Job публикации получает `contents: write`; signing jobs получают только нужные environment secrets на доверенном ref. По умолчанию `FFIDO_PUBLICATION_READY` выключен: до выбора лицензии, application IDs и ключа публичная публикация явно блокируется, PR CI работает. Автоматические выпуски после первоначальной настройки не требуют ручного approval environment. Версии Actions закрепляются полными SHA, права токена минимальны, секреты не вводятся в shell через непроверенные выражения.

Артефакты CI служат для передачи между jobs. Финальные файлы размещаются в Releases, поскольку это канал публичного скачивания, а не временные workflow artifacts. Публикация: собрать весь ожидаемый manifest, проверить hashes/подписи, загрузить в draft, проверить состав и только затем открыть prerelease/release. Сбой оставляет непубличный draft; rerun того же run/SHA продолжает draft, но не заменяет опубликованные файлы. Включение immutable releases оценить при реализации; идентичность опубликованных файлов обязательна независимо от этой функции.

### 3. Матрица и проверка пакетов

Предлагаемая начальная матрица, без обещания непроверенных архитектур:

| Компонент | ОС / архитектура | Формат |
| --- | --- | --- |
| Клиент | macOS arm64 и x86_64, отдельные сборки | DMG с `.app` |
| Клиент | Windows x86_64 | ZIP с exe и всеми Flutter DLL/assets |
| Клиент | Linux x86_64 | tar.gz с Flutter bundle и desktop launcher |
| Клиент | Android arm64-v8a, armeabi-v7a, x86_64 | один универсальный release APK |
| Сервер | macOS arm64 и x86_64 | tar.gz |
| Сервер | Linux x86_64 | tar.gz |

Архитектуры — первоначальное предложение, а не расширение всех платформ на ARM. Не добавлять MSI/DEB/RPM/AppImage/AAB без необходимости; portable-пакеты уменьшают объём первой публикации. Min OS/Android API фиксируются по фактическим Flutter/SDK и linked libraries при реализации и заносятся в manifest/README до выпуска. Выбрать явные доступные GitHub runner labels для каждой архитектуры, зафиксировать Flutter/Java/NDK и зависимости без попутного upgrade.

Backend устанавливается через CMake `--component ffido` в staging: fidoback, ffido-admin, ffido-hpt-auth, wrapper, example config и legal files. HPT тоссер пользователя не включается автоматически; тестовый HPT собирается в изолированном prefix. Husky-компоненты закрепить ревизиями из docs/testing.md, включая fidoconf `62c963a6f078905660f2c0b3a6929383823190c5`; source hash адаптера сохраняется. Никаких ссылок на `/Users/yurik`, `/work` или библиотек, доступных только на машине сборки.

Проверять `otool -L`, `ldd/readelf`, PE dependencies; runtime DLL/dylib/so включать в пакет в рамках лицензий или явно задавать системные prerequisites. Linux baseline выбрать не новее заявляемой минимальной системы; Flutter secure storage требует документированных системных библиотек/службы keyring. Для macOS обеспечить корректные rpath и signing после изменения linked paths. Smoke: распаковать в новый каталог, проверить запуск клиента, запуск сервера на синтетической конфигурации, TLS Login/read/post с согласованным клиентом/контрактом. Проверки не трогают рабочие JAM.

### 4. Версии, подписи и лицензия

Версия продукта берётся из `apps/frontend/pubspec.yaml`, передаётся backend build metadata и в manifest; новый stable base меняется через PR. Prerelease tag: `vX.Y.Z-dev.N.<shortSHA>`, stable: `vX.Y.Z`. В рамках одного постоянного release workflow `N=github.run_number`; Android build number — N плюс зафиксированный offset, превышающий ранее распространявшиеся номера. PR APK не публикуются и могут использовать debug key только для проверки сборки. Retry сохраняет N и release identity; перед выпуском проверяется отсутствие конфликтов версии. При замене workflow нельзя обнулить Android-счётчик: offset увеличивается через PR. Stable APK собирается тем же release workflow с новым N.

Android получает постоянный keystore и application ID, которые владелец утверждает перед первой публикацией; ключ хранится в защищённой резервной копии вне GitHub. Планируемые secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD`. Не создавать новый ключ для каждого CI run. Смена существующего application ID создаёт другое приложение, поэтому до выбора проверить локально установленные профили; не выполнять молчаливую миграцию Keychain/сессий.

До получения Apple Developer ID/Windows сертификатов разрешены явно обозначенные неподписанные desktop prerelease с инструкцией штатного подтверждения установки. macOS ad-hoc подпись отличать от Developer ID и notarization. Не предлагать глобально отключать Gatekeeper/SmartScreen. Для заявленного signed режима отсутствие сертификата — ошибка, а не fallback. Stable может быть неподписанным, если это явно указано; Android release-подпись обязательна всегда.

Лицензию собственного кода владелец выбирает отдельно. `LICENSE`, `THIRD_PARTY_NOTICES` и распространяемые legal/source/relink материалы формируются после проверки лицензий закреплённых библиотек. Локальные COPYING Husky показывают Library GPL/LGPL; статическое включение libfidoconfig и замена cfg.c требуют отдельной проверки условий, нельзя ограничиться добавлением MIT в корень. Нерешённое лицензирование блокирует публичный выпуск, но не написание workflows и локальную сборку.

### 5. Подготовка каталога и история

Сценарий экспорта принимает новый output path вне исходного дерева и отказывается перезаписывать существующий непустой каталог. Используется явный список путей продукта с проверкой каждого файла, а не простое `git archive HEAD` (оно потеряет незакоммиченный монорепозиторий) или копирование всего рабочего каталога. Включаются `apps/`, `contracts/`, необходимые `tools/`, `scripts/`, cmake/build files, public docs и openspec; в `apps/` исключаются runtime/temp/cache. `.agents`, `.opencode`, `.qwen` не копируются как инструменты владельца; проектный AGENTS может войти после проверки. Исторические OpenSpec-архивы сохраняются без переписывания; отчёт отдельно отмечает исторические локальные пути как текст, а не требуемую зависимость сборки.

Выход: manifest файлов/хешей, отчёт секретов и абсолютных путей, источники без `.git` до выбора режима истории. Сканировать актуальное дерево и будущий диапазон истории; результаты не печатают обнаруженные секреты. Исключения для синтетических fixture passwords документируются точечно. Проверять symlinks, вложенные .git, крупные бинарные файлы, конфиги, JAM, SQLite, ключи и чужие checkout, включая `apps/backend/tmp/`. Пользовательские файлы в оригинале не удаляются. Чистая сборка из экспорта обязательна.

Новая история: после решения владельца git init в экспорте. Сохранение истории: отдельный clone старого Git плюс применение отобранного текущего дерева, аудит всех достижимых refs перед push; исходный checkout не переписывается. Не публиковать старые ветки/теги автоматически. Если найдены секреты, сначала ротация и решение о переписывании/новом старте. Commit/push по отдельному запросу; apply готовит каталог и инструкции без этих действий.

### 6. План полного README

Корневой README на русском: назначение, возможности/ограничения, архитектура клиент—gRPC—backend—JAM/HPT; таблица пакетов и download links; отдельные маршруты «только клиент» и «сервер»; OS/runtime requirements; подписи и SHA-256; установка/обновление/удаление с сохранением пользовательских данных; TLS/endpoint/FTN login; Docker path mappings и CP866/KOI8-R; shared coordination lock и поддерживаемый HPT wrapper; point mail provisioning/cycle; backups/recovery; troubleshooting; сборка/проверки из корня; лицензия и contribution policy. Нельзя обещать внешнюю доставку после SAVED_LOCALLY. Подробности остаются в component README/docs без дублирования противоречащих команд.

## Risks / Trade-offs

- [Нет решения владельца по лицензии/ключам/истории] → параметризованная локальная подготовка и явные gates первой публикации, без выдуманной лицензии и секретов.
- [Windows/Linux Flutter plugins не проверены release] → обязательная матрица и исправление конкретных проблем совместимости в apply без обновления toolchain ради обхода.
- [Husky/libs отсутствуют на runner] → pinned bootstrap в отдельный prefix, кеш по OS/arch/compiler/revisions, никакого использования рабочей ноды.
- [Библиотеки доступны только при сборке] → проверка зависимостей и smoke из распакованного пакета на чистом runner.
- [Ноль approvals упрощает слияние вредного кода участником Write] → права только доверенным, обязательный CI; второе человеческое ревью не гарантируется выбранной политикой.
- [macOS Intel runners/длительные native builds] → явные labels и замер полной матрицы, без удаления архитектуры из выпуска для получения зелёного CI.
- [Public fork возможен] → это ожидаемое свойство публичного кода; запрет upstream contributions не является запретом копирования.

## Migration Plan

### Подробная последовательность для владельца GitHub

1. При apply подготовить каталог и локальный отчёт. Выбрать `<OWNER>/<REPO>` (имя ffido рекомендуется), личный аккаунт либо организацию; лицензию; новую либо сохранённую историю. Утвердить Android и Apple bundle IDs до первой массовой установки. Скопировать постоянный Android-ключ в резервное хранилище.
2. Выполнить документированные проверки из чистого экспорта. Не использовать `git add .` в исходном смешанном рабочем дереве. Проверить лицензию, manifest и будущую Git-историю. До решения о лицензии не загружать публичный код.
3. На GitHub `New repository`: выбранные owner/name, Public, без автогенерации README/LICENSE/.gitignore, если они подготовлены локально. Для CLI будущая команда: `gh repo create OWNER/REPO --public`; токен и пароли в команды не вставлять. Создание/первый push выполняет владелец после отдельной авторизации.
4. Начальную ветку master создать одним проверенным seed commit без секретов. Вариант bootstrap: seed содержит только утверждённые юридические файлы и короткий README, весь продукт/CI — отдельной веткой `codex/prepare-publication`. Зафиксировать bootstrap-исключение: PR нельзя направить в несуществующую ветку. При сохранении истории подготовить эквивалентную границу в отдельном clone, не переписывая оригинал.
5. В `Settings → General` назначить default branch `master`; в Features включить Pull requests и выбрать `Collaborators only`. В `Settings → Collaborators`/`Manage access` пригласить выбранных участников; для организации не давать всем членам Write по умолчанию. Включить squash merge (рекомендуемый единый режим), отключить ненужные merge методы.
6. В `Settings → Rules → Rulesets` создать active branch ruleset master: Require PR, approvals=0, no code-owner/latest-push approval, Block force pushes, Restrict deletions, Require conversation resolution, bypass list пустой. Не включать Restrict updates. На этом шаге ещё нет зарегистрированного check.
7. В `Settings → Actions → General` разрешить только используемые доверенные actions/reusable workflows. Default workflow permissions — read; автоматическое создание/одобрение PR не требуется. Создать первый PR продукта/CI при выключенном `FFIDO_PUBLICATION_READY`. Подождать первого запуска `ci-required`, затем до первого merge добавить его в ruleset как required с источником GitHub Actions и требованием актуальной базы. Проверить отсутствие пропущенных matrix jobs. Если check не появился, исправить workflow в PR, а не включать фиктивный check.
8. После merge CI/документации проверить настройки через GitHub API/UI и тестовую ветку: приглашённый может создать PR, посторонний — нет; прямой push master/force/delete отклоняются; намеренно падающий check блокирует merge; владелец с успешным PR сливает без второго approval. Деструктивные проверки удаления/force выполнять в одноразовом репозитории с тем же ruleset, а не на рабочей master. Проверить anonymous clone и downloads без cookie.
9. В `Settings → Environments` создать release environment, разрешённые deployment branches — master и контролируемые stable tags; без обязательных reviewer, чтобы не нарушать автоматические выпуски. Добавить Android secrets; опционально Apple/Windows secrets по будущей инструкции; проверить ограничения tags и версий. Права write задать только publish job. Если нужны Apple ID/notary credentials, заносить их через secrets UI, не в config.json.
10. Когда license/IDs/keys/история утверждены и проверки готовы, включить `FFIDO_PUBLICATION_READY`. Следующий merged PR автоматически выпускает prerelease. Для первого gated merge предусмотреть `workflow_dispatch` retry только того же доверенного SHA master; это не способ публикации произвольной ветки.
11. Открыть публичный prerelease без авторизации; скачать все пакеты, проверить SHA-256 и установку на заявленных ОС. Проверить, что он помечен prerelease и не подменяет latest stable.
12. Для stable изменить base version через обычный PR, дождаться зелёного CI, выбрать проверенный SHA master, создать подписанный или annotated tag `vX.Y.Z`, затем `git push origin vX.Y.Z` из подготовленного clone. Tag ruleset разрешает создание владельцу, но запрещает обновление/удаление выпущенной версии. Проверить stable release и согласованность manifest.
13. При сбое найти ошибку matrix job, исправить обычным PR или повторить тот же run, если проблема инфраструктурная. Не перезаписывать публичные пакеты; ошибочную публичную версию обозначить в release notes и выпустить новую. Rollback — получить предыдущий пакет с backup данных по README; новые SQLite/JAM не откатывать вслепую. Рабочая нода не участвует в проверках и не обновляется автоматически.

Эта последовательность переносится в `docs/github-publication.md` при реализации, с фактическими именами secrets/jobs/runner и проверенными командами. До удалённого запуска нельзя утверждать, что branch protection и GitHub CI уже проверены.

### Источники для настройки, проверенные при планировании

- [GitHub: Collaborators only](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/disabling-pull-requests)
- [GitHub: branch/tag rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [GitHub: события workflow](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub: скачивание workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)
- [GitHub: безопасное использование Actions](https://docs.github.com/en/actions/reference/security/secure-use)

## Open Questions

Отложенные решения владельца, не меняющие выбранную схему: GitHub owner/name и тип аккаунта; выбранная лицензия и copyright holder; сохранить историю либо начать новую; окончательные application IDs; наличие Apple/Windows сертификатов и согласие на явно неподписанные desktop-пакеты. Предпочтения формата/архитектур в таблице — предложения для review до apply. До разрешения условий не выполняется публичная загрузка, смена ID или создание ключей; подготовка сценариев, примеров и документации возможна без этих значений.

## Принятые решения при apply

Владелец утвердил `hashev/ffido`, MIT, новую публичную историю без переноса старой,
`io.github.hashev.ffido` и неподписанные desktop-пакеты. Эти решения заменяют
соответствующие отложенные вопросы выше. Создан только пустой remote; commit/push
и выпуск пакетов пока не разрешались. Android release-key ещё не предоставлен.

Разные merged SHA используют отдельные concurrency groups: глобальная группа GitHub
могла бы отменять ожидающий prerelease. Повторы одного run сериализуются,
а пакеты каждого run собираются по собственному manifest и уникальному тегу.
