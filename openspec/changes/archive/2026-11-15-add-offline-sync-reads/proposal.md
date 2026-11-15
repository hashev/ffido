# Proposal

## Why

Для офлайн-синхронизации клиенту нужны поколение JAM-базы, последовательная выборка новых номеров независимо от даты письма и исходные технические поля без отметки чтения. Существующий ffido.v1 не предоставляет эти возможности вместе.

## What Changes

- Добавить `SessionInfo.supports_offline_sync = 5`, возвращать true в Login и RestoreSession.
- Выдавать существующее поколение JAM в `Conference.generation = 17` и `ListMessagesResponse.generation = 5`, включая ListMessages, GetThread и GetArchiveThread.
- Добавить `MESSAGE_SORT_NUMBER_ASCENDING = 3` только для ListMessages и `after_message_id = 7`; проверять поколение и диапазон, разрешать удалённый курсор и не читать старые заголовки.
- Добавить opt-in `ReadArchiveMessageRequest.include_subfields = 5`, все сырые подполя в `ReadArchiveMessageResponse.subfields = 6` и второе слово атрибутов `attributes2 = 7`, сохраняя сворачивание и отсутствие побочных эффектов.
- Уточнить комментарии основной маски атрибутов JAM в Message и MessageTechnicalData.
- Добавить контрактные и сервисные регрессионные тесты; регенерировать Dart штатным генератором.

Все изменения аддитивны: номера существующих полей и поведение прежних запросов сохраняются; рефакторинг не входит в объём.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `api-transport`: аддитивный wire-контракт и объявление поддержки офлайн-чтений.
- `conference-browsing`: поколение базы и последовательное чтение ListMessages по JAM-номеру.
- `archive-research`: полные сырые подполя и attributes2 при явном архивном чтении.

## Impact

`contracts/ffido/v1/ffido.proto`, C++ domain/service/storage и gRPC mapping в `apps/backend/`, `apps/frontend/lib/api/generated/`, `contracts/tests/test_contract.cpp`, `apps/backend/tests/`, `apps/frontend/test/api/contract_test.dart`. C++/descriptor генерирует CMake, Dart — `tools/proto/generate.sh`. Новые зависимости, миграции SQLite, интерфейс офлайн-кеша и изменения UI не требуются. Существующие незавершённые изменения репозитория сохраняются.
