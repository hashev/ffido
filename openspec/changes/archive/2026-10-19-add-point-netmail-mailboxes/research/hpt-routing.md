# Проверка HPT на временных базах, 2026-10-17

## Методика и границы

Фактически выполнены эксперименты с `/Users/yurik/ftn/usr/bin/hpt` (hpt/mac 1.9 2024-03-02).
SHA-256 бинарника: `44285bedcc804022628473b1f66c88e19ba57ac3fa73bf060af95e8bcf07287e`.
Конфиги, JAM, PKT, outbound и логи созданы в отдельных `ffido-point-routing-*` каталогах системного temp.
Рабочие config/toss/JAM не читались для заполнения фикстур и не изменялись. HPT запускался только с явным `-c` через `scripts/run_hpt.py` и временный coordination_lock. Mailer не запускался, сеть не использовалась.

Синтетический Type-2+ пакет: от линка 2:1/9 к боссу 2:1/2; пять личных сообщений
от 2:1/9.7 к 2:1/2.1, 2:1/2.2, самому боссу, ненастроенному 2:1/2.9 и транзитному 2:1/7.1.
Имя обоих поинтов одинаковое `Same Name`, адреса различаются через INTL/TOPT/FMPT.
У сообщений отдельные MSGID и ASCII-маркеры, CHRS CP866 2. Индексы, заголовки и подполя JAM
разобраны независимым Python/struct-кодом; в outbound проверены маркеры, а не только exit status.

## Результаты

Колонки: активные записи общей ingress до/после pack, число пакованных маркеров P1/P2.

| Конфигурация | toss/pack exit | ingress | P1/P2 в outbound |
| --- | --- | --- | --- |
| normal | 0/0 | 5 → 1 | 1/1 |
| keep | 0/0 | 5 → 5 | 1/1 |
| nopack | 0/0 | 5 → 5 | 0/0 |
| foreign-aka | 78/78 | 0 → 0 | 0/0 |
| nopack-priority | 0/0 | 5 → 5 | 1/1 |
| locked | 0/0 | 5 → 5 | 0/0 |
| dedup-del | 0/0 | 4 → 1 | 1/0 |
| dedup-off | 0/0 | 5 → 1 | 1/1 |

- `normal`: обычный Route normal noroute *, без KeepTrsMail. Все пять сообщений сначала находятся
  в первой NetmailArea, после pack остаётся только письмо боссу. Четыре транзитных письма экспортированы.
- `keep`: KeepTrsMail on сохраняет пять записей, но P1/P2 всё равно отправляются в outbound.
- `nopack`: точный Route nopack для .1/.2 до общего маршрута удерживает их; ненастроенный .9 и транзит экспортируются, босс не экспортируется. Повтор pack не добавил копий.
- В `nopack` повтор исходного пакета с HPT dupeCheck del сохранил 5 записей. Постинг через HPT
  от 2:1/2.1 к 2:1/9.7 и два pack дали ровно один исходящий маркер, оригинал сохранился с OADDRESS
  поинта, DADDRESS адресата и Sent. Это проверяет маршрут/хранение, не durable очередь FFIDO.
- `foreign-aka`: NetmailArea -a 2:1/2.1/.2 без этих адресов в Address отклоняется с кодом 78:
  `2:1/2.1 not found as address`. Имена областей сами по себе не распределяют почту.
- `nopack-priority`: после toss на временных JAM-записях .1/.2 выставлен настоящий JAM Crash
  0x00000100 (входящий пакетный Crash HPT ранее сбрасывает). Оба письма упакованы вопреки nopack.
- `locked`: тот же эксперимент с настоящим JAM Locked 0x40000000 перед pack: .1/.2 не экспортированы,
  посторонний транзит экспортируется. Это лабораторная правка закрытых временных файлов,
  не готовая crash-safe реализация обновления заголовков.
- `dedup-del` / `dedup-off`: при одинаковом MSGID двух писем разным поинтам HPT dupeCheck del
  оставил 4 из 5 сообщений, письмо P2 исчезло до распределения. С off сохранены все пять.
  Следовательно, для общей ingress нужен управляемый address-aware dedup до pack, а не доверие
  одному MSGID или глобальному HPT dupeCheck del. Это меняет операторский pipeline при включении функции.

## Обнаруженная несовместимость wire-флагов

Установленный SMAPI и upstream api_jam.h совпадают:

| JAM | SMAPI / формат | Текущий FFIDO |
| --- | --- | --- |
| TypeLocal | 0x00800000 | 0x00400000 |
| TypeEcho | 0x01000000 | 0x00800000 |
| TypeNet | 0x02000000 | 0x01000000 |
| Locked | 0x40000000 | 0x04000000 |

Сдвиги затрагивают также часть флагов выше FileAttach. Текущие raw-тесты повторяют константы FFIDO,
а экспорт HPT по настроенной NetmailArea не доказывает правильность типа исходной JAM-записи:
SMAPI при переписывании нормализует её тип. Нужны сверка всей таблицы и независимый SMAPI oracle,
проверка до и после HPT. Код проекта в ходе исследования не исправлялся; массовая миграция старых
писем не обоснована, потому что внешние и созданные FFIDO записи могут иметь одинаковые биты.

## Воспроизведение

Scratch-скрипты текущей сессии: `/tmp/ffido-point-routing-probe.py`,
`/tmp/ffido-point-locked-probe.py`, `/tmp/ffido-point-dedup-probe.py`.
Это исследовательские временные материалы, не установленный инструмент FFIDO.
Для постоянных regression-тестов в apply перенести описанные фикстуры в тестовую инфраструктуру,
не включать абсолютные temp-пути или бинарные рабочие базы в репозиторий.

Шаблон конфигурации **только временного эксперимента**: Address 2:1/2; три Link с OurAKA
2:1/2 для 2:1/9, 2:1/2.1 и .2; Inbound/ProtInbound/Outbound/TempInbound/TempOutbound/LogFileDir/
DupeHistoryDir/NodelistDir/MsgBaseDir направлены в temp. NetmailArea INGRESS, BadArea BAD,
DupeArea DUPE используют отдельные JAM. Варианты добавляют KeepTrsMail on и Route nopack
2:1/2.1 2:1/2.2 перед Route normal noroute *. Команды:

```sh
python3 scripts/run_hpt.py --config "$fixture/wrapper.json" --timeout 10 -- /path/to/hpt -c "$fixture/hpt.cfg" toss
python3 scripts/run_hpt.py --config "$fixture/wrapper.json" --timeout 10 -- /path/to/hpt -c "$fixture/hpt.cfg" pack
```

Временный wrapper.json содержит только свой ftn.coordination_lock. Этот пример не готовый
production-конфиг: в частности, standalone pack не заменяет распределитель и журнал восстановления.
Crash/потери питания FFIDO, копирование в ящики, две сессии и UI в этом исследовании не проверялись:
они являются критериями реализации, а не результатами проведённого эксперимента.

## Первичные источники

- [Руководство HPT](https://raw.githubusercontent.com/huskyproject/hpt/master/doc/hpt.texi): KeepTrsMail, Route, Several Netmail Areas.
- [SMAPI api_jam.h](https://raw.githubusercontent.com/huskyproject/smapi/master/smapi/api_jam.h): wire-флаги JAM.
- Фактически установленные исходники: `hpt/src/toss.c` processNMMsg, `hpt/src/scan.c` scanNMArea/packMsg,
  `fidoconf/src/line.c` areaOptions, `smapi/src/api_jam.c` под `/Users/yurik/ftn/fidoip-ng/husky/husky/`.
  Документация upstream проверена; результаты поведения относятся к указанному локальному бинарнику.
