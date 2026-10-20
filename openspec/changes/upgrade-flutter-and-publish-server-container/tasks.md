# Tasks

## 1. Flutter и Dart-зависимости

- [x] 1.1 Проверить последний stable через официальный Flutter release manifest, записать точные Flutter/Dart/дату в отчёт обновления в `docs/`; снять исходный `flutter pub outdated --json` из `apps/frontend` и `dart pub outdated --json` из `tools/proto`. Критерий: сохранены исходные версии и проверяемый источник целевой версии.
- [x] 1.2 Обновить Flutter pins в `.github/workflows/build.yml`, `.github/workflows/release.yml`, SDK constraints `apps/frontend/pubspec.yaml` и `tools/proto/pubspec.yaml`, документацию установки; проверить совпадение `flutter --version` во всех путях сборки, не меняя общий SDK разработчика без необходимости.
- [x] 1.3 Обновить прямые зависимости, включая major, и оба lockfile; согласовать grpc/protobuf/protoc_plugin и выполнить необходимые миграции Dart-кода, mocks и платформенных настроек. Критерий: установка с `--enforce-lockfile`, анализ и тесты из `apps/frontend` успешны; повторный pub get не меняет lockfile.
- [x] 1.4 Проверить `tools/proto/generate.sh --check` с закреплённым protoc; при необходимости согласованно обновить генерацию и связанные pins. Выполнить `python3 scripts/check_dart.py --check`; критерий: нет расхождения generated-кода и изменения wire-контракта.
- [x] 1.5 Дополнить отчёт в `docs/` итоговым outdated/deps для клиента и tools/proto, таблицей обновлений и причинами каждого отставания от Latest. Критерий: нет необъяснённого удержания доступных версий constraints проекта и принудительных overrides; необходимое изменение платформенных минимумов явно описано.

## 2. Сборка и эксплуатация контейнера

- [x] 2.1 Добавить корневые `Dockerfile` и `.dockerignore`: многостадийная `linux/amd64` сборка через `scripts/release/dependencies.sh`, корневой CMake и существующую серверную упаковку. Критерий: `docker build --platform linux/amd64 -t ffido:test .` успешен, CTest выполнен, runtime содержит все инструменты/библиотеки/лицензии и не содержит SDK, рабочего дерева исходников, локальных конфигов, ключей и баз; лицензионные архивы исходников и материалы перелинковки сохранены.
- [x] 2.2 Добавить пример контейнерной конфигурации с TLS и `0.0.0.0:8080`, непривилегированного пользователя 10001:10001, exec ENTRYPOINT и документированные mounts/UID/GID. Критерий: сервер запускается с `--user` при корректных правах, admin/helper/wrapper доступны, все изменяемые данные, включая uploads и session key, находятся на постоянных mounts.
- [x] 2.3 Добавить контейнерный smoke в `scripts/release/` с переиспользованием синтетических FTN/TLS fixtures и существующих gRPC-проверок. Критерий: проверены TLS-запрос/вход, отсутствие обязательной конфигурации/TLS, недоступное состояние, SIGTERM и пересоздание контейнера с сохранением сообщения, метаданных, загрузки и действительной сессии; тесты не используют рабочую ноду.
- [x] 2.4 Дополнить `README.md` и серверную документацию командами build/pull/run, запуском admin, mounts, портом, UID/GID, `path_mappings`, общей блокировкой внешнего HPT и rollback по digest. Критерий: команды проверены на синтетическом Linux-стенде без каталогов разработчика; не заявлена поддержка ARM64 или встроенного HPT-сервиса.

## 3. CI и публикация Docker Hub

- [x] 3.1 Добавить container job и включить его в обязательный агрегатор `.github/workflows/build.yml`; передавать проверенный image artifact и release identity текущего run. Критерий: PR выполняет build/smoke без Docker Hub secrets и push, отказ/skip job делает обязательный итог неуспешным.
- [x] 3.2 Добавить в `scripts/release/` вычисление/проверку Docker-тегов из существующей identity и тесты. Критерий: unittest покрывает prerelease, stable, неверную identity, повтор с тем же digest, конфликт digest, порядок обновления `latest` и параллельные выпуски без переназначения версии.
- [x] 3.3 Расширить `.github/workflows/release.yml` загрузкой именно проверенного образа, публикацией в `docker.io/hashev/ffido`, OCI labels, сохранением digest и завершением полного Release после Docker push. Критерий: сохранены существующие gates/`FFIDO_PUBLICATION_READY`/environment `release`; stable получает `X.Y.Z`, SHA и `latest`, prerelease не меняет `latest`; частичный сбой допускает безопасный повтор.
- [x] 3.4 Документировать `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN`, права на репозиторий, настройки выпуска, теги и проверку digest в документации релизов. Критерий: токен не попадает в образ/артефакты/логи, отсутствие credentials при включённой публикации даёт явную ошибку, PR не получает секреты.
- [ ] 3.5 В разрешённом доверенном выпуске проверить доступ к `hashev/ffido`, push, pull по опубликованному digest и повторный smoke; сопоставить SHA/версию с GitHub Release. Критерий: подтверждён фактический образ в реестре; при отсутствии внешнего доступа задача остаётся невыполненной с конкретной причиной.

- [x] 3.6 Добавить в GitHub allowlist репозитория hashev/ffido только одобренные SHA docker/setup-buildx-action и docker/login-action; сохранить существующие patterns/github_owned_allowed/verified_allowed. Критерий: повторный GET API подтверждает точные SHA и прежние ограничения; документирована процедура обновления.

## 4. Итоговая интеграционная проверка

- [ ] 4.1 Из `apps/frontend` выполнить `flutter pub get`, `flutter analyze --no-pub`, `flutter test --no-pub`; подтвердить существующую CI-матрицу release-сборок macOS/Windows/Linux/Android и smoke пакетов. Критерий: результаты сохранены, недоступные локально платформы явно отделены от проверенных.
- [x] 4.2 Из корня выполнить `cmake -S . -B build/backend -DCMAKE_BUILD_TYPE=Debug`, `cmake --build build/backend --parallel 4`, `ctest --test-dir build/backend --output-on-failure` с необходимыми существующими dependency-настройками, проверки C++ и release-tools из CI. Критерий: нет внесённых регрессий; обязательные HPT-проверки не пропущены.
- [x] 4.3 Проверить итоговый diff и `openspec validate upgrade-flutter-and-publish-server-container --strict`. Критерий: сохранены исходные пользовательские изменения, нет секретов/баз/кешей, все выполненные проверки и внешние ограничения отражены в отчёте.
