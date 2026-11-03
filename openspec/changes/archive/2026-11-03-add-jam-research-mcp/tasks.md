# Tasks

## 1. Архивный контракт и чтение без отметок

- [x] 1.1 В `contracts/ffido/v1/ffido.proto` добавить SearchArchiveMessages, ReadArchiveMessage и GetArchiveThread с references, периодом, сортировкой, cursor/complete и блочным телом; дополнить `contracts/tests/test_contract.cpp`, проверить сериализацию Unicode и сохранение старых полей/RPC.
- [x] 1.2 В `apps/backend/src/service/message_service.cpp` и соответствующих headers реализовать архивное чтение поверх существующих JAM-примитивов с фильтрами, reveal и UTF-8 блоками; тестами в `apps/backend/tests/integration/test_services.cpp` подтвердить неизменность прочитанности, истории, позиции и JAM, границы символов и ошибки offsets.
- [x] 1.3 Подключить архивные handlers в `apps/backend/src/service/grpc_service.cpp` с сессией, deadline и отменой; gRPC-тестами проверить доступный reference, чужой mailbox, отсутствие сессии и отсутствие RecordView.
- [x] 1.4 Реализовать архивную цепочку с переиспользованием текущего traversal; тестами покрыть недостающих родителей, циклы, неоднозначный MSGID, пагинацию и свёрнутые письма без выдачи тела.
- [x] 1.5 Документировать новые RPC, offsets и неизменность обычного GetMessage/FindMessage в `apps/backend/README.md`; сверить примеры с контрактом и проходящими тестами.

## 2. Поиск и ограниченное продолжение

- [x] 2.1 Реализовать в `apps/backend/src/service/` поиск 1–20 областей с общей авторизацией до чтения, периодом [from,to), существующими FoldSearch/SearchRanges и стабильной сортировкой; unit/integration тестами проверить кириллицу, Ё/ё, CP866/override, буквальные метасимволы и границы периода.
- [x] 2.2 Добавить ограниченное состояние scan/sort/page, cursor с привязкой к профилю/запросу/поколениям/ревизии фильтров, TTL и memory quotas по design.md; тестами с уменьшенными бюджетами проверить пустую неполную страницу, продолжение, порядок без дублей, expiry, чужой cursor и RESOURCE_EXHAUSTED.
- [x] 2.3 Проверять изменение JAM до/после каждой порции и повторные права при продолжении; интеграционными тестами моделировать append/pack, перезапуск backend, отзыв роли, изменение фильтра и отмену без ложного результата «совпадений нет».
- [x] 2.4 Формировать snippets, source references и результаты сворачивания без утечки скрытого тела; тестами подтвердить валидный Unicode, чтение точного источника и различие полного/частичного/пустого результата. Описать семантику и лимиты поиска в `apps/backend/README.md`.

## 3. Просмотр и проверка публикации на backend

- [x] 3.1 Добавить PreviewMessage и optional expected_preview_digest в `contracts/ffido/v1/ffido.proto`; контрактными тестами проверить backward compatibility старого CreateMessageRequest и поля просмотра.
- [x] 3.2 В `MessageService::CreateMessage` переиспользовать текущий план/validate_only для PreviewMessage с фактическим текстом, адресацией, публичностью, кодировкой и digest; тестами подтвердить отсутствие JAM-записи, transport intent и RecordView при просмотре эхи/netmail/LocalArea.
- [x] 3.3 Проверять expected_preview_digest первой публикации под координацией плана/записи, сохранив старую семантику без digest и идемпотентный replay; тестами проверить изменение текста, кодировки, профиля, родителя, отзыв прав, повтор и непредставимые символы без частичной записи.
- [x] 3.4 Подключить PreviewMessage в gRPC и описать preview/digest/saved_locally в `apps/backend/README.md`; gRPC-тестами проверить личную и публичную адресацию, запрет служебных областей и отсутствие обещания сетевой доставки.

## 4. MCP-процесс, конфигурация и подключение профиля

- [x] 4.1 Добавить `apps/backend/src/mcp/` и target ffido-mcp в `apps/backend/CMakeLists.txt` без доступа к storage и новых зависимостей; проверить сборку из корня и отдельный запуск executable.
- [x] 4.2 Реализовать CONFIG/session_file/state_dir, проверку безопасных файлов, TLS, отдельные read/post allowlist и локальный `ffido-mcp login CONFIG`; тестами с временными файлами и локальным TLS подтвердить права, атомарную запись, невалидный сертификат, отсутствие пароля/токена в argv/логах и независимую сессию.
- [x] 4.3 Реализовать JSON-RPC stdio lifecycle, protocol negotiation, ping, initialized, EOF, errors/notifications, reader/worker pool и cancellation; subprocess-тестами проверить stdout purity, запрос до initialize, неверный JSON/метод, лимиты строки, параллелизм и отзыв отмены в gRPC.
- [x] 4.4 Создать `docs/mcp.md` с примером локальной настройки и stdio-подключения, границей авторизации и передачей данных ассистенту; вручную воспроизвести инструкции на временном тестовом backend без production-публикаций.

## 5. Инструменты исследования и шаблоны MCP

- [x] 5.1 Реализовать tools/list и пять читающих инструментов из design.md с input/outputSchema, structuredContent/text, аннотациями, allowlist и контролируемыми ошибками; wire-тестами проверить все схемы, закрытую область, total после фильтрации и UNIMPLEMENTED без fallback.
- [x] 5.2 Реализовать безопасное представление raw bytes, source_uri, offsets, complete/cursor и ограничение ответа; тестами проверить base64, escaping ID, длинный текст, скрытые snippets и отсутствие молчаливого усечения.
- [x] 5.3 Реализовать prompts/list/get: research_topic, digest_period, explain_thread; snapshot/wire-тестами проверить аргументы, требование источников, неполноту, недоверенный текст писем и отсутствие автоматических вызовов чтения/отправки.
- [x] 5.4 Дополнить `docs/mcp.md` примерами поиска решения, дайджеста и диагностики, пояснить буквальный поиск и URI как идентификатор источника; воспроизвести сценарии на фикстурах и сверить references с письмами.

## 6. Подготовка и отправка через MCP

- [x] 6.1 Реализовать ffido_prepare_message с PreviewMessage, устойчивой записью immutable draft и одним operation_id; тестами проверить точность просмотра, TTL 15 минут, профиль/endpoint binding, crash до выдачи draft_id и права state_dir.
- [x] 6.2 Реализовать ffido_send_message с confirm=true, проверкой post allowlist, состояниями prepared/attempted/completed и сохранёнными digest/request; тестами проверить неверный/истёкший draft, подмену параметров, повтор, concurrent send одного draft и смену прав.
- [x] 6.3 Добавить subprocess+TLS интеграционный тест потери ответа после записи, перезапуска MCP и повтора с тем же draft_id; подтвердить одну JAM-запись, один FTN MSGID, сохранённый operation_id, outcome_unknown при неопределённости и отсутствие обещания отката при отмене.
- [x] 6.4 В schemas/descriptions и `docs/mcp.md` описать показ просмотра, разрешение пользователя в MCP-клиенте, ограниченность confirm, saved_locally и локальное удаление drafts; проверить, что инструменты не предлагают кросспостинг, UUE или HPT-команды.

## 7. Поставка и общая проверка совместимости

- [x] 7.1 В `apps/backend/CMakeLists.txt` и `scripts/release/` включить ffido-mcp в серверные пакеты Linux/macOS и существующую проверку зависимостей/BUILD metadata; тестами упаковки проверить executable и отсутствие локальных CONFIG, сессий, drafts, JAM и SQLite.
- [x] 7.2 Регенерировать Dart через `tools/proto/generate.sh`, выполнить `tools/proto/generate.sh --check`, контрактные тесты C++, затем из `apps/frontend/` выполнить `flutter pub get`, `flutter analyze --no-pub`, `flutter test --no-pub`; подтвердить прежнее поведение клиента без MCP.
- [x] 7.3 Выполнить из корня `cmake -S . -B build/backend -DCMAKE_BUILD_TYPE=Debug`, `cmake --build build/backend --parallel 4`, `ctest --test-dir build/backend --output-on-failure`, предусмотренные CI проверки `scripts/check_cpp.py` и `scripts/check_dart.py` по их существующим параметрам; устранить внесённые ошибки, явно зафиксировать недоступные проверки.
- [x] 7.4 Провести сквозной сценарий через настоящий stdio MCP-клиент на временных базах: поиск → письмо → цепочка → просмотр → разрешённая тестовая публикация → повтор; подтвердить неизменность чтения и одну запись. Проверить итоговый diff и `openspec validate add-jam-research-mcp --strict`.


## Результаты проверки реализации

Проверено 2026-11-03 на macOS:

- Корневые CMake configure/build и полный CTest: 447 успешно, 5 внешних HPT-сценариев помечены Skipped (452 зарегистрированных теста).
- После последней правки диагностического JSON повторены MCP-протокол и установка: 13/13 успешно.
- C++ format-check и clang-tidy: 111 файлов / 57 translation units; дополнительно проверен последний изменённый server.cpp. Новых диагностик нет. Сохраняется прежнее предупреждение nodiscard в apps/backend/tests/integration/test_process.cpp:244; этот файл не изменялся.
- Dart-генерация и generate.sh --check; flutter pub get --offline, flutter analyze --no-pub без замечаний, flutter test --no-pub: 614 успешно, 2 пропущены. Использован уже установленный Flutter 3.47.7 / Dart 3.13.5 без обновления зависимостей.
- scripts/check_dart.py --check: 183 файла, без изменений форматирования.
- scripts/release/test_release.py: 33/33 успешно в существующем build/update-venv. Проверена реальная установка ffido-mcp и документации без локальных данных/сессий/JAM.
- Сквозные subprocess-тесты используют временные JAM/SQLite и локальный TLS: исследование без отметок, ввод пароля без эха, независимые сессии, просмотр, параллельная отправка, потеря ответа после записи, перезапуск и повтор без дублей, отзыв доступа, отмена, лимиты и base64.
- Проверены итоговый diff, новые файлы и openspec validate add-jam-research-mcp --strict. Реальные эхи и пользовательские FTN-базы не использовались.

Linux-сборка и внешние HPT-сценарии в этом запуске не проверены. Коммит, публикация и архивирование не выполнялись.
