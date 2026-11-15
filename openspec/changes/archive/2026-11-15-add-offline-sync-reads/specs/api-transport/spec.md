# Spec Delta

## ADDED Requirements

### Requirement: Аддитивный контракт офлайн-чтений
Общий ffido.v1 SHALL добавлять поля и enum без перенумерации, удаления или изменения поведения существующих запросов. C++ и регенерированные Dart-модели SHALL передавать одинаковые значения через gRPC и gRPC-Web.

#### Scenario: Новые wire-поля
- **WHEN** выполняется сериализация и чтение новых полей
- **THEN** сохраняются `Conference: string generation = 17`, `ListMessagesResponse: string generation = 5`, `ListMessagesRequest: string after_message_id = 7`, `ReadArchiveMessageRequest: bool include_subfields = 5`, `ReadArchiveMessageResponse: repeated MessageTechnicalSubfield subfields = 6` и `uint32 attributes2 = 7`
- **AND** `MESSAGE_SORT_NUMBER_ASCENDING` имеет номер 3; прежние номера и типы сохраняются

#### Scenario: Прежний запрос
- **WHEN** клиент использует прежнюю сортировку и не задаёт новые opt-in поля
- **THEN** прежние результаты, ошибки и побочные эффекты сохраняются, кроме добавленных выходных полей; неизвестные поля не требуют миграции клиента

### Requirement: Объявление поддержки офлайн-чтений
SessionInfo SHALL содержать `bool supports_offline_sync = 5`; Login и RestoreSession SHALL устанавливать true вместе с существующими supports-флагами. Отсутствующий флаг старого сервера SHALL означать false.

#### Scenario: Вход и восстановление
- **WHEN** выполнен успешный Login либо RestoreSession
- **THEN** SessionInfo содержит supports_offline_sync=true, профиль, срок действия и прежние capability-флаги

#### Scenario: Старый сервер
- **WHEN** Dart-модель получает SessionInfo без поля 5
- **THEN** supports_offline_sync равен false

### Requirement: Документирование исходной маски JAM
Комментарии Message.attributes и MessageTechnicalData.attributes SHALL указывать, что это сырая маска JAM (Local=0x1, Private=0x4, ...), а не слово атрибутов FTS-0001.

#### Scenario: Проверка контракта атрибутов
- **WHEN** разработчик читает оба объявления attributes в proto
- **THEN** комментарии явно различают JAM и FTS-0001 без изменения значений полей
