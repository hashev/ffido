# Проверка FFIDO с базами `/Users/yurik/ftn`

Инструкция составлена по установленному пакету 12 октября 2026. Рабочая конфигурация HPT — `/Users/yurik/ftn/usr/etc/fido/config`, программа — `/Users/yurik/ftn/usr/bin/hpt`. Основной адрес — `2:5015/120.1`, AKA — `2:5015/120`, Sysop — `Yuriy Khashev`.

Историческая проверка до перехода на пароль HPT: рецепты создания TLS и конфигураций были проверены на искусственных JAM-файлах: успешны выдача двух токенов, native TLS RPC для обоих пользователей и двух конференций, scan установленным HPT через wrapper, валидация Envoy и штатная остановка backend. Журнал — локальный `build/ftn-guide-check.log`. Установка доверия в Keychain, ручное тестирование интерфейса и подключение рабочих баз оставлены вам; автоматически они не выполнялись.

| Конференция | Префикс файлов JAM |
|---|---|
| `nino.046.local` | `/Users/yurik/ftn/fido/msgbasedir/nino.046.local` |
| `zx.spectrum` | `/Users/yurik/ftn/fido/msgbasedir/zx.spectrum` |

У обеих баз имеются `.jhr`, `.jdt`, `.jdx`, `.jlr`. FFIDO использует первые три файла; персональная прочитанность приложения хранится в SQLite, не в `.jlr`. Настроенные Netmail и carbonArea не являются EchoArea и в этот каталог конференций не включаются.

**Сначала выполните шаги 1–9 на копиях.** Они позволяют читать настоящие сообщения и проверять отправку, HPT и несколько пользователей, не отправляя проверочные сообщения в действующую FidoNet. Подключение оригиналов описано отдельно в шаге 10.

## 1. Подготовить сборку

```sh
cd /Users/yurik/Projects/ffido
./build.sh build
FFIDO_TEST_HPT=/Users/yurik/ftn/usr/bin/hpt ./build.sh test
./build.sh check
```

После исправления отображения сообщений ожидается 191 backend-тест и 124 Flutter-теста. `FFIDO_TEST_HPT` включает интеграционный тест установленного HPT на искусственной базе; он не использует рабочие JAM. Если порты 8080, 8443 или 9443 заняты, освободите их либо согласованно поменяйте значения в следующих командах. Backend, gateway и клиент запускаются отдельными процессами.

## 2. Сделать согласованные копии

На время копирования остановите HPT, GoldED, FFIDO и другие программы, которые обращаются к этим базам; приостановите автоматический запуск `toss` через cron/launchd. Дождитесь завершения уже запущенных процессов. Простое копирование во время записи не создаёт согласованного снимка.

В терминале подготовки:

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
umask 077
mkdir -m 700 "$FFIDO_CHECK_DIR"
mkdir "$FFIDO_CHECK_DIR/jam" "$FFIDO_CHECK_DIR/backup" \
  "$FFIDO_CHECK_DIR/data" "$FFIDO_CHECK_DIR/certs"

python3 - <<'PY'
import os, shutil
from pathlib import Path
root = Path(os.environ['FFIDO_CHECK_DIR'])
source = Path('/Users/yurik/ftn/fido/msgbasedir')
for name in ('nino.046.local', 'zx.spectrum'):
    for extension in ('.jhr', '.jdt', '.jdx', '.jlr'):
        item = source / (name + extension)
        if item.is_symlink() or not item.is_file():
            raise SystemExit(f'Ожидался обычный файл: {item}')
        for directory in ('backup', 'jam'):
            destination = root / directory / item.name
            if destination.exists():
                raise SystemExit(f'Файл уже существует: {destination}')
            shutil.copy2(item, destination)
print('Созданы исходный backup и отдельные рабочие копии двух JAM-баз')
PY
```

Если каталог уже существует, первая `mkdir` выдаст ошибку: остановитесь и выберите новый каталог, а не повторяйте оставшиеся команды в старом. `backup` оставьте неизменяемой исходной копией, эксперименты проводите только в `jam`. После копирования обычное FTN-окружение можно запустить снова: оно не использует эти копии.

В каждом новом терминале дальше устанавливайте:

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
cd /Users/yurik/Projects/ffido
```

## 3. Создать TLS-сертификаты

Для localhost используйте отдельный тестовый CA. Следующие команды создают ключи только в приватном каталоге проверки. Не повторяйте их поверх уже выданных сертификатов.

```sh
export FFIDO_OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl
"$FFIDO_OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 30 \
  -subj '/CN=FFIDO local test CA' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -out "$FFIDO_CHECK_DIR/certs/ca.pem" \
  -keyout "$FFIDO_CHECK_DIR/certs/ca-key.pem"

"$FFIDO_OPENSSL" req -new -newkey rsa:2048 -nodes \
  -subj '/CN=localhost' \
  -out "$FFIDO_CHECK_DIR/certs/server.csr" \
  -keyout "$FFIDO_CHECK_DIR/certs/server-key.pem"

cat > "$FFIDO_CHECK_DIR/certs/extensions.cnf" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EOF

"$FFIDO_OPENSSL" x509 -req -days 30 \
  -in "$FFIDO_CHECK_DIR/certs/server.csr" \
  -CA "$FFIDO_CHECK_DIR/certs/ca.pem" \
  -CAkey "$FFIDO_CHECK_DIR/certs/ca-key.pem" -CAcreateserial \
  -extfile "$FFIDO_CHECK_DIR/certs/extensions.cnf" \
  -out "$FFIDO_CHECK_DIR/certs/server.pem"

"$FFIDO_OPENSSL" verify -CAfile "$FFIDO_CHECK_DIR/certs/ca.pem" \
  "$FFIDO_CHECK_DIR/certs/server.pem"
```

Последняя команда должна вывести `OK`. Для macOS-клиента и Chrome добавьте **публичный сертификат тестового CA** в пользовательское доверенное хранилище:

```sh
security add-trusted-cert -r trustRoot -p ssl \
  -k /Users/yurik/Library/Keychains/login.keychain-db \
  "$FFIDO_CHECK_DIR/certs/ca.pem"
```

macOS может запросить подтверждение. Затем перезапустите приложение и Chrome. Не устанавливайте приватный `ca-key.pem` в Keychain и не отключайте проверку TLS. Это локальная схема для данного Mac; для телефона нужны достижимое имя сервера, соответствующий SAN и доверенный на устройстве сертификат. `localhost` телефона не указывает на ваш Mac.

## 4. Создать конфигурацию FFIDO и отдельную конфигурацию HPT

Публичный backend-каталог задаётся двумя простыми EchoArea-строками. Не передавайте весь рабочий HPT config: в FFIDO нужен самостоятельный каталог, без Include/макросов/условий. Права пользователей берутся из отдельного эффективного HPT config; наличие эхи в каталоге само по себе не разрешает доступ.

```sh
python3 - <<'PY'
import json, os
from pathlib import Path
root = Path(os.environ['FFIDO_CHECK_DIR'])
areas = (
    'EchoArea nino.046.local jam/nino.046.local -b Jam -d "NINO.046.LOCAL"\n'
    'EchoArea zx.spectrum jam/zx.spectrum -b Jam -d "ZX.SPECTRUM"\n'
)
config = {
    'auth': {'hpt_config_path': './hpt-copy.cfg', 'session_key_path': './data/session.key'},
    'server': {
        'ip': '127.0.0.1', 'port': 8080, 'thread_num': 8,
        'rpc_timeout_ms': 5000, 'shutdown_timeout_ms': 10000,
        'tls_certificate': './certs/server.pem',
        'tls_private_key': './certs/server-key.pem',
    },
    'ftn': {
        'areacfg_path': './areas.cfg', 'jam_base_path': '.',
        'default_encoding': 'cp866', 'coordination_lock': './data/hpt.lock',
    },
    'database': {'metadata_path': './data/metadata.db'},
    'logging': {'level': 'info'},
}
for name, text in (('areas.cfg', areas), ('config.json', json.dumps(config, indent=2)+'\n')):
    with (root/name).open('x') as output:
        output.write(text)

# HPT использует только копии и отдельный outbound. Binkd к нему не подключён.
directories = {
    'Inbound': 'inbound', 'ProtInbound': 'protinbound',
    'Outbound': 'outbound', 'TempInbound': 'tmpin', 'TempOutbound': 'tmpout',
    'LogFileDir': 'logs', 'DupeHistoryDir': 'dupes', 'NodelistDir': 'nodelist',
}
hpt_root = root/'hpt'
hpt_root.mkdir()
text = 'Name FFIDO local check\nSysop Yuriy Khashev\nLocation Local\nAddress 2:5015/120.1\n'
for keyword, directory in directories.items():
    path = hpt_root/directory
    path.mkdir()
    text += f'{keyword} {path}\n'
text += f'MsgBaseDir {root}/jam\nEchoTossLog {hpt_root}/logs/toss.log\nImportLog {hpt_root}/logs/import.log\n'
text += 'Link TestUplink\nAKA 2:5015/120\nOurAKA 2:5015/120.1\nAllowEmptyPktPwd on\nEchoMailFlavour direct\n'
for keyword, name in (('NetmailArea', 'netmail'), ('BadArea', 'bad'), ('DupeArea', 'dupe')):
    text += f'{keyword} {name.upper()} {hpt_root}/{name} -b JAM\n'
# Только тестовые пароли, ввод не отображается. Файл остаётся локальным.
import getpass
for label, point in (('A', 100), ('B', 101)):
    password = getpass.getpass(f'Пароль тестового линка {label} (латиница/цифры, от 12 символов): ')
    if not password.isascii() or not password.isalnum() or len(password) < 12:
        raise SystemExit('Используйте тестовый пароль из латинских букв и цифр длиной от 12')
    text += f'Link TestClient{label}\nAKA 2:5015/120.{point}\nOurAKA 2:5015/120.1\nSessionPwd {password}\n'
for name in ('nino.046.local', 'zx.spectrum'):
    text += f'EchoArea {name} {root}/jam/{name} -b JAM -a 2:5015/120.1 2:5015/120 2:5015/120.100 2:5015/120.101\n'
with (root/'hpt-copy.cfg').open('x') as output:
    output.write(text)
(root/'hpt-copy.cfg').chmod(0o600)
print('FFIDO config и HPT config созданы; все пути HPT изолированы')
PY
```

`jam_base_path` здесь — каталог проверки; обе базы находятся внутри него. Кодировка CP866 взята как fallback: если сообщение содержит CHRS, parser использует CHRS. Источником FTN-адреса отправителя будет профиль пользователя, а не адрес из EchoArea.

## 5. Подготовить вход через HPT

На шаге 4 созданы два искусственных линка: A — `2:5015/120.100`, B —
`2:5015/120.101`. Используйте введённые там пароли; не сохраняйте их в Git,
скриншотах или журналах. FFIDO читает `hpt-copy.cfg` штатным парсером через
`ffido-hpt-auth`. Учётные записи создаются при первом успешном входе.
Для проверки телефона и ноутбука используйте **один и тот же линк A** на обоих.
Для проверки изоляции других пользователей используйте линк B с другим адресом.
Оба тестовых линка явно подписаны на эти две эхи. Для проверки ограничения
удалите один адрес из строки EchoArea либо задайте ReadOnly/WriteOnly и
перезапустите FFIDO. Ранее созданные копии HPT-конфига нужно дополнить
подписками тестовых линков: одного Link/AKA с паролем теперь недостаточно.
Собственный поинтовый AKA `2:5015/120.1` также допускает вход по паролю
своего босса `2:5015/120`, если OurAKA этого линка совпадает с `.1`. В этом
режиме доступны локальные JAM-эхи, чей эффективный AKA равен `.1`.
Явный реальный Link для `.1`, если он существует, имеет приоритет со своими ACL.

Соберите backend с `-DFFIDO_HUSKY_ROOT=/Users/yurik/ftn/usr`. Ключ сессий создаётся
автоматически в `data/session.key`; каталог должен существовать. Существующие
SQLite сначала копируйте при остановленном backend; неоднозначные профили с
одним адресом требуют разрешения конфликта до миграции.

## 6. Запустить backend и macOS-клиент

Терминал backend:

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
cd /Users/yurik/Projects/ffido
build/backend/apps/backend/fidoback "$FFIDO_CHECK_DIR/config.json"
```

Процесс должен продолжать работать и слушать localhost:8080. Если он завершился, сначала исправьте ошибку конфигурации/TLS/каталога. Обычный `curl https://localhost:8080` не является проверкой gRPC API.

Терминал клиента:

```sh
cd /Users/yurik/Projects/ffido/apps/frontend
flutter run -d macos
```

В форме «Подключение к FFIDO» укажите имя, `2:5015/120.100`, пароль линка A
и `https://localhost:8080`. Нажмите «Подключиться», затем «Открыть конференции».
При первом входе введённое имя сохраняется в серверном профиле. На нативном
клиенте сессия и пароль HPT сохраняются в защищённом хранилище. Пароль не
попадает в preferences и удаляется при явном выходе. Для production-проверок
используйте настоящее имя владельца адреса: первый Login создаёт его профиль.

## 7. Проверить браузер и второго пользователя

В новом терминале запустите Envoy. Проверенный executable уже есть в локальном build-каталоге; если он перемещён, подставьте действительный путь к установленному Envoy.

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
cd /Users/yurik/Projects/ffido
python3 tools/gateway/run.py \
  --envoy "$PWD/build/tools/envoy/1.39.3/bin/envoy" \
  --origin https://localhost:9443 \
  --certificate "$FFIDO_CHECK_DIR/certs/server.pem" \
  --private-key "$FFIDO_CHECK_DIR/certs/server-key.pem" \
  --backend-ca "$FFIDO_CHECK_DIR/certs/ca.pem" \
  --backend-port 8080 --port 8443 \
  --output "$FFIDO_CHECK_DIR/envoy.json"
```

Следующий терминал — HTTPS Web-клиент:

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
cd /Users/yurik/Projects/ffido/apps/frontend
flutter run -d chrome --web-hostname localhost --web-port 9443 \
  --web-tls-cert-path "$FFIDO_CHECK_DIR/certs/server.pem" \
  --web-tls-cert-key-path "$FFIDO_CHECK_DIR/certs/server-key.pem"
```

Страница открывается на `https://localhost:9443`; **адрес API в настройках браузерного клиента — `https://localhost:8443`**. Войдите с данными линка B (`2:5015/120.101`). Нативный клиент идёт на 8080 напрямую, браузер — на 8443 через gateway. Origin `https://127.0.0.1:9443` отличается от разрешённого `https://localhost:9443` и будет отклонён.

## 8. Ручная проверка функций

1. В каждом клиенте откройте обе конференции, проверьте русский текст, даты, автора, поиск, обновление и переходы между страницами. Если сообщение содержит CHRS, сравните текст с GoldED на **копиях**, не открывая те же копии одновременно с backend.
2. В macOS под A прочитайте несколько сообщений, добавьте закладки. Проверьте прочитанность, счётчики, историю и закладки. В браузере под B эти действия не должны появиться в его личных данных.
3. В копии `nino.046.local` отправьте сообщение с темой `FFIDO CHECK A 001`, русским текстом и ответом на существующее сообщение. Под B отправьте `FFIDO CHECK B 001`. Автор/адрес берутся из выданных профилей. Обновите оба клиента: каждый подтверждённый текст должен присутствовать ровно один раз; reply-цепочка должна указывать на выбранного родителя. Успешный результат означает «Сообщение сохранено локально».
4. Для конкуренции отправьте несколько сообщений из обоих клиентов почти одновременно, с различными темами. Проверьте отсутствие пропущенных и повторных подтверждённых сообщений.
5. Остановите backend через Ctrl+C. Клиент должен сообщать недоступность при запросах без подходящего кеша; подходящий кеш списка может временно отображаться. Запустите backend с тем же `config.json`: сообщения, личные данные и закладки должны сохраниться.
6. Только на копиях: через DevTools Chrome временно прервите сеть при отправке. Если интерфейс сообщает, что подтверждение не получено, восстановите сеть и нажмите «Повторить отправку» с прежним текстом. Не закрывайте форму и не перезагружайте клиент: ключ незавершённой операции хранится в этой форме. После повтора не должно появиться второго сообщения.
7. Проверьте вход и выход: «Выйти» очищает локальную сессию и кеш. Неверный пароль должен дать понятную ошибку. Для проверки независимости войдите с линком A на двух устройствах, выйдите на одном и продолжите на другом. Смена SessionPwd с перезапуском FFIDO отзывает обе старые сессии.

Команда отзыва (действительно прекращает доступ A):

```sh
cd /Users/yurik/Projects/ffido
build/backend/apps/backend/ffido-admin revoke-user \
  /Users/yurik/ffido-check/data/metadata.db 'ftn:2:5015/120.100'
```

## 9. Проверить HPT рядом с backend на копиях

Оставьте backend включённым. После отправки новых проверочных сообщений запустите **отдельную конфигурацию копий**:

```sh
export FFIDO_CHECK_DIR=/Users/yurik/ffido-check
cd /Users/yurik/Projects/ffido
python3 scripts/run_hpt.py --config "$FFIDO_CHECK_DIR/config.json" -- \
  /Users/yurik/ftn/usr/bin/hpt -c "$FFIDO_CHECK_DIR/hpt-copy.cfg" \
  scan -w -a nino.046.local
```

Повторите для `zx.spectrum`, если в неё отправляли проверочные сообщения. Здесь используются свои outbound и логи под `ffido-check/hpt`; рабочий Binkd их не отправляет. `-w` нужен из-за проверенной особенности high-water в установленной SMAPI; уже экспортированные сообщения исключаются по Sent. В outbound может попасть и старое сообщение копии без Sent: это остаётся в изолированном каталоге.

Пока HPT работает, обновляйте клиент или отправляйте сообщения. Backend может кратковременно ждать либо вернуть контролируемый deadline/недоступность. После окончания HPT запросы должны восстановиться. При неопределённом исходе отправки повторяйте её кнопкой с прежним содержимым. Повторите `scan -w`: уже экспортированные сообщения не должны экспортироваться вновь. Проверьте сообщения и цепочки после штатного перезапуска backend. Смотрите только `ffido-check/hpt/logs` и backend stderr.

Для отдельной проверки timeout wrapper без JAM-записи удержите координационную блокировку в терминале:

```sh
python3 - <<'PY'
import fcntl, time
with open('/Users/yurik/ffido-check/data/hpt.lock', 'a+b') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    print('Exclusive coordination lock удерживается 15 секунд', flush=True)
    time.sleep(15)
PY
```

Во втором терминале за эти 15 секунд:

```sh
cd /Users/yurik/Projects/ffido
python3 scripts/run_hpt.py --config /Users/yurik/ffido-check/config.json \
  --timeout 1 -- /Users/yurik/ftn/usr/bin/hpt \
  -c /Users/yurik/ffido-check/hpt-copy.cfg scan -w -a nino.046.local
echo $?
```

Ожидается `HPT coordination deadline exceeded; HPT was not started` и код 75. Не удаляйте lock-файл: его inode должен оставаться общим у всех процессов.

## 10. Подключить исходные рабочие базы

Переходите к этому шагу после успешной проверки копий. Здесь отправки уже попадут в рабочие конференции и после HPT scan могут уйти в FidoNet. Используйте обычные разрешённые правилами конференций сообщения.

Обнаруженный `/Users/yurik/ftn/usr/bin/toss` сейчас выполняет прямой `hpt -q toss scan afix`, затем `htick`, затем `hpt -q pack`. Его нельзя запускать одновременно с FFIDO в таком виде. Перед подключением оригиналов остановите автоматический toss и переведите **каждый** путь запуска HPT на общий wrapper, а `pack` вынесите в обслуживание при остановленном backend. Не запускайте GoldED и другие JAM-редакторы одновременно с FFIDO: проверенное сосуществование относится к HPT под wrapper.

При остановленных программах сохраните согласованный backup рабочих JAM. Создайте **отдельный** приватный каталог, например `/Users/yurik/ffido-live`, с `certs`, `data`, `config.json`, `areas.cfg` и локальным ключом сессий. Для локальной проверки можно скопировать сертификат сервера, его ключ и публичный CA из `ffido-check/certs`; приватный CA-ключ серверу не нужен. Не копируйте тестовую SQLite: её generation/message keys относятся к копиям баз.

В `ffido-live/config.json` используйте тот же формат, что в шаге 4, но измените:

```json
"ftn": {
  "areacfg_path": "./areas.cfg",
  "jam_base_path": "/Users/yurik/ftn/fido/msgbasedir",
  "default_encoding": "cp866",
  "coordination_lock": "./data/hpt.lock"
}
```

В `ffido-live/areas.cfg`:

```text
EchoArea nino.046.local /Users/yurik/ftn/fido/msgbasedir/nino.046.local -b Jam -d "NINO.046.LOCAL"
EchoArea zx.spectrum /Users/yurik/ftn/fido/msgbasedir/zx.spectrum -b Jam -d "ZX.SPECTRUM"
```

Укажите рабочий `auth.hpt_config_path`, отдельный `auth.session_key_path` и используйте данные существующего реального линка HPT. Сначала завершите тестовый backend; затем запустите рабочий с `ffido-live/config.json`. В клиенте введите имя, FTN-адрес и пароль реального линка. Не переносите тестовые адреса или пароли в рабочую конфигурацию. Envoy может использовать прежний доверенный сертификат для localhost; при изменении сертификата/CA обновите gateway и доверие клиента.

Рабочий HPT запускается только так:

```sh
cd /Users/yurik/Projects/ffido
python3 scripts/run_hpt.py --config /Users/yurik/ffido-live/config.json -- \
  /Users/yurik/ftn/usr/bin/hpt -c /Users/yurik/ftn/usr/etc/fido/config \
  toss scan -w afix
```

Или экспорт одной конференции:

```sh
python3 scripts/run_hpt.py --config /Users/yurik/ffido-live/config.json -- \
  /Users/yurik/ftn/usr/bin/hpt -c /Users/yurik/ftn/usr/etc/fido/config \
  scan -w -a nino.046.local
```

Wrapper использует именно live-конфигурацию, как и backend. Ссылаться на `ffido-check/config.json` для рабочего HPT нельзя: это другой lock-файл. Запускайте backend и HPT от пользователя `yurik` с доступом к одному локальному файлу блокировки.

Если `toss` продолжает запускать HTick, проверьте, не касается ли он этих JAM; такие обращения также должны находиться под той же координационной блокировкой. Изменения cron/launchd/toss здесь не выполнены автоматически. Простое оборачивание всего старого `toss` не делает его `pack` совместимым с работающим backend.

`pack`, purge, замена и восстановление файлов требуют остановки backend и согласованного backup JAM **вместе с SQLite**. Не откатывайте только JAM или только SQLite после подтверждённых отправок. При запуске backend миграция старой SQLite сохраняет старую прочитанность в `read_status_legacy_backup`, начинает новую прочитанность заново и сохраняет закладки/историю. Подключать старую SQLite нужно отдельным осознанным шагом с backup; эта инструкция использует новую.

## Если что-то не работает

| Симптом | Что проверить |
|---|---|
| TLS / HandshakeException | CA доверен пользователю; SAN включает localhost; срок не истёк; клиент/Chrome перезапущен |
| UNAUTHENTICATED | Проверьте FTN-адрес и пароль линка HPT; после истечения/отзыва сессии войдите снова |
| Web CORS / 403 | Страница на `https://localhost:9443`, API на 8443, точно тот же Origin в Envoy |
| Backend завершился при запуске | Файлы TLS, JSON, корень JAM, наличие всех `.jhr/.jdt/.jdx`, права, ошибки bind |
| RESOURCE_EXHAUSTED | Слишком большая страница/сообщение; уменьшите страницу, проверьте лимиты в backend README |
| DEADLINE_EXCEEDED во время HPT | Дождитесь окончания HPT, повторите чтение; отправку повторяйте прежней операцией |
| Quarantine / повреждение базы | Остановите запись, сохраните JAM и SQLite, изучите диагностику; не удаляйте journal и не правьте header вручную |
| Отправка видна в JAM, но не в сети | Успех FFIDO означает сохранение локально; проверьте wrapper HPT scan, Sent, outbound и дальнейший Binkd |

После тестов остановите Web, Envoy и backend через Ctrl+C, очистите буфер обмена (`pbcopy < /dev/null`). Если тестовый CA больше не нужен, уберите выданное ему доверие:

```sh
security remove-trusted-cert /Users/yurik/ffido-check/certs/ca.pem
```

Это повлияет и на live-подключение, если оно использует сертификат того же CA. Не удаляйте приватный каталог проверки до остановки процессов и сохранения нужных журналов. Здесь не выполнялись реальные отправки, изменения рабочих JAM или автоматическая перенастройка FTN-пакета.

## Проверка через интернет

Для VPS используйте DNS-имя и сертификат публично доверенного CA. В FFIDO
настройте listen IP и TLS, откройте выбранный порт gRPC. Если используется
прокси, включите HTTP/2 gRPC до backend. Телефон Android и ноутбук подключаются
к одному HTTPS-адресу FFIDO, без доступа к конфигурационным файлам HPT.
В рабочем `config.json` задайте `auth.hpt_config_path` на рабочий HPT config,
а `auth.session_key_path` — на отдельный локальный файл ключа. При копировании
примеров не используйте изолированную тестовую конфигурацию вместо рабочей.

## Вход с собственным AKA реального поинта

Для `/Users/yurik/ftn/usr/etc/fido/config` собственный адрес —
`2:5015/120.1`, явный линк босса — `2:5015/120`. Используйте имя,
собственный адрес `.1`, существующий пароль соединения с боссом
(SessionPwd, иначе Password) и `https://localhost:8080`.
Серверный конфиг подготовлен отдельно: `/Users/yurik/ffido-live/config.json`.
Вход не меняет HPT config и не превращает отправителя в босса.
После изменения пароля/AKA/OurAKA перезапускайте FFIDO.

При активном сервере вызывайте `/Users/yurik/ftn/usr/bin/toss`: его HPT/HTick
проходят через общий wrapper. Автоматический pack из этой команды вынесен.
Для pack сначала остановите live FFIDO, затем используйте
`/Users/yurik/ftn/usr/bin/ffido-pack`. Команда удерживает instance-lock FFIDO
на всё обслуживание и не запускает HPT, если сервер работает.
`ffido-pack --check` проверяет возможность обслуживания без запуска HPT.
Прямой HPT или JAM-редакторы в обход этого порядка одновременно с FFIDO
не запускайте.

## Проверить кодировку исходящих публикаций

В `/Users/yurik/ffido-live/config.json` используется `ftn.default_encoding=cp866`.
Это одновременно резервная кодировка чтения и кодировка новых сообщений из
клиента. Unicode транспорта превращается в CP866 на сервере для тела, темы
и имён; JAM получает `CHRS: CP866 2`. CHRS существующих входящих писем может
быть другим, включая UTF-8; новый ответ всё равно использует cp866.
Непредставимые символы отклоняются без изменения JAM, черновик остаётся у клиента.

Для проверки без отправки в рабочие эхи используйте синтетические тесты:

```sh
ctest --test-dir build/backend -R 'GrpcTest.Cp866' --output-on-failure
FFIDO_TEST_HPT=/Users/yurik/ftn/usr/bin/hpt ctest --test-dir build/backend -R ProcessTest.HptRoundTripAndConcurrentExportWithSharedWrapper --output-on-failure
```

Первая команда проверяет байты `.jdt` и текстовых подполей `.jhr`, CHRS,
ответ UTF-8-родителю и отказ для символов вне CP866. Вторая дополнительно
проверяет реальный HPT на временных файлах; рабочие конфигурации/базы туда
не передавайте. Уже существующие JAM не перекодируются.

При публикации сервер заменяет **все** заглавные кириллические `Н` (U+041D)
на латинские `H` (U+0048): `НН H н` → `HH H н`. Это действует для текста,
цитат и пересылок, темы, имени автора из профиля и имени получателя, включая
получателя ответа из исходного письма. Строчная `н` и остальные символы
сохраняются. Замена выполняется перед кодированием в JAM; в CP866 латинская
`H` записывается байтом `0x48`. Профиль, исходный черновик и старые сообщения
не переписываются. Повтор операции сверяется по исходному запросу: изменение
`Н` на `H` с прежним ключом отправки считается конфликтом.

## Чтение, цитаты и пересылка

Нижние «Предыдущее»/«Следующее» обходят текущий список или цепочку в показанном
порядке, дозагружая страницы. На границах кнопка отключена. Возврат «К списку»
сохраняет позицию. При сетевой ошибке остаётся текущее письмо; «Повторить»
повторяет переход. При устаревшем ID обновите список. Прочитанность и история
обновляются обычным запросом полного сообщения.

«Ответить в эху» — публичный ответ автору в той же эхе. В редактор сразу
вставляется цитата с `> `: сократите её и напишите ответ между строками.
Отправляется видимое тело, без скрытой вставки оригинала. Обычный текст,
нечётные и чётные уровни цитирования имеют разные цвета при чтении и наборе.
Ориентир — [QUOTE1/QUOTE2 GoldED+](https://raw.githubusercontent.com/golded-plus/golded-plus/master/cfgs/config/gedcolor.cfg).
Маркеры `AB>`, `>>`, `> AB>` поддерживаются, `a > b` не считается цитатой.
Оформление не меняет текст, переносы или CP866 сервера.

«Переслать» позволяет выбрать другую разрешённую для публикации эху,
включая post-only. Чтения исходной эхи достаточно, писать в неё не нужно.
Проверьте поиск и «Загрузить ещё», отмену, изменение назначения без потери
правок, отказ после отзыва прав и повтор с прежним ключом при потере ответа.
В реальных эхах тестовые сообщения не публикуйте: используйте fake transport
или временную базу. Пересылка — новое письмо, без reply-ссылки в чужую эху.

Матрица визуальной проверки действий:

| Среда | Проверка |
| --- | --- |
| macOS, мышь | Активная иконка различима, появляется hover и курсор указателя; disabled не кликается |
| macOS, клавиатура | Tab показывает фокус; Enter/Space выполняют действие; поле оставляет текстовый курсор |
| macOS, русский ввод | Цитата меняет цвет при правке маркера, выделение/копирование/Undo сохраняют текст |
| Android, узкий экран | Нижняя панель не перекрывает письмо, редактор прокручивается при клавиатуре |
| Android, касание | Все действия доступны без hover; выбор эхи и отмена сохраняют черновик |
| Компонентные тесты | Светлая/тёмная палитры: иконки ≥3:1, текст и цитаты ≥4.5:1 |

Для изолированного визуального осмотра можно запустить клиент на fake transport:

```sh
cd apps/frontend
flutter run -d macos --release -t test/manual/reader_smoke.dart
```

Этот target показывает только искусственные письма и эху `test.target`, не
подключается к FTN-серверу и не публикует сообщения. После проверки соберите
обычное приложение без `-t`: `flutter build macos --release` (или
`flutter build apk --release` для Android). Рабочие артефакты и тестовый target
используют одну стандартную папку сборки, поэтому последний target определяет
содержимое исполняемого файла.

## Приватные области владельца

Сначала обновите сервер и владельческий клиент вместе. В отдельном временном окружении
задайте `auth.owner_addresses: ["2:1/2.1"]`: адрес должен уже входить через пароль HPT.
Ни номер поинта, ни OurAKA, ни имя пользователя не дают эту роль автоматически.
Оператор проверяет отдельный непубличный пароль владельца; общедоступный пароль не изолирует личную почту.
Для отключения доступа уберите адрес и перезапустите сервер. Старая сессия теряет доступ,
но персональные отметки и письма сохраняются и вновь доступны после явного возврата роли.

В двух клиентах владельца проверьте группы «Эхи», «Личная почта», «Локальные», «Служебные».
Откройте netmail, нажмите «Ответить лично»: имя и полный адрес получателя обязательны,
в ответе адрес берётся из оригинального письма. Подтверждение означает «сохранено локально»,
а не доставку. В LocalArea доступен «Локальный ответ»; Bad/Dupe/Robots — только чтение.
Приватные области не являются источником/назначением эхопересылки. Squish/MSG показывают
«не поддерживается / статистика неизвестна», открыть или записать их нельзя.

Затем войдите двумя обычными поинтами: приватных названий не должно быть в списках,
поиске, истории и закладках. Прямые RPC с известными ID должны вернуть PERMISSION_DENIED.
Проверьте смену владельца на обычного поинта в том же клиенте: приватные данные исчезают;
при отказе сервера или сетевой ошибке приватный каталог не восстанавливается из кеша.

Автоматизированная изолированная проверка из корня репозитория:

```sh
cmake -S . -B build/backend -DCMAKE_BUILD_TYPE=Debug
cmake --build build/backend --parallel 4
FFIDO_TEST_HPT=/Users/yurik/ftn/usr/bin/hpt build/backend/apps/backend/fidoback_tests --gtest_filter='PrivateAreasTest.*:ProcessTest.PrivateOwner*'
```

Тест создаёт временные JAM, TLS и конфиги. Путь к HPT — только исполняемый файл;
его рабочий конфиг и реальные базы не используются. Запуск pack/scan внутри теста проходит
через `scripts/run_hpt.py`, включая полный lifecycle открытия/закрытия SMAPI.
Для операторской проверки на **временной копии** окружения используйте:

```sh
python3 scripts/run_hpt.py --config /tmp/ffido-fixture/config.json --timeout 10 -- /path/to/hpt -c /tmp/ffido-fixture/hpt.cfg pack
python3 scripts/run_hpt.py --config /tmp/ffido-fixture/config.json --timeout 10 -- /path/to/hpt -c /tmp/ffido-fixture/hpt.cfg scan -w -a RU.TEST
```

`config.json` и `hpt.cfg` здесь должны описывать одни временные базы и общий coordination_lock.
Перед выполнением замените пути на реально подготовленный временный каталог. Netmail должен
иметь Local/TypeNet/Private и OADDRESS/DADDRESS, без AREA/SEEN-BY/PATH и эхового Origin;
LocalArea не должна появиться в outbound. RPC не запускает HPT, роботов, toss или сетевую отправку.
Не добавляйте автоматический pack в рабочий toss; операторский pack требует согласованной блокировки.

Временный HPT-конфиг для проверки pack должен включать явный маршрут к синтетическому адресату,
например `Route normal 2:1/3.4 2:1/3.4`. Код возврата 0 без настроенного Route не подтверждает экспорт;
проверяйте MsgID в исходящем пакете. Этот пример не является маршрутом для рабочей сети.

Для сквозной проверки настоящего Flutter ApiClient (не FakeTransport) против временного
C++-сервера после сборки бэкенда:

```sh
cd apps/frontend
FFIDO_E2E_BACKEND=/Users/yurik/Projects/ffido/build/backend/apps/backend/fidoback flutter test --no-pub test/api/private_areas_e2e_test.dart
```

Тест создаёт собственные CA/сертификат с serverAuth во временном каталоге и доверяет CA
только внутри тестового канала. Он не отключает TLS-проверку и не устанавливает сертификаты
в систему. Без переменной окружения этот отдельный deployment-тест пропускается; обычные
unit/widget-тесты продолжают выполняться. Сервер и временные файлы удаляются при завершении.

Проверка атрибутов JAM (включая настоящий HPT pack/scan на временных базах):

```sh
FFIDO_TEST_HPT=/path/to/hpt ctest --test-dir build/backend -R 'JamAttributes|PrivateAreasTest' --output-on-failure
```

SMAPI-проверка сверяет все 29 битов независимо от FFIDO и проверяет Netmail/ответ,
Echo и LocalArea до/после HPT. Отдельный тест подтверждает, что чтение старых писем
с прежними неправильными битами не меняет JAM. Эти тесты не используют рабочие базы.


### Аудит исторических JAM-атрибутов

Перед включением персональной почты остановите backend и почтовый цикл, сохраните
согласованную резервную копию SQLite (включая незавершённый WAL, если он есть), JAM
и конфигов. Аудит выполняйте на согласованном checkpointed снимке SQLite без непустого WAL:

```sh
ffido-admin audit-jam /backup/metadata.db /backup/jam/netmail /backup/hpt.lock
```

Файл coordination lock должен уже существовать. Активный backend с тем же instance lock
и непустой WAL запрещают аудит. Команда открывает SQLite immutable/read-only,
не создаёт WAL/SHM, не выполняет миграции, recovery или запись JAM. Отчёт содержит
числа флагов, наличие точного committed FFIDO-append и pending/quarantine, без тела письма.
Совпадение старых и новых битов остаётся неоднозначным; отчёт не является разрешением
на массовую правку. Адресная миграция требует отдельного решения после анализа backup.


### Создание персональных баз (временное окружение)

Новый раздел `point_mail` по умолчанию выключен. Для временного теста назначьте
`enabled: true`, `ingress_areas: ["IN"]`, `egress_area: "OUT"` и `points` с полями
`address` и относительным `jam_base`, например `2:1/2.1` → `points/p1`.
Временный HPT должен иметь собственный Address `2:1/2`, явные Link/OurAKA поинтов,
JAM NetmailArea IN с dupeCheck off, отдельную OUT, KeepTrsMail on, PackNetMailOnScan off,
точные Route nopack управляемым поинтам перед общим внешним маршрутом.

```sh
ffido-admin provision-mailboxes /temporary/config.json
```

Команда требует остановленного backend и общей эксклюзивной coordination lease.
Вход/RPC не создают баз. Повтор команды проверяет сохранённые идентичности всех трёх
файлов; symlink/hardlink, существующая непривязанная или подменённая база отклоняются.
SQLite schema 6 добавляет привязки. После сбоя до фиксации привязки оставшиеся файлы
не присваиваются автоматически: требуется разбор и сохранение оператором.
Включение runtime требует созданных bindings и успешного preflight полного транспортного цикла.

### Полный временный цикл персональной почты

Проверяемая конфигурация: собственный Address `2:1/2`; два FFIDO Link-поинта `.1/.2`
и обычный mailer-поинт `.3`, у каждого OurAKA `2:1/2`. Личные JAM лежат под отдельным
корнем, например `points/p1`, `points/p2`, и не перечисляются в HPT. Отдельные
NetmailArea IN/OUT должны быть JAM с нодовым AKA. На IN нужен `-dupeCheck off`;
это допускается только вместе с адресным dedup полного цикла. Глобальные параметры:

```text
KeepTrsMail on
PackNetMailOnScan off
Route nopack 2:1/2.1 2:1/2.2
Route normal noroute *
```

Конкретный внешний Route зависит от инфраструктуры. Общий nopack для всех поинтов
не подходит: `.3` должен продолжать получать пакеты. KeepTrsMail не заменяет захват,
а nopack не защищает от Crash — распределитель фиксирует настоящий Locked до pack.

Раздел FFIDO для временного стенда:

```json
"point_mail": {
  "enabled": true,
  "ingress_areas": ["IN"],
  "egress_area": "OUT",
  "points": [
    {"address": "2:1/2.1", "jam_base": "points/p1"},
    {"address": "2:1/2.2", "jam_base": "points/p2"}
  ]
}
```

Транспортные IN/OUT и остальные объявленные JAM предварительно создаются средствами
HPT на временном стенде. Привязки поинтов создаются явно. Полностью воспроизводимая
фикстура создаёт все каталоги/базы и синтетический Type-2+ PKT без мейлера и сети:

```sh
FFIDO_TEST_HPT=/path/to/hpt ctest --test-dir build/backend -R 'PointMailboxProvision|PointMailboxCycle|HptRoutingFixtures' --output-on-failure
```

Рабочий цикл по расписанию оператора (только после отдельного согласования live-конфига):

```sh
python3 scripts/run_hpt.py --config /temporary/config.json --cycle --admin /path/to/ffido-admin --hpt /path/to/hpt
```

`--scan` добавляет эховый scan после pack. `--timeout` ограничивает ожидание lease и каждую
дочернюю стадию; timeout/cancel/signal завершают её группу процессов. При перезапуске
сначала восстанавливаются незавершённые append/claim/bind/unlock. HPT не запускается при
неподтверждённом восстановлении; сохраняются источник, пользовательская копия и MsgID.
Поступление в приложение зависит от частоты этого цикла и обычного обмена мейлера.

Диагностика под той же exclusive lease:

```sh
python3 scripts/run_hpt.py --config /temporary/config.json --status --admin /path/to/ffido-admin
```

Отчёт показывает состояние экспорта, pending append/outbox и ссылки на незавершённые
переходы/карантин, без тел и паролей. Quarantine сохраняет исходную запись Locked;
после проверки её блокировки можно обрабатывать остальные письма. При неизвестном
состоянии claim запрещается весь pack. Коллизии нельзя устранять удалением второй
версии наугад. Неподдерживаемая кодировка при валидном заголовке также изолируется.

Если pack прерван, export_state 1/2 считается неопределённым. До продолжения оператор
сверяет MsgID, Sent и имеющиеся PKT/FLO с согласованным backup, учитывая возможность
частичной упаковки. Только когда транспорт приведён в проверенное согласованное состояние:

```sh
python3 scripts/run_hpt.py --config /temporary/config.json --ack-export --admin /path/to/ffido-admin
```

Эта явная команда записывает reconciliation в SQLite и снимает только блокировку цикла.
Она не меняет JAM-флаги, не исправляет пакеты и не отправляет письма. Без предварительной
сверки её применять нельзя: исход HPT между записью PKT и Sent принципиально неоднозначен.
Журнал сверяется read-only запросом `SELECT * FROM mail_export_log ORDER BY id` на снимке.

Для backup остановите новые отправки и цикл, завершите/зафиксируйте pending и сохраните
вместе персональные JAM, транспорт/ingress, SQLite с WAL, конфиги и состояние outbound.
При rollback сначала остановите цикл и доступ/новые отправки, сохраните данные и разберите
незавершённые переходы. Выключение point_mail не удаляет bindings, базы или отметки.
Не снимайте Locked и не возвращайте традиционную доставку управляемым поинтам автоматически.
Возврат маршрутов, dupeCheck и старого binary/SQLite — отдельное согласованное действие.
Обычному mailer-поинту никаких персональных баз FFIDO не назначают.

Клиентский режим: две отдельные сессии одного адреса; общие read/history/bookmarks/last-opened.
Ревизии назначает сервер. Продолжение загружает anchor-страницу с фактическим offset и
сохраняет навигацию в обе стороны; удалённый anchor не отмечает другое письмо.
Resume/обновление/возврат к списку запрашивают сервер, приватный кеш не подставляется.
Черновики, положение прокрутки, push и подтверждение внешней доставки не входят в режим.


Сквозной сценарий двух клиентов настоящего Flutter ApiClient с временными backend/HPT:

```sh
cd apps/frontend
FFIDO_E2E_BACKEND=/absolute/path/build/backend/apps/backend/fidoback FFIDO_TEST_HPT=/path/to/hpt flutter test --no-pub test/api/point_mailboxes_e2e_test.dart
```

Сценарий создаёт собственную тестовую CA, сертификат с serverAuth, синтетические JAM/PKT,
две сессии P1, P2, владельца и обычного поинта. Мейлер и FTN-сеть не запускаются.
Проверяются inbox/outbox, CP866/Н → H, REPLY, pack/repeat, серверная позиция за первой
страницей, разделение read/bookmarks/history, известные чужие ID, отзыв bindings и пароля.


Перед outbox handoff пользовательская копия сверяется с полным подтверждённым append-планом,
MsgID, назначенным адресом автора и durable direction. Подмена тела/атрибутов после подтверждения
переводит outbox в состояние 3 и запрещает экспорт. В status остаются user/operation,
conference/message_number и MsgID для сверки; оригинальный план сохранён в SQLite, текущие
файлы не переписываются. `--ack-export` не снимает такой карантин: он относится только
к неопределённости завершения HPT. Исправление исходных данных/карантина — отдельное
адресное действие оператора после backup, без автоматического нового append.

В личном ящике показано время последнего успешного получения списка с сервера.
Это актуальность клиентской страницы, а не подтверждение обмена мейлера или доставки адресату.

### Проверка «Отметить всё прочитанным»

Используйте только временную JAM EchoArea с несколькими страницами и двумя
пользователями; повторите вход первого пользователя во втором клиенте.
В меню открытой эхи выберите «Отметить всё прочитанным», отмените и убедитесь,
что счётчик не меняется. Повторите с подтверждением: отметка охватывает всю эху,
включая другие страницы/цепочку. Обновите список на втором клиенте: общий профиль
видит ту же прочитанность. Другой пользователь не должен получить эти отметки.
После нового письма счётчик снова растёт; безопасный повтор прежней операции
не включает новое поступление. Сравните JAM/JLR до и после: они не меняются.
История и последнее открытое письмо также не перемещаются.

При потере ответа в ещё открытом экране используйте «Проверить/повторить», не
создавая новую операцию. Новое явное действие после закрытия/открытия экрана
получает новый снимок. На старом сервере ожидается сообщение о неподдерживаемой
операции. В Netmail/Local/служебных областях пункт отсутствует, прямой RPC запрещён.
Перед реальным обновлением backend нужен backup SQLite: новая схема 8 сохраняет
receipt массовых операций. Не понижайте user_version вручную при rollback.
