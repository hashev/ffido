# Локальный gRPC-Web шлюз

## Публичный endpoint для Web / Telegram

По умолчанию listener остаётся на `127.0.0.1`. Для явно разрешённого публичного
развёртывания предусмотрен `--listen-address 0.0.0.0` (или нужный IP) и `--port 443`;
также можно оставить loopback за существующим TLS-прокси. Не запускайте процесс
от root ради порта: используйте штатный supervisor/прокси и минимальные права ОС.
Для Pages задайте `--origin https://hashev.github.io` без `/ffido/`.
Этот origin общий для проектов владельца; CORS не различает пути на нём.

Let’s Encrypt подходит: `--certificate` указывает `fullchain.pem`, `--private-key` —
`privkey.pem`, SAN соответствует публичному имени endpoint. ACME-клиент продлевает
сертификат; deploy hook обязан применить новые файлы в службе завершения TLS.
Статическая конфигурация этого wrapper сама не выполняет hot reload сертификатов:
для прямого Envoy listener предусмотрите управляемый restart/hot-restart supervisor,
для внешнего TLS-прокси — его штатный reload. Проверяйте новый serial/expiry новым
TLS-соединением; смена файла на диске не доказывает применение сертификата.
Upstream к FFIDO остаётся TLS с `--backend-ca` и проверкой DNS SAN.

Проверка генератора без публичного запуска: `python3.12 -m unittest discover -s tools/gateway -p 'test_*.py'`
из корня, затем `run.py ... --validate` с установленным Envoy и тестовыми сертификатами.
Ни публикация, ни выпуск сертификатов этими тестами не выполняются.

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
