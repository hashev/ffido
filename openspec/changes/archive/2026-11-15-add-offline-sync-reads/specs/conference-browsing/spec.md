# Spec Delta

## ADDED Requirements

### Requirement: Поколение доступной JAM-базы
Conference.generation и ListMessagesResponse.generation SHALL равняться части текущего message_id до `#`, без нового определения поколения. Ответы ListMessages, GetThread и GetArchiveThread SHALL заполнять generation, включая пустые успешные страницы. Conference SHALL выдавать generation только при известной статистике.

#### Scenario: Получение поколения
- **WHEN** получены конференция с statistics_known=true и списки ListMessages, GetThread, GetArchiveThread той же базы
- **THEN** их generation совпадает с префиксом текущих message_id

#### Scenario: Статистика неизвестна
- **WHEN** Conference.statistics_known=false, в том числе при omit_statistics
- **THEN** Conference.generation пуст
- **AND** omit_statistics не открывает JAM-базу, как и ранее

#### Scenario: Замена базы с прежней статистикой
- **WHEN** поколение в message_id изменилось после замены файлов, а total_count и last_message_date остались прежними
- **THEN** новые ответы ListMessages, GetThread и GetArchiveThread содержат новое generation
- **AND** Conference.generation также меняется там, где оно заполняется

#### Scenario: Независимые страницы
- **WHEN** клиент последовательно запрашивает страницы ListMessages
- **THEN** каждый успешный ответ содержит поколение базы, открытой для этого запроса; межзапросный снимок не гарантируется

#### Scenario: Защита при замене физических файлов
- **WHEN** физические JAM-файлы заменены после запуска сервера
- **THEN** прежняя защита от чтения подменённых файлов сохраняет отказ до штатного переоткрытия базы
- **AND** после переоткрытия успешные ответы отражают новое поколение, как и message_id

### Requirement: Последовательная выборка по JAM-номеру
Только ListMessages SHALL принимать NUMBER_ASCENDING. Этот режим SHALL требовать пустые query и anchor_message_id. Непустой after_message_id SHALL требовать NUMBER_ASCENDING и page.offset=0. Номера SHALL упорядочиваться по возрастанию независимо от дат; состояние чтения SHALL не изменяться.

#### Scenario: Страница без курсора
- **WHEN** sort=NUMBER_ASCENDING и after_message_id пуст
- **THEN** возвращаются живые письма по возрастанию JAM-номера с page.offset и page.limit по прежним правилам пагинации

#### Scenario: Позднее письмо со старой датой
- **WHEN** после известного номера добавлено письмо с более старой датой и запрошено продолжение
- **THEN** письмо включено по большему JAM-номеру независимо от даты

#### Scenario: Несовместимые параметры
- **WHEN** NUMBER_ASCENDING задан с query или anchor_message_id, либо after_message_id задан с другой сортировкой или ненулевым offset
- **THEN** возвращается INVALID_ARGUMENT без изменения состояния

#### Scenario: Другие RPC
- **WHEN** FindMessage либо SearchArchiveMessages получает NUMBER_ASCENDING
- **THEN** возвращается INVALID_ARGUMENT, как для неподдерживаемой сортировки

### Requirement: Проверяемый курсор номера
Курсор SHALL иметь формат generation#number. Для текущего поколения допустим любой номер от base_msg_num до последнего слота индекса включительно, в том числе удалённый. Продолжение SHALL возвращать только живые номера строго больше курсора без чтения или сортировки заголовков на нём и ниже.

#### Scenario: Продолжение и удалённый курсор
- **WHEN** курсор текущего поколения лежит в диапазоне, в том числе на удалённом номере
- **THEN** возвращается до page.limit следующих живых писем, actual_offset=0, total равен числу живых писем всей базы, has_more указывает наличие следующей страницы
- **AND** заголовки с номерами не выше курсора не читаются и не сортируются

#### Scenario: Последний номер
- **WHEN** курсор равен последнему слоту индекса
- **THEN** messages пуст, actual_offset=0, has_more=false, total остаётся числом живых писем базы

#### Scenario: Некорректный формат
- **WHEN** after_message_id не является корректным generation#number, включая некорректную числовую часть
- **THEN** возвращается INVALID_ARGUMENT

#### Scenario: Чужое поколение или номер вне диапазона
- **WHEN** корректный по формату курсор имеет другое поколение либо номер ниже base_msg_num или выше последнего слота, включая базу без слотов
- **THEN** возвращается FAILED_PRECONDITION, а не NOT_FOUND, без изменения состояния

#### Scenario: Отсутствие персональных побочных эффектов
- **WHEN** выполнены страницы NUMBER_ASCENDING с курсором, без курсора или отклонённый запрос
- **THEN** read_status, история и reading_positions, включая ревизии, совпадают с состоянием до запроса
