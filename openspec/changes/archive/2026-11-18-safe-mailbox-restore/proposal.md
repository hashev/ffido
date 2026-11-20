# Proposal

## Why

Репетиция amster2 показала: миграция SQLite 11→12 сохраняет данные, но распаковка backup меняет inode JAM, и прежние привязки персональных ящиков блокируют запуск даже старого backend. Maintenance backup также пропускает таблицы перекодировки HPT и corrections manifest; нужен проверяемый путь восстановления до рабочего обновления Mini App.

## What Changes

- Добавить явную административную процедуру проверки и восстановления физических привязок ящиков по доверенному согласованному снимку; не ослаблять проверку обычного startup/provisioning.
- Проверять manifest, целостность JAM/SQLite, назначение ящиков и связанные generation-ссылки; выполнять изменения атомарно после dry-run с защитой от подмены и повторного применения.
- Добавить воспроизводимую подготовку полного остановленного backup и manifest зависимостей конфигурации, включая intab/outtab и corrections manifest.
- Сохранить логическую generation для UUE/crosspost receipt и FTN-дедупликации через проверенное runtime-сопоставление; подготовить отдельную rollback-пару backend/tosser v1.0.27 с restore-support.
- Собрать новые pinned backend/tosser и повторить репетицию в закрытом каталоге amster2 без сети, рабочих mounts, перезапуска рабочих служб, firewall и публикации.

## Capabilities

### New Capabilities

- `node-backup`: полный согласованный снимок данных и зависимостей узла, manifest и проверка полноты до восстановления.

### Modified Capabilities

- `point-mailboxes`: явное безопасное восстановление физических привязок после переноса проверенных JAM-файлов и согласованных метаданных.

## Impact

Backend: CLI ffido-admin, point_mail_admin/point_mailbox, metadata_store/sqlite_store, координационные locks, generation-зависимые данные и тесты. Операционные инструменты backup — в scripts/ с тестами; текущий удалённый manage.py используется как источник наблюдений, не перезаписывается в production. Документация docs/deployment/amster2-miniapp, README backend и docs/testing.md.

gRPC/protobuf и клиентский интерфейс не меняются; существующая схема 11 должна поддерживаться offline restore-инструментом для отката на отдельный v1.0.27 с restore-support без неявной миграции до 12. Секреты и базы остаются вне Git. Старые архивы не переписываются.
