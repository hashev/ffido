# Spec Delta

## ADDED Requirements

### Requirement: Полные сырые подполя при архивном чтении
ReadArchiveMessage SHALL при include_subfields=true, body_offset=0 и несвёрнутом письме возвращать все сырые JAM-подполя в subfields и исходное второе слово attributes2. Порядок, повторы, low_id, high_id, пустые значения и байты SHALL сохраняться в пределах существующего лимита 64 КиБ на весь блок подполей сообщения.

#### Scenario: Все виды подполей
- **WHEN** запрошены подполя письма с LoID 4, 5, 2000, SEEN-BY 2001, PATH 2002, TZUTC 2004, PID 7 и другими, включая неизвестные
- **THEN** возвращены все подполя в сохранённом порядке с исходными high_id, повторениями, пустыми значениями и произвольными bytes
- **AND** attributes2 совпадает с исходным словом и MessageTechnicalData.attributes2, включая старший бит

#### Scenario: Граница блока
- **WHEN** блок подполей достигает допустимого размера 64 КиБ либо превышает его
- **THEN** допустимый блок возвращается целиком; превышение отклоняется существующей проверкой JAM без усечения и повышения лимита

#### Scenario: Не первая часть тела
- **WHEN** include_subfields=true и body_offset не равен 0
- **THEN** возвращается INVALID_ARGUMENT

#### Scenario: Прежнее архивное чтение
- **WHEN** include_subfields=false либо не задан
- **THEN** прежние поля ответа и поведение чтения сохраняются, subfields пуст, attributes2=0

### Requirement: Сырые поля сохраняют персональное сворачивание
ReadArchiveMessage SHALL не выдавать subfields и attributes2 для письма, свёрнутого персональными фильтрами при reveal=false. Явное раскрытие SHALL выдавать поля только при соблюдении остальных условий include_subfields и существующей авторизации.

#### Scenario: Свёрнутое письмо
- **WHEN** include_subfields=true, body_offset=0, письмо свёрнуто и reveal=false
- **THEN** subfields пуст, attributes2=0, тело скрыто по прежним правилам

#### Scenario: Явное раскрытие
- **WHEN** для того же доступного письма include_subfields=true, body_offset=0 и reveal=true
- **THEN** возвращаются исходные подполя и attributes2 вместе с запрошенным блоком тела

#### Scenario: Чтение без побочных эффектов
- **WHEN** выполняются include_subfields-чтения обычного, свёрнутого, явно раскрытого письма или отклонённый запрос
- **THEN** read_status, история и reading_positions с ревизиями остаются прежними, JAM и персональные фильтры не изменяются
