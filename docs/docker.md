# Сервер FFIDO в Docker

Образ `docker.io/hashev/ffido` предназначен для Linux amd64. Он содержит TLS gRPC
сервер, `ffido-admin`, `ffido-hpt-auth`, `ffido-run-hpt`, runtime-библиотеки и
лицензионные архивы с материалами перелинковки. HPT запускается отдельно.
Web-клиенту по-прежнему нужен HTTPS gRPC-Web шлюз. OCI license label MIT
относится к собственному коду FFIDO; условия сторонних компонентов находятся в
`/opt/ffido/legal/THIRD_PARTY_NOTICES.md` и `share/ffido/legal/`.

## Сборка и проверка

Из корня монорепозитория:

```sh
docker build --platform linux/amd64 -t ffido:test .
python3 scripts/release/container_smoke.py ffido:test
```

Для smoke нужен Flutter 3.47.7 / Dart 3.13.5 в PATH и установленный набор
зависимостей клиента (`cd apps/frontend && flutter pub get --enforce-lockfile`).
Проверки используют временные конфиги, CA и JAM-базы. Рабочая нода не нужна.
Smoke проверяет TLS gRPC, отсутствие конфигурации/TLS, недоступное состояние,
сессию, сообщение, метаданные и незавершённую загрузку после пересоздания.

Dockerfile собирает закреплённые native-зависимости и сервер корневым CMake,
выполняет CTest с HPT и использует существующую серверную упаковку. На ARM Mac
сборка amd64 выполняется через эмуляцию и может занять значительное время.

## Установка

Создайте отдельные каталоги конфигурации, TLS и состояния. Для нового каталога
состояния на Linux задайте владельца 10001:10001; не меняйте рекурсивно владельца
существующей FTN-базы. Пример ниже предполагает стандартного пользователя образа:

```sh
sudo install -d -m 0750 -o 10001 -g 10001 /var/lib/ffido
sudo install -d -m 0750 -o root -g 10001 /etc/ffido/tls
sudo install -m 0640 -o root -g 10001 \
  apps/backend/config.container.example.json /etc/ffido/config.json
```

Установите собственные сертификат и приватный ключ в `/etc/ffido/tls/server.pem`
и `/etc/ffido/tls/server-key.pem`, доступные контейнерному UID/GID на чтение.
Приватный ключ не должен быть доступен всем. Настройте пример перед запуском:

| Данные | Путь внутри контейнера | Доступ |
|---|---|---|
| Конфигурация | `/etc/ffido/config.json` | Только чтение |
| TLS | `/etc/ffido/tls` | Только чтение |
| SQLite, session key, staging uploads | `/var/lib/ffido` | Чтение/запись |
| Конфигурация HPT и области FTN | `/srv/fido` | Конфиги читаются; JAM и общий lock доступны на запись |

Uploads этого сервера хранятся в SQLite metadata, отдельный ephemeral-каталог
uploads для них не требуется. Сохраняйте весь каталог SQLite вместе с WAL/SHM
и `session.key`; не переносите активную SQLite копированием одного файла.

Пример конфигурации слушает `0.0.0.0:8080`. Сертификат должен соответствовать
публичному имени сервера и быть доверенным клиенту. TLS не отключается.
Замените `1.0.0` на фактически опубликованную версию:

```sh
docker pull hashev/ffido:1.0.0
docker run -d --name ffido --restart unless-stopped \
  --platform linux/amd64 \
  -p 8080:8080 \
  --mount type=bind,src=/etc/ffido/config.json,dst=/etc/ffido/config.json,readonly \
  --mount type=bind,src=/etc/ffido/tls,dst=/etc/ffido/tls,readonly \
  --mount type=bind,src=/var/lib/ffido,dst=/var/lib/ffido \
  --mount type=bind,src=/srv/fido,dst=/srv/fido \
  hashev/ffido:1.0.0
docker logs ffido
```

Образ работает как 10001:10001. Если FTN-данными владеет другой пользователь,
задайте `--user UID:GID` и обеспечьте этому UID/GID чтение конфигов/ключей и
запись SQLite, JAM и lock. Поддержка файловых блокировок bind mount обязательна;
сетевые FS без такой гарантии не поддерживаются.

`hpt.cfg`, включаемые файлы и `areas.cfg` должны ссылаться на пути, доступные
в контейнере. Если host-пути отличаются, задайте существующий `ftn.path_mappings`
по [инструкции FTN](ftn-check.md); не переписывайте рабочие конфиги автоматически.
Для внешнего HPT задайте тот же физический файл `ftn.coordination_lock`, что
доступен контейнеру: например `/srv/fido/ffido-hpt.lock`. На хосте запускайте HPT
через существующий `scripts/run_hpt.py --config HOST_CONFIG -- hpt ...` с тем же
lock; host-конфиг может иметь свои пути, но файл блокировки должен быть общим.

Администрирование выполняется с теми же mounts и пользователем:

```sh
docker exec ffido ffido-admin --help
docker exec ffido ffido-admin provision-mailboxes /etc/ffido/config.json
docker stop --time 20 ffido
```

В контейнере не запущен HPT-демон; наличие wrapper не заменяет установленный HPT
на хосте. `docker stop` передаёт SIGTERM непосредственно серверу.

## Версии, обновление и откат

| Тег | Назначение |
|---|---|
| `X.Y.Z-dev.BUILD.SHA12` | Проверенный prerelease из master |
| `X.Y.Z` | Проверенный стабильный выпуск по `vX.Y.Z` |
| `sha-<полный SHA>` | Первый проверенный образ коммита; поздний stable его не заменяет |
| `latest` | Наибольшая опубликованная стабильная версия |

SHA-тег может сохранять prerelease-метаданные, если stable выпускается из того же
коммита. Для точного стабильного выпуска используйте тег версии или digest из
`release-manifest.json` GitHub Release. Version-теги не переназначаются другому
digest; повтор с другими байтами блокируется и требует новой версии.

Для обновления остановите и удалите только контейнер, затем повторите `docker run`
с прежними mounts и новой версией. Сохранённые сессии требуют прежнего session key.
Для отката используйте предыдущий опубликованный `hashev/ffido@sha256:...` с теми
же mounts. Изменение не вводит миграции форматов данных. Резервную копию состояния
делайте штатным способом до обновления; не используйте `docker rm -v` для удаления
постоянных данных.

## Настройка выпуска

В GitHub environment `release` нужны `DOCKERHUB_USERNAME` и `DOCKERHUB_TOKEN`.
Токен должен предоставлять Read/Write для `hashev/ffido`; пароль аккаунта не нужен.
Включение выпуска управляется существующей переменной `FFIDO_PUBLICATION_READY`.
PR собирает и проверяет образ без push и секретов. В ограниченном Actions
allowlist должны быть разрешены ровно закреплённые SHA Docker actions из workflow;
процедура обновления описана в [публикации GitHub](github-publication.md).

После доставки workflow в master можно отдельно проверить авторизацию и право
push без загрузки образов:

```sh
gh workflow run dockerhub-check.yml --repo hashev/ffido --ref master
```

Проверка получает scope `pull,push` у Docker Hub auth service и выводит только
результат. Ни пароль, ни registry token не печатаются. Этот workflow не выпускает
GitHub Release и не публикует образы.

Обычный выпуск сначала проходит полную существующую матрицу, Android-подпись и
container smoke. Затем проверенный OCI-архив текущего запуска публикуется с
сохранением digest; скачанный по digest образ проверяется повторно. Полный GitHub
Release завершается только после этого. Публикации сериализованы, чтобы старый
запуск не откатил `latest`. При частичном сбое Docker Hub/GitHub повтор продолжает
тот же выпуск без замены уже опубликованной версии.
