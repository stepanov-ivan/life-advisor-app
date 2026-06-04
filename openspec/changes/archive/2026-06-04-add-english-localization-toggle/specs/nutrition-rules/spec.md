## MODIFIED Requirements

### Requirement: Каталог правил питания из JSON
Система SHALL загружать 16 правил питания ВОЗ/ФАО из `nutrition_rules.json` в bundle при запуске и предоставлять их в UI, сгруппированными по stable category ids. JSON-конфигурация SHALL содержать только language-agnostic rule data и SHALL NOT быть источником пользовательских `title` и `description`.

#### Scenario: Успешная загрузка правил без display copy
- **WHEN** приложение запускается и JSON корректен
- **THEN** RuleEngine загружает все правила по их stable ids, категориям и параметрам, а UI получает пользовательские названия и описания из localization layer, а не из JSON

#### Scenario: Некорректное правило в JSON
- **WHEN** правило имеет неизвестный `field`, неверный `type` или невалидный `window`
- **THEN** правило логируется и пропускается, остальные правила загружаются нормально

#### Scenario: Отсутствие JSON-файла
- **WHEN** `nutrition_rules.json` отсутствует в bundle
- **THEN** система показывает ошибку конфигурации и не показывает список правил

## ADDED Requirements

### Requirement: Presentation правил локализуется по stable rule ids
Система SHALL получать пользовательские названия, описания, категории и section titles правил через отдельный localization layer, привязанный к stable rule ids и category ids.

#### Scenario: Правило отображается на английском языке
- **WHEN** effective language приложения английский и UI показывает правило `who_protein`
- **THEN** название, описание и категория правила отображаются через английские ключи таблицы `Rules`, а не через поля модели правила

#### Scenario: Правило отображается на русском языке
- **WHEN** effective language приложения русский и UI показывает правило `who_processed_meat`
- **THEN** название, описание и категория правила отображаются через русские ключи таблицы `Rules`

### Requirement: Группировка правил не зависит от локализованного текста
Система SHALL группировать правила в UI по stable category ids или presentation section ids, а не по локализованным display strings.

#### Scenario: Список правил группируется по stable ids
- **WHEN** `RulesListView` строит секции правил
- **THEN** правила сначала группируются по stable category ids, а заголовки секций локализуются отдельно

#### Scenario: Аналитическая панель использует presentation grouping policy
- **WHEN** `DayAnalyticsPanel` строит секции правил для аналитики дня
- **THEN** grouping policy использует stable ids и может объединять категории через явные presentation rules без зависимости от локализованного текста
