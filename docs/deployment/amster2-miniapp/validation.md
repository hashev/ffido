# Проверка подготовки 18.11.2026

## Выполнено в этой задаче

- SSH read-only: ss, df/du, Docker inspect/ps/compose config, конфигурация backend
  с исключением секретных полей, SQLite mode=ro (user_version и sqlite_master),
  сертификаты openssl x509, DNS getent, timedatectl, cron и maintenance-код.
- Рабочая SQLite schema 11, Telegram-таблиц нет. Проверен исходный путь миграции
  schema12 в apps/backend/src/storage/sqlite_store.cpp; сама миграция не запускалась.
- Предложенный Envoy JSON сгенерирован из tools/gateway/run.py и проверен локальным
  Envoy 1.39.3 через --mode validate. Для проверки использовались отдельные
  временные self-signed cert/key, созданные и удалённые на этом Mac. Входные
  server-пути заменялись только во временной копии JSON. Listener не запускался.
- docker compose -f gateway.compose.json config --quiet: успешно.
- docker compose -f backend.override.example.json config --quiet: успешно.
  Для обязательных image-переменных подставлены проверочные значения локально;
  команды не делают pull/build/create/start. Совместный merge с секретным основным
  Compose на сервере не выполнялся: обязателен на этапе применения.
- JSON assertions: IPv4 listener 9443, backend :8080 с DNS SAN/SNI, точный CORS
  origin; schema каталога, уникальные ID, FTN-адреса и HTTPS URL без credentials;
  существующая тестовая запись полностью сохранена. Это структурная проверка,
  не новый Flutter/runtime тест парсера.
- Итоговые файлы просмотрены, git diff --check пройден. В шаблонах только пути,
  публичные адреса/bot_id и обязательные placeholders; private keys/паролей нет.

## Что это не подтверждает

Не проверены восстановление backup, миграция production-копии, кандидат backend/
worker, фактическое чтение сертификатов UID 10001, доступ из network namespace,
production Telegram-вход, issuance/renewal/reload сертификатов, внешний порт 9443,
FTN-публикация и телефоны. Backend, gateway и HPT-тесты повторно не запускались,
поскольку здесь подготовлены только документация и конфигурационные шаблоны.
Сборка приложения, новый backend image, публикация и развёртывание не выполнялись.

Повторная проверка в конце: хеши docker-compose.yaml, ffido/config.json,
image-override.json и hpt.cfg совпали с началом обследования. Время старта
ffido, ffido-tosser, fido, jamnntpd и обоих тестовых контейнеров не изменилось.
