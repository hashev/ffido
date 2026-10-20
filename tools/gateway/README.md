# Локальный gRPC-Web шлюз

Нужен установленный Envoy с v3 API; локальная проверка использует Envoy 1.39.3.
Шлюз запускается отдельным процессом без Docker. Backend принимает только TLS
на localhost:8080; браузер обращается к TLS listener шлюза localhost:8443.
Администратор назначает HTTPS origin клиента. Сертификаты backend и шлюза
должны содержать DNS SAN соответствующих имён и доверяться ОС/браузеру.

```sh
python3 tools/gateway/run.py \
  --origin https://localhost:9443 \
  --certificate /absolute/path/web-server.pem \
  --private-key /absolute/path/web-server-key.pem \
  --backend-ca /absolute/path/backend-ca.pem \
  --output build/gateway/envoy.json
```

`--validate` проверяет конфигурацию без запуска. Если Envoy вне PATH, передайте
`--envoy /absolute/path/envoy`. Параметры backend-host/backend-port/port меняют
адреса; listener по умолчанию доступен только на loopback. Конфигурация содержит
пути к ключам, а не сами ключи. Runtime конфигурацию и сертификаты не добавляют в Git.

Origin должен точно совпадать, без пути и завершающего `/`. RBAC отклоняет
другие Origin, CORS разрешает лишь POST/OPTIONS, необходимые заголовки gRPC-Web
и authorization. Backend проверяет пароль HPT при Login и внутреннюю сессию остальных RPC.
Шлюз проверяет CA и DNS SAN backend и использует HTTP/2. Лимиты: metadata 8 KiB,
request 2 MiB, RPC/idle timeout 15 s; backend также ограничивает ответы 4 MiB.
Admin listener и access logging с пользовательскими metadata не включены.

Основания конфигурации: [gRPC-Web filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/grpc_web_filter),
[CORS filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/cors_filter),
[HTTP RBAC](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/rbac_filter).
