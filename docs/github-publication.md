# Публикация FFIDO на GitHub

## Утверждённые решения и текущий статус

| Параметр | Значение |
| --- | --- |
| Репозиторий | https://github.com/hashev/ffido, личный аккаунт, public |
| Лицензия своего кода | MIT; лицензии зависимостей сохраняются отдельно |
| История | новая публичная история; старая `.git` не переносится |
| Основная ветка | master |
| Участие | только приглашённые Collaborators могут создавать PR |
| Слияние | PR + ci-required, 0 approvals, squash, без bypass |
| Application ID | io.github.hashev.ffido |
| Desktop signing | unsigned, macOS ad-hoc, без notarization |
| Android signing | постоянный keystore, требуется до публикации |
| Каналы | prerelease после merge; stable по vX.Y.Z |
| Публичный выпуск | FFIDO_PUBLICATION_READY=false до полной проверки |

Начальная `master` создана 19 октября 2026 года с MIT и коротким README
(коммит `137312c`); она назначена основной веткой. Исходники и workflow находятся
в [первом PR](https://github.com/hashev/ffido/pull/1), который проверяется GitHub CI.
Настройки доступа и защиты проверяются `audit_github.py`. Публикация пакетов
остаётся выключенной независимо от результатов CI; включение требует отдельного
решения владельца и настройки постоянного Android-ключа.

## 1. Подготовка локального каталога

Из корня исходного монорепозитория:

```sh
python3 -m unittest discover -s scripts/release -p 'test_*.py' -v
python3 scripts/release/export.py ../ffido-publication
```

Каталог назначения должен быть новым и находиться вне исходного дерева.
Экспортирует текущее состояние файлов, включая незакоммиченный монорепозиторий,
но не `.git`, рабочие конфиги/базы, ключи, кеши, uploads и временные checkout.
Исходный каталог сохраняется. Проверка секретов — дополнительная защита, а не
замена ручному review: проверьте `PUBLICATION-MANIFEST.json`, весь список файлов
и `machine_reference_review`. Исторические документы OpenSpec могут упоминать
прежние локальные пути; они не являются путями сборки. Не загружайте ненужные
персональные документы и не исправляйте исторические архивы без причины.

Повторите сборку/тесты из экспортированного каталога по README. Для новой истории
аудит старых коммитов не требуется: они не копируются. Проверьте, что в экспорте
нет `.git`, баз, реальных конфигов, ссылок на внешние файлы и закрытых ключей.
Не используйте `git add .` в исходном смешанном рабочем дереве.

MIT утверждена владельцем. Перед выпуском бинарников проверьте фактическое наличие
legal/source/relink материалов в каждом серверном пакете; MIT не снимает условия
LGPL/Library GPL для включённого Husky. Клиент содержит лицензии Flutter-плагинов.

## 2. Новая история и первоначальная master

Эти команды **публикуют файлы**. Выполняйте их только после review каталога и
отдельного разрешения владельца. Подготовка сценариев сама по себе их не запускает.

Нужна существующая master, чтобы открыть первый PR. Рекомендуемый bootstrap:
создать отдельный seed-каталог с утверждёнными LICENSE и коротким README, затем:

```sh
cd <seed-каталог>
git init -b master
git add LICENSE README.md
git commit -m 'Initialize FFIDO public repository'
git remote add origin https://github.com/hashev/ffido.git
git push -u origin master
gh api --method PATCH repos/hashev/ffido -f default_branch=master
```

GitHub ruleset допускает начальное создание ветки без status check
(`do_not_enforce_on_create`); это не разрешение последующих прямых обновлений.
Если GitHub отклонит именно bootstrap из-за обязательного PR, сначала проверить
точную причину через API; не добавлять постоянный bypass. Любое разовое изменение
правила требует отдельного решения владельца и немедленного восстановления.

После seed клонируйте новый репозиторий в ещё один каталог, создайте ветку
`codex/prepare-publication`, перенесите проверенный экспорт без `.git`, просмотрите
`git diff --cached`, закоммитьте и создайте PR в master. Старую историю не import,
не выполняйте `git push --mirror`. Первый PR оставьте открытым до проверки CI.

## 3. Проверка настроек доступа

В Settings → General → Features: Pull requests → **Collaborators only**.
В Settings → Collaborators приглашайте только выбранных участников.
Сейчас доступ к записи выдан только hashev; скачивание исходников/релизов публично.

Settings → Rules → Rulesets: активное правило master/default branch, без bypass:
Require PR, approvals=0, Require conversation resolution, Require status checks
`ci-required` от GitHub Actions с актуальной базой, Block force pushes,
Restrict deletions. Не включайте Restrict updates вместо PR: это может заблокировать
и нормальное слияние. Разрешён squash merge; обязательного второго reviewer нет.

Read-only проверка:

```sh
python3 scripts/release/audit_github.py
```

До bootstrap она закономерно сообщает, что default branch ещё main.
После первого запуска PR убедитесь в UI, что `ci-required` появился с точным именем.
Проверка с intentional failing check должна запретить merge; зелёная — позволить
владельцу слить собственный PR. Force/delete сценарии проверяйте в одноразовом
репозитории с тем же правилом, не разрушая рабочую master. Не делайте реальный
прямой push «для теста», если его успех добавит нерассмотренный код.

## 4. CI и зависимости

`ci.yml` вызывает `build.yml`. PR не получает signing secrets и write-токен.
Обязательные jobs: release-tools tests, клиентские analyze/test/build на пяти
OS/arch вариантах, backend build/CTest/HPT/static checks/proto на трёх вариантах.
Тестовый HPT собирается из закреплённых Husky-ревизий в локальном build-prefix.
`check_ctest.py` запрещает отсутствующий HPT и skipped tests. amster2 не используется.

Матрица использует Flutter 3.47.7, Java 17, Ubuntu 24.04, Windows 2022 runner,
macOS 15 arm64 и macos-15-intel. Backend выбирает установленный Xcode 26.3
для стандартного `std::stop_token`; deployment target остаётся macOS 15.
Actions закреплены полными commit SHA.
Кеш dependency prefix привязан к runner/архитектуре, fingerprint compiler/SDK/внешних библиотек и содержимому builder scripts.
При смене компилятора/образа сбросьте кеш; не переиспользуйте несовместимые объекты.

Actions → General: workflow permissions Read repository contents; PR approvals
автоматизации выключены. Allow selected actions: GitHub-owned и
`subosito/flutter-action@*` (в YAML всё равно pinned SHA). Другие actions сначала
добавляйте в явный allowlist и проходите review.

При падении server smoke после успешной упаковки сохраняется artifact
`debug-server-<OS>-<arch>` для диагностики; его нельзя считать проверенным выпуском.
Публикация требует успешной матрицы и не собирает artifacts с префиксом debug.

## 5. Постоянный Android signing key

Создание ключа выполняет владелец локально в каталоге **вне Git**. Пример:

```sh
keytool -genkeypair -v -keystore ffido-release.jks -alias ffido \
  -keyalg RSA -keysize 4096 -validity 10000
keytool -list -v -keystore ffido-release.jks -alias ffido
```

Сохраните файл, alias и пароли в защищённой резервной копии. Не отправляйте пароли
в чат, не включайте shell tracing. Без этого же ключа обновления Android могут
потребовать переустановки. Публичный application ID уже выбран; старый com.example
считается отдельным приложением, профили не копируются автоматически.

Settings → Environments → **release**: разрешить deployment master и контролируемых
тегов `v*`, без обязательного reviewer (иначе выпуск перестанет быть автоматическим).
Environment release и политики master/v* созданы через gh. На 2026-10-22
перечисленные Android secrets уже присутствуют; повторно создавать ключ не нужно.
При настройке нового окружения требуются environment secrets:

- `ANDROID_KEYSTORE_BASE64`: Base64 содержимого keystore без дополнительных строк;
- `ANDROID_KEYSTORE_PASSWORD`;
- `ANDROID_KEY_ALIAS`;
- `ANDROID_KEY_PASSWORD`.

Создайте environment variable `ANDROID_CERT_SHA256` — fingerprint из keytool.
Workflow сверяет сертификат готового APK и отклоняет debug-подпись. Временный
keystore создаётся только в signing job, с правами 600 и удалением при завершении.

Desktop на первом этапе без Apple Developer ID/Authenticode. `codesign -s -`
на macOS — ad-hoc, а не подтверждение издателя или notarization. Переход к подписанным
desktop-пакетам требует отдельного изменения pipeline и секретов; текущий упаковщик
не выдаёт неподписанный пакет за подписанный.

## 6. Первый prerelease

Пока проверка пакетов, подпись и legal-комплект не готовы, оставьте repository
variable `FFIDO_PUBLICATION_READY=false`. Release workflow всё ещё проверяет и
собирает неподписанные CI-пакеты, но signing/publish jobs не выполняются.
Публичных пакетов из debug APK не будет.

После успешной проверки полного набора, ключа и лицензий:

```sh
gh variable set FFIDO_PUBLICATION_READY --repo hashev/ffido --body true
```

Следующий merge PR в master запускает Release на итоговом SHA. Для первого
проверенного master можно вручную запустить Release → Run workflow → master.
Ручной retry допускает только доверенный SHA master, не произвольную feature branch.

Версия берётся из `apps/frontend/pubspec.yaml`. Build number — release workflow
run number + offset 1000. Prerelease: `vX.Y.Z-dev.N.<sha>`. При переименовании/замене
workflow нельзя обнулить Android versionCode: увеличьте offset через PR.

Публикация собирает восемь целевых пакетов одного запуска, сверяет manifest и
SHA-256, создаёт draft, загружает файлы, повторно скачивает и проверяет их и только
после этого открывает релиз. Уже публичные файлы не заменяются молча.
Пакеты должны скачиваться без авторизации со страницы Releases, а не только
из временных Actions artifacts.

## 7. Stable и сопровождение

Измените base version через обычный PR. Дождитесь успешного CI/merge, затем:

```sh
git fetch origin master
git tag -a vX.Y.Z <проверенный-SHA-master> -m 'FFIDO X.Y.Z'
git push origin vX.Y.Z
```

Тег должен совпадать с версией исходников и указывать на коммит истории master.
Два активных tag ruleset уже настроены: создание stable-тегов только владельцем,
запрет обновления и удаления всех тегов v*. Правило создания исключает v*-dev.*,
чтобы GITHUB_TOKEN мог создавать автоматические prerelease-теги без отдельного PAT. Не применяйте к стабильным тегам
постоянный bypass всех правил. Пример процесса: отдельное правило создания с
правом владельца и отдельное правило запрета удаления/force без bypass.

Stable пересобирается и проверяется тем же набором jobs, получает полный SHA,
BUILD metadata, manifest и контрольные суммы. Он не является просто переименованием
непроверенного CI-архива.

При инфраструктурном сбое повторите тот же run: draft можно дозагрузить, публичную
версию менять нельзя. При дефекте кода исправьте обычным PR и выпустите новую
версию. Workflow concurrency изолирует повтор одного run; разные merged SHA получают
собственные версии и не ставятся в глобальную concurrency-группу, которая могла бы
отменить ожидающий выпуск. Артефакты берутся только из текущего run.

Перед обновлением backend нужна согласованная backup по README. Ошибочный релиз
пометьте в release notes и предложите предыдущий пакет; не откатывайте схему SQLite
поверх изменённых данных вслепую.

## Критерий завершения первой публикации

Локально: manifest/secret scan, тесты release-tools, YAML/actionlint, чистые
build/test и smoke доступных пакетов. Удалённо: зелёный полный CI, реальные правила
PR/master, постоянная подпись APK и anonymous download полного prerelease/stable.
Недоступная проверка не считается пройденной и отмечается в docs/testing.md.
Commit/push и публикация выполняются только по отдельному запросу владельца.

## Docker Hub

Серверный OCI-образ проверяется в обязательном container job и публикуется в
`hashev/ffido` перед завершением полного GitHub Release. Настройка secrets,
проверка авторизации без push, правила тегов и digest описаны в [Docker](docker.md).

20 октября 2026 года по отдельному согласованию владельца в Actions allowlist
добавлены только `docker/setup-buildx-action@8d2750c68a42422c14e847fe6c8ac0403b4cbd6f`
и `docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9`. GitHub-owned actions
и прежний `subosito/flutter-action@*` сохранены; `verified_allowed=false`.
При обновлении этих actions сначала проверяйте новый commit, затем согласованно
обновляйте pinned SHA в workflow и точечную запись allowlist. Не заменяйте её
wildcard `docker/*` и не разрешайте все verified actions.

## Подписанные метаданные обновления

Начиная с формата `schema_version: 1`, `release-manifest.json` сохраняет прежние
`identity`, `packages` и `container` и добавляет:

- `channel`: `stable` или `dev`, согласованный с `identity.stable`;
- `update_sequence`: `identity.build_number` текущего release workflow;
- `compatibility`: major протокола и поддерживаемые диапазоны клиента/сервера,
  диапазон SQLite schema, `config_format` и `jam_format`;
- у каждого пакета — `component`, `platform.os`, `platform.architecture`,
  `min_os`, `size` в байтах и `compatibility` наряду с прежним `sha256`;
- `macos_appcasts`: immutable XML feeds по архитектурам с размером и SHA-256.

Для Android минимум задаётся `min_os.api=24`, macOS — `min_os.version` по реально
связанным binaries, Windows — version/build, Linux — distribution/version.
Совместимость с текущим состоянием SQLite объявлена только для schema 9;
неизвестные форматы не разрешают автоматическую миграцию. Поля не означают,
что клиент уже проверил версию подключённого сервера через gRPC.

`release-manifest.sig` — JSON с `algorithm: "Ed25519"`, `key_id` и base64 `signature`
над точными байтами manifest, включая завершающий перевод строки. Получатель
сначала проверяет подпись встроенным доверенным ключом, затем схему, идентичность,
последовательность и пакет. Повторная сериализация JSON перед проверкой запрещена.
macOS feed и архив дополнительно имеют Sparkle Ed25519 signatures; feed связан
с manifest своим SHA-256. Формат signing block соответствует Sparkle 2.10.0.
Подпись обновления не является Developer ID, нотариализацией или Authenticode.

`update_sequence` зависит от сохранения истории нумерации release workflow.
При пересоздании workflow оператор должен сохранить возрастающий build number
через существующий `android_build_offset`; уменьшение последовательности
заблокирует обновление у уже видевших новый номер клиентов. Исторические
неподписанные выпуски остаются доступны вручную и не переписываются.

### Ключ выпуска

`scripts/update/public_keys.json` — источник публичных trust anchors. Подключён
ключ `ffido-prod-2026-01`; этот же ID выбран в release settings и встроен в
клиент/Sparkle. Настройка GitHub environment остаётся отдельным шагом: наличие
публичного ключа в исходниках само по себе не включает выпуск.
Приватный ключ нельзя помещать в репозиторий, артефакты CI, журналы или чат.
Для provisioning владелец создаёт и резервирует ключ в защищённом месте вне checkout,
добавляет только публичный base64 ключ в JSON под устойчивым key ID и настраивает
в GitHub environment `release`:

- variable `FFIDO_UPDATE_KEY_ID` — выбранный ID;
- secret `FFIDO_UPDATE_PRIVATE_KEY` — base64 32-байтового Ed25519 seed.

Публичный JSON и ID не являются секретами. После настройки `--check-only` проверяет
не только полный inventory, но и наличие private key, совпадение его публичной части
с trust anchors данного исходного дерева. Эта проверка идёт до push образа.
Отсутствующий, неверный или неизвестный ключ блокирует выпуск. Тестовые ключи
генерируются только в памяти тестов и не добавляются в trust anchors.

Генератор нового update-ключа для локального запуска владельцем:

```sh
build/update-venv/bin/python scripts/release/generate_update_key.py \
  --directory /Users/yurik/Projects/ffido-keys --key-id ffido-prod-2026-01
```

Он создаёт только `update-private-seed.b64` (секрет) и `update-public.json`
(публичный JSON trust anchors) вне checkout, с закрытыми правами. Android keystore,
его пароли, repository settings и GitHub не меняются. Приватное содержимое не
печатается. При повторном запуске существующая согласованная пара проверяется
без ротации; неполная/повреждённая пара, иной key ID и небезопасные права дают
ошибку без перезаписи. `--check-only` проверяет пару, ничего не создавая.
Сначала сохраните защищённую резервную копию; в чат можно передать только
`update-public.json`. Android-ключ, которым подписан уже установленный выпуск,
сохраняйте: этот генератор не заменяет его и не создаёт новый Android signing key.

Для ротации сначала выпустите переходную версию с обоими публичными ключами,
подписанную прежним ключом. Лишь после её распространения переключайте подпись
на новый ключ. Потеря всех доверенных ключей требует ручной установки; SHA-256
или ключ, полученный вместе с неподтверждённым релизом, не восстанавливает доверие.

### Локальная проверка инфраструктуры

Для update tooling нужен Python 3.10+ и отдельное окружение с закреплёнными
зависимостями; системные пакеты не изменяются:

```sh
python3 -m venv build/update-venv
build/update-venv/bin/python -m pip install -r scripts/update/requirements.txt
build/update-venv/bin/python -m unittest discover -s scripts/release -p 'test_*.py' -v
build/update-venv/bin/python -m unittest discover -s scripts/update -p 'test_*.py' -v
```

Тесты publication используют FakeGitHub без сетевой публикации: проверяют подпись
точных байтов, пакет/архитектуру, подписанный appcast, обязательность ключа, повтор
draft и неизменяемость публичных manifest/signature/feed. Наличие этой инфраструктуры
ещё не означает, что UI и платформенные установщики реализованы.

Для macOS выбранный `update_key_id` в `scripts/release/settings.json` должен
совпадать с ID подписи выпуска (при единственном ключе он выбирается автоматически).
Генератор identity и signer используют общую проверку trust store: ID должны
быть корректными, значения — canonical Base64 ровно 32 байт. Неизвестный/пустой
выбранный ID и несколько ключей без явного выбора блокируют генерацию до записи
identity, assets, xcconfig и GITHUB_ENV. Пустой trust store допускается только
для ненастроенной локальной конфигурации без выбранного ID.
Проверка до публикации запрещает несоответствие ключа, встроенного в Sparkle, и
подписи архива. Генератор xcconfig экранирует `/` через переменную, чтобы base64
с `//` не превратился в комментарий Xcode.

Для macOS ad-hoc общая переходная ротация ключей имеет ограничение Sparkle:
смена ключа вместе с нестабильной ad-hoc code identity может потребовать ручного
bootstrap новой сборки. Сохраняйте и резервируйте исходный ключ; не обещайте
бесшовную macOS-ротацию без стабильной Developer ID подписи. Это не меняет
обычный сценарий обновления с тем же ключом.


## Подготовка первого prerelease с managed updates (2026-10-22)

Это первый выпуск новой системы обновлений, а не первый prerelease репозитория.
Read-only проверка GitHub обнаружила последний prerelease
`v1.0.0-dev.1005.4159d0bbf466`: version 1.0.0, Android build_number 1005.
Текущая исходная версия `apps/frontend/pubspec.yaml` — `1.0.0+1`.
Для dev-выпуска оставляем base version 1.0.0; локальный суффикс +1 не используется
как публичный versionCode: Release передаёт Flutter явные build-name/build-number.
При сохранении workflow и offset 1000 следующий новый запуск после run 5 даст
versionCode 1006 и тег `v1.0.0-dev.1006.<sha12>`. Это нижняя оценка, а не
зарезервированный номер: пропущенные/проверочные новые запуски тоже расходуют
run_number. Retry существующего запуска сохраняет номер. Перед публикацией
снова сверяйте actual run_number с последним публичным Android versionCode.
QA versionCode 41001/41002 не публиковались и не задают минимум для пользователей.

Проверена передача единой identity из Release в build.yml и Android signing job,
соответствие постоянному сертификату, выбранный update key и inventory. В environment
release присутствуют четыре Android secrets, update private key и Docker Hub secrets;
публичные ANDROID_CERT_SHA256 и FFIDO_UPDATE_KEY_ID совпадают с локальной конфигурацией.
Наличие secrets не подтверждает их содержимое или работоспособность в Actions:
реальная signing/publish цепочка нового исходного дерева ещё не запускалась.
Actionlint и локальные release/updater unit-тесты прошли.

FFIDO_PUBLICATION_READY остаётся false. При false Release выполняет identity/verify,
но пропускает android-sign и publish. При true publish зависит от всей verify-матрицы
и android-sign; предварительная проверка inventory и update key идёт до push OCI,
затем проверяется опубликованный образ и публикуется полный GitHub Release.
Windows входит в обязательную verify-матрицу: открытая Windows-проверка не обойдена.
Systemd остаётся отдельной незавершённой проверкой и не покрывается зелёной сборкой.

Следующие действия владельца: сохранить резервную копию ключей; отдельно разрешить
commit/push текущих изменений и пройти полную PR CI; проверить actual identity,
комплект пакетов, лицензии и ограничения Windows/systemd; лишь затем отдельным
решением включить publication flag и запуск выпуска. После выпуска проверить
анонимную загрузку manifest/signature/appcast и реальный публичный A→B на следующем
build. Для старых клиентов без updater нужна однократная ручная установка.
Текущие local check-only main-target сборки не являются release candidates.

Локальный отчёт preflight: build/prerelease-preflight/report.json.
Workflow dispatch, commit/push, публикация и изменение release-флага не выполнялись.

## Подготовка CI и публикация

Версии и источники сборки задаются в `scripts/release/dependencies.lock.json`.
Native-компоненты восстанавливаются отдельными точными ключами через
`.github/actions/native-dependencies`; перед использованием проверяется полный
manifest файлов. Workflow `native-dependencies.yml` прогревает доверенный кеш
при изменении сборочных входов в master и доступен вручную. PR читает доступный
кеш основной ветки; кеш merge-ref PR не продвигается в master/tag. Секреты,
рабочие FTN-данные и готовые PR-пакеты в общий комплект не входят.

В `release.yml` android-sign начинает работу после identity одновременно с verify.
Он разрешён только для master и тегов v*, с прежним environment `release` и
production-ключами. Publish по-прежнему ожидает identity, verify и android-sign;
failed/cancelled/skipped обязательного задания блокирует публикацию. Сохраняются
валидация текущего запуска/identity, восемь пакетов, подписи и проверка контейнера.
Раннее завершение подписания не меняет публичные assets или канал обновления.

Переносимые format/analyze запускаются один раз. Платформенные сборки, тесты,
контракты и smoke сохраняются; результат C++-анализа переиспользуется только для
полностью совпавших входов соответствующей платформы. Android fixtures A/B
готовятся один раз, API 24/25/35 проверяются независимо. Только новый коммит того
же PR отменяет предыдущий PR-прогон; master и релизные версии не отменяются.

Сводка `CI timings` и artifact `ci-metrics` разделяют ожидание runner и выполнение,
содержат длительности этапов и оценку критического пути DAG. Для чтения таймингов
caller workflows получают `actions: read`; production-права и ключи в PR не
передаются. `native-log-*` содержит полный сжатый лог и нормализованные входы кеша;
в консоли долгой сборки каждые 30 секунд выводится прогресс. Холодный запуск при
отсутствующем/просроченном кеше остаётся полноценной сборкой.

Docker CTest получает `FFIDO_TEST_RUN=<run_id>.<attempt>` после слоя компиляции:
новый запуск исполняет тесты заново, сохраняя кеш зависимостей и компиляции.
Повторная проверка BuildKit cache в том же workflow использует тот же идентификатор.
После подготовки native-prefix удаляются ненужные CMake build directories;
исходники helper и юридические материалы сохраняются.

Docker-native snapshots хранятся отдельными точными GitHub cache keys. Targets
`native-profile`, `native-cache-import` и `native-cache-snapshot` вычисляют
входы внутри toolchain и переносят компоненты между hosted runners. Вспомогательные
cache targets не являются входами основного image build. Сами snapshots находятся
в `build/docker-native-cache`, отдельно от публикуемого `build/container`.
