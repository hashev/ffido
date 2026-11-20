# Локальная проверка safe-signed-node-transition

## Границы

Рабочие службы, конфигурации и firewall amster2 не изменялись. Релиз не
публиковался, автообновления не возобновлялись. Для локального Docker был прочитан
существующий серверный архив подготовленных worker-образов; SHA-256 архива проверен.
Новых серверных архивов и контейнеров не создавалось.

Сквозной стенд использует образы исходной пары amster2, отдельный Linux volume,
два фиктивных поинта 2:1/2.1–2, частный QA signing key и loopback registry/gateway.
Данные личной переписки и рабочие credentials в fixture не используются. Worker
работает без сети и проверяет distribution, HPT и SQLite, но не обрабатывает
транспортные очереди. Реальные HPT-циклы проверяются отдельным backend gate.
Telegram public key заменяется только в временной QA-копии исходника.

## Подтверждённые проверки

| Проверка | Результат |
| --- | --- |
| `cmake --build build/backend --parallel 4` | Успешно |
| `FFIDO_TEST_HPT="$PWD/build/publication-deps/prefix/bin/hpt" CTEST_PARALLEL_LEVEL=4 python3 scripts/release/check_ctest.py build/backend` | 564/564, без skipped HPT, 232,78 с |
| `python3 scripts/check_cpp.py --build-dir build/backend` | Format и clang-tidy: 129 файлов, 65 translation units |
| `scripts/test_mailbox_restore.py ADMIN FAULT_LIBRARY` | 20 тестов на macOS и 20 в Linux |
| `build/update-venv/bin/python -m unittest discover -s scripts/release -p 'test_*.py'` | 107 тестов |
| `build/update-venv/bin/python -m unittest discover -s scripts/update -p 'test_*.py'` | 107 тестов |
| Тот же updater suite через `build/telegram-python/bin/python` (3.12.16) | 107 тестов |
| Focused Linux Python 3.12: common/docker/pair/coordinator и node backup | 74 теста |
| `build/update-venv/bin/python -m unittest discover -s scripts -p test_node_backup.py` | 16 тестов |
| `build/telegram-python/bin/python -m unittest discover -s scripts/release -p test_schema_compatibility.py` | Реальный backend: создание 12, миграции 9/10/11 → 12, повторное открытие 12 и отказ на 13 |
| `openspec validate safe-signed-node-transition --strict` | Успешно |

Основной unittest runner использует существующий `build/update-venv`; его Python
3.15 не объявляется релизным runtime. Дополнительно изменённая область проверяется
на Python 3.12 в Linux QA host с закреплёнными update requirements. Полный набор
updater в минимальном QA host встречает четыре ограничения среды: три Android
fixture-теста требуют отсутствующий Git, один server bundle-тест требует исполнения
из временного каталога, который по умолчанию был noexec. Это не успешный Linux gate;
focused Linux-набор запускается с явным `--tmpfs /tmp:rw,exec`.

Codegraph доступен, но индекса репозитория нет; индекс не создавался. Связи и
инварианты проверялись по исходникам и тестам. Падений процесса C++ и оснований
для attach LLDB в этой проверке не было.

## Воспроизведение стенда

Подготовка и требования к Linux QA host описаны в [runbook](signed-transition.md).
Входы этой репетиции:

- Backend: `sha256:4339f8b44b076d8dcbea0cfde2532c0607dd8bd61fb561ec85380b1b713c4b9a`.
- Worker: `sha256:0e9232a9b70026003920559293cdf7bff91c2dfcdd0f3d87effdd21c1408fcfb`.
- Toolkit: `sha256:6ed58d14a197741f76a7f2d8108de52d3a185a1fef04f60b30483c987f7bab67`.
- Повторно используемая QA-цель: `sha256:e80ffcb7232f35705d8f365c9461959eb9779430b8892844f828823a8285dc2e`.

`scripts/update/test_pair_compose_flow.py` запускается внутри QA host с Docker
socket только у координатора, read-only checkout и отдельным Linux volume,
смонтированным по тому же абсолютному пути у Docker daemon и координатора.
Для пересборки QA-цели используются исходники, подготовленный builder и новый
QA Telegram key; повторное использование `--target-image` требует matching
`--telegram-key-file`. Эти параметры не предназначены для production.

Первый успешный полный прогон — `flow13`: локальный build 2026111804 с исходным
нестандартным tag остался неизменным, QA signed floor прошёл 1065 → 1066.
Подтверждены отклонение неверной подписи и изменённого рецепта без остановки,
прерывание между запусками пары, полное восстановление с переносом физических JAM
и изоляцией неисправного WAL, обе identity и реальные API-проверки после rollback.
Повторный переход дошёл до complete, включая свежий Telegram-вход, прежние сессии,
персональные ящики, прочитанность, UUE/crosspost receipts и TLS/gRPC-Web/CORS.
Возврат старого snapshot после admission отклонён с отдельным полным backup текущих
данных; посторонний сервис и процесс отдельного gateway не пересоздавались.
Это переход schema 12 → 12; миграции исторических схем проверены отдельно в таблице.

Финальные повторения `flow14` и `flow15` также завершились с exit 0. `flow15`
включает синхронизацию каталогов и дополнительные assertions: после свежих Telegram
входов число сессий выросло с двух до пяти; отказ snapshot rollback не изменил
ни одну проверяемую строку, а post-admission backup содержит то же полное состояние.
Проверены users/tokens/telegram_bindings/mailbox_bindings/read_status/operations/
uue_uploads/crosspost_groups с нормализацией только штатных generation aliases и
физических identities файлов. Время прочтения не исключалось: probe использует
`ReadArchiveMessage`, не меняющий историю. Оба файла sequence после завершения
остались на 1066. Сервисы и registry стендов остановлены в finally.

После этих прогонов итоговое ревью выявило риск смены владельца/прав BUILD identity
при атомарной записи. Сохранение её metadata исправлено в switch и rollback;
остальные приватные журналы по-прежнему создаются с 0600. Отдельная новая Linux
регрессия выполняет обе операции над файлом UID/GID 1000, режим 0640, и проверяет
реальное чтение JSON дочерним процессом под UID 1000. После этой правки повторены
полные updater suites на обоих Python и focused Linux suite (результаты в таблице).
Полный Docker-цикл повторно после этой узкой правки прав не запускался.

Фактически выполненные host-команды повторений:

```sh
python3 build/safe-signed-node-transition/run-linux.py flow13
python3 build/safe-signed-node-transition/run-linux.py flow14
python3 build/safe-signed-node-transition/run-linux.py flow15
```

Этот локальный helper читает приватный ресурсный descriptor. Эквивалент запуска
последнего прогона (повторять только с новым именем контейнера и новым каталогом):

```sh
qa_repo=/Users/yurik/Projects/ffido
qa_volume=ffido-signed-qa-20261119-a0a62587
qa_mount=/var/lib/docker/volumes/ffido-signed-qa-20261119-a0a62587/_data
qa_host=sha256:6ed58d14a197741f76a7f2d8108de52d3a185a1fef04f60b30483c987f7bab67
docker run --name "${qa_volume}-flow15" --platform linux/amd64 --network host \
  -e PYTHONDONTWRITEBYTECODE=1 -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${qa_repo}:${qa_repo}:ro" -v "${qa_volume}:${qa_mount}" -w "$qa_repo" \
  "$qa_host" "$qa_repo/scripts/update/test_pair_compose_flow.py" \
  --directory "$qa_mount/flow15" \
  --source-worker sha256:0e9232a9b70026003920559293cdf7bff91c2dfcdd0f3d87effdd21c1408fcfb \
  --admin /opt/ffido/bin/ffido-admin --envoy /usr/local/bin/envoy \
  --toolkit-image "$qa_host" \
  --target-image sha256:e80ffcb7232f35705d8f365c9461959eb9779430b8892844f828823a8285dc2e \
  --telegram-key-file "$qa_mount/flow1/fixture.private.json"
```

При этом QA-план проверяет доступные байты на каждом этапе. В первом preflight
стенда расчёт составлял 23 070 200 652 байта с резервом 2 GiB; при post-admission
backup, когда образы уже подготовлены, — 12 706 513 356 байт. Это размеры данного
стенда, включая QA toolkit, а не норматив для amster2.

Приватные журналы, ключи и полные bundles находятся под игнорируемым
`build/safe-signed-node-transition/` и в отдельном QA volume. Они не входят в Git.
Неудачные fixtures сохраняются для диагностики, а их сервисы останавливаются.
Успешный runner записывает публичный `result.json` без credentials.

## Условия будущего рабочего допуска

1. Выпустить и отдельно проверить настоящий подписанный релиз с schema max 12,
   Telegram и безопасным restore; QA-подпись и QA-образы для рабочего узла непригодны.
2. Повторно обследовать amster2 и зарегистрировать фактические image ID, BUILD,
   конфигурации и guards. Подготовить совместимый restore toolkit с передачей lock.
3. Обеспечить рассчитанное место для полного bundle и staging; прежние 14 GiB
   не заменяют расчёт по фактическим размерам. Автоочистка не выполняется.
4. Включить фактические gateway/TLS/ACME/renewal/cron/firewall и их runtime в профиль,
   согласовать общий maintenance lock с renewal и сохранить внешний trusted digest.
5. По отдельному разрешению сделать свежий stopped-node backup и репетицию его
   восстановления; только затем выполнять рабочий переход пары.
6. Отдельно принять новую пару и лишь после этого рассматривать снятие guards.
   При возможных новых записях старый snapshot не применять: сначала сохранить
   актуальные данные и принять отдельное решение о reconciliation.
