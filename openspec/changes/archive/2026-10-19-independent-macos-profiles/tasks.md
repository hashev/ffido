# Tasks

## 1. Выбор и хранение профиля

- [x] 1.1 Добавить bootstrap bridge и разбор аргументов в `apps/frontend/macos/Runner/`, стабильный профиль в Flutter до первого SharedPreferences.getInstance в `apps/frontend/lib/main.dart`; проверить допустимые/ошибочные/повторные аргументы, default и два namespace тестами; зафиксировать синтаксис в `apps/frontend/README.md`.
- [x] 1.2 Внедрить раннюю настройку непересекающихся prefixes и единый контекст во все потребители настроек/кеша, включая `apps/frontend/lib/pages/settings.dart` и `repositories/conference_repository.dart`; тестами проверить чтение, изменение и очистку point1/point2/default без потери соседних ключей и отсутствие импорта старого аккаунта.
- [x] 1.3 Изолировать ключи `apps/frontend/lib/api/session_store.dart` по профилю и endpoint, сохранив legacy-ключи default; расширить `apps/frontend/test/api/session_store_test.dart` сценариями одного endpoint, restore, logout, смены endpoint, отказа записи и revoked session, проверяя отсутствие удаления чужих секретов; описать первое подключение и rollback.

## 2. Независимые процессы и заголовок

- [x] 2.1 Добавить lifetime flock профиля в macOS Runner до Flutter bootstrap; проверить второй запуск того же ID, параллельные разные ID, освобождение после закрытия/сбоя и ошибку доступа, с понятным NSAlert; документировать необходимость закрыть прежние экземпляры без lock перед первым запуском.
- [x] 2.2 Добавить обновление NSWindow.title через bridge и Flutter lifecycle login/restore/logout/auth invalidation в `apps/frontend/lib/main.dart` и соответствующих API-точках; тестами проверить актуальные имя/адрес, default/именованный профиль, очистку и порядок sessionChanges, отсутствие секретов и no-op остальных платформ; описать формат заголовка в README.

## 3. Интеграционная проверка

- [x] 3.1 Выполнить из `apps/frontend/` flutter pub get, analyze --no-pub, test --no-pub, форматирование изменённых Dart-файлов и macOS release build; запустить два профиля на одном endpoint временного стенда, проверить отправку/ответ, независимый logout и восстановление после перезапуска, заголовки и занятый профиль; записать фактические результаты и ограничения в `docs/manual-test-results.md`, не меняя рабочие HPT/JAM.
- [x] 3.2 Проверить `openspec validate independent-macos-profiles --strict`, итоговый diff и отсутствие изменений backend/API/реальных конфигов; убедиться, что инструкция запуска двух профилей воспроизводима и legacy вход сохранён.

## Workflow follow-up

- После реализации и проверок предложить синхронизацию спецификации и архивирование отдельным запросом.
