# Рабочий gateway9443: запуск и локальная проверка

19.11.2026 запущен отдельный `ffido-miniapp-main-gateway` из подготовленного Compose
в `/srv/ffido-miniapp-main`. Рабочие backend/tosser/fido/jamnntpd и тестовые
backend/gateway не перезапускались: image IDs и start times совпали с исходными.

Образ: sha256:8f34a3f1f8c804af3f975bc19a50104120482535401d5c8e954156c20ffd5316.
Запуск с явным gateway.pinned.env, `--no-deps --no-build --pull never`.
Listener IPv4 `0.0.0.0:9443`, network_mode=host, UID/GID10001, read-only filesystem,
cap_dropALL. Внешний допуск9443 не открывался; AMSTER-INPUT совпал байт-в-байт.
Основной backend по-прежнему schema12 на прежнем закреплённом образе.

## Изменение для совместной работы с тестовым gateway

Первый запуск завершался до создания listener: Envoy сообщил
`unable to bind domain socket with base_id=0 ... errno=98`.
Два Envoy с host network конфликтовали за стандартный hot-restart domain socket.
В рабочий `gateway.compose.json` добавлен **--disable-hot-restart**; контейнер
пересоздан, тестовый не трогали. Поддержка флага проверена у закреплённого бинарника.
Для принятого cold restart контейнера при продлении сертификата hot restart не нужен.

Окончательный контейнер стартовал в10:56:22 UTC (13:56:22 MSK); после исправления
RestartCount=0. Это не утверждение об отсутствии неудачных первоначальных запусков.
Штатный renew script остановит/запустит только этот gateway, сохраняя новый command.

## Фактически выполненные проверки

HTTPS-соединения направлялись на127.0.0.1:9443 с настоящими SNI/Host
`f120n5015z2.ddns.net`. Проверка системной цепочки и hostname включена, без -k.

- TLS1.3; предъявленный leaf DER точно совпал с production fullchain.pem.
  Используется отдельный production сертификат до17.02.2027, не тестовый ключ/сертификат.
- OPTIONS с Origin`https://hashev.github.io`, методомPOST и заголовками
  authorization/content-type/x-grpc-web: допустимый preflight, точный ACAO,
  POST/OPTIONS в Allow-Methods, необходимые заголовки разрешены. GET не разрешён CORS.
- POST с чужим Origin и без Origin: HTTP403, без Access-Control-Allow-Origin.
- `GetServerCapabilities` через binary gRPC-Web: HTTP200, protobuf supports_telegram=true,
  настоящий grpc-status0 в декодированных frames/trailers.
- То же через text gRPC-Web с Content-Type и Accept application/grpc-web-text:
  успешные base64 framing, protobuf response и grpc-status0.
- `ListConferences` без сессии и `ListTelegramProfiles` без Telegram proof:
  grpc-status16 (UNAUTHENTICATED), а не ложный успех только по HTTP200.
  Учтён допустимый trailers-only ответ с grpc-status в initial headers.
- grpc-status доступен браузеру через Access-Control-Expose-Headers.
- Работающая пара backend/tosser healthy, новый gateway running без перезапусков;
  тестовые и остальные рабочие контейнеры сохранили image/start times.

Положительный ответ backend также подтверждает upstream TLS HTTP/2 до native8080
с настроенными CA/SNI/SAN; verification не отключалась. Внешний HTTPS9443, браузерный
вход и реальный подписанный Telegram initData в этом этапе не проверялись.
Пароли/сессии не использовались, сообщения не читались и не отправлялись.

Свидетельства на сервере: `gateway-start-before.json` и
`gateway-local-validation.json` в `/srv/ffido-miniapp-main`.
Безопасная сводка и проверочный скрипт сохранены локально в build/amster2-gateway-20261119.
`git diff --check` успешно. Приёмка выполнена на реальном gateway, не только
через offline Envoy validate. Никакого изменения firewall, каталога или Web публикации.

Повтор preflight на самом amster2:

```sh
curl --resolve f120n5015z2.ddns.net:9443:127.0.0.1 \
  -X OPTIONS -D - -o /dev/null \
  -H 'Origin: https://hashev.github.io' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,content-type,x-grpc-web' \
  https://f120n5015z2.ddns.net:9443/ffido.v1.Ffido/GetServerCapabilities
```

Следующий этап требует отдельного разрешения: допустить TCP9443 в active/persistent
AMSTER-INPUT и проверить HTTPS/gRPC-Web/CORS снаружи; затем публиковать запись
основного backend в каталоге. Автоapply backend по-прежнему оставлен на паузе.
