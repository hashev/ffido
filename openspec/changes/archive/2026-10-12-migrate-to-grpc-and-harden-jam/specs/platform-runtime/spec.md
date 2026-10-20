# Spec Delta

## MODIFIED Requirements

### Requirement: Исходящая сеть
Приложение SHALL поддерживать защищённые соединения gRPC на Android, iOS, Windows, Linux и macOS и gRPC-Web в Web release. Разрешения Android release и sandbox macOS SHALL допускать сеть; Web SHALL работать через настроенный шлюз с корректным CORS.

#### Scenario: Производственная сеть
- **WHEN** приложение Android release или sandbox macOS вызывает gRPC по TLS
- **THEN** платформенные разрешения допускают исходящее соединение

#### Scenario: Остальные нативные платформы
- **WHEN** приложение iOS, Windows или Linux вызывает общий API
- **THEN** соединение и protobuf-ответ обрабатываются нативным gRPC-транспортом

#### Scenario: Web release
- **WHEN** браузерный клиент с разрешённого origin обращается к API через шлюз
- **THEN** gRPC-Web передаёт авторизацию, ответы и ошибки без нарушения CORS

#### Scenario: Недоверенный сертификат
- **WHEN** сервер или шлюз предъявляет недоверенный сертификат
- **THEN** клиент отклоняет соединение и не отключает проверку TLS
