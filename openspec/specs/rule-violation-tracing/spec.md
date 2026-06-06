## Purpose

Трейсинг нарушений правил питания от правила через день и приём до конкретного ингредиента через persisted contribution entities (RuleContributionSnapshot, RuleContributionItem). Explainability отделён от факта нарушения.

## Requirements

### Requirement: Модель нарушения правила
Система SHALL хранить нарушение правила в `RuleViolation` как факт нарушения с полями `ruleId`, `date`, `zone`, `magnitude`, `reasonCode` и опциональными связями на `MealEvent?` и `EstimateItem?`, но SHALL NOT использовать нарушение как универсальную explainability-модель для всех зон правила.

#### Scenario: Создание нарушения при выходе за норму
- **WHEN** дневное правило оценивается и значение выходит за пределы нормы
- **THEN** создаётся `RuleViolation` с зоной `violation`, величиной отклонения и связью с днём

#### Scenario: Правило в норме
- **WHEN** дневное правило оценивается и значение остаётся в допустимых границах
- **THEN** `RuleViolation` не создаётся, а explainability хранится только в `RuleContributionSnapshot`

#### Scenario: Нарушение дня без привязки к продукту
- **WHEN** нарушение относится ко дню в целом и не имеет конкретного culprit-продукта
- **THEN** `mealEvent` и `estimateItem` могут быть `nil`

### Requirement: `RuleViolation` не хранит contribution JSON
Система SHALL NOT хранить карту вклада продуктов внутри `RuleViolation`. Источником truth для дневного product contribution SHALL быть `RuleContributionSnapshot` и `RuleContributionItem`.

#### Scenario: Нарушение с продуктами-вкладчиками
- **WHEN** нарушение связано с продуктами, внёсшими вклад в метрику
- **THEN** эти связи читаются через contribution items, а не через JSON-строку внутри `RuleViolation`

#### Scenario: Нарушение без продуктов
- **WHEN** у нарушения нет конкретного продуктового источника
- **THEN** violation хранится без contribution payload и UI не пытается читать JSON

### Requirement: Нарушения доступны из контекста приёма через contribution entities
Система SHALL предоставлять список нарушений, связанных с конкретным `MealEvent`, через contribution items, связанные одновременно с нарушенным правилом, днём и данным `MealEvent`.

#### Scenario: Запрос нарушений для приёма
- **WHEN** у нарушенного правила есть contribution items, связанные с продуктами данного приёма
- **THEN** `violationsForMeal(_:)` возвращает это нарушение

#### Scenario: Приём без нарушений
- **WHEN** ни одно нарушенное правило не имеет contribution items для данного `MealEvent`
- **THEN** `violationsForMeal(_:)` возвращает пустой массив

### Requirement: Трейсинг explainability отделён от факта нарушения
Система SHALL использовать `RuleContributionSnapshot` и `RuleContributionItem` как дневной explainability read model для breakdown правила и списка затронутых правил под продуктом, независимо от того, находится правило в зоне `normal` или `violation`.

#### Scenario: Breakdown правила в норме
- **WHEN** правило находится в зоне `normal`
- **THEN** UI читает product contribution из snapshot/items без создания `RuleViolation`

#### Scenario: Breakdown нарушенного правила
- **WHEN** правило находится в зоне `violation`
- **THEN** UI может одновременно использовать `RuleViolation` как факт нарушения и snapshot/items как explainability-слой

### Requirement: Хранение нарушений в пределах недели
Система SHALL хранить `RuleViolation` только в пределах текущей недели (пн–вс).

#### Scenario: Сброс в понедельник
- **WHEN** наступает понедельник
- **THEN** система удаляет все `RuleViolation` за предыдущую неделю

### Requirement: Инкрементальный пересчёт нарушений
Система SHALL пересчитывать нарушения инкрементально: полный слепок при первом входе на экран правил или начале новой недели, затем только дельта для нового/изменённого дня.

#### Scenario: Первичный слепок
- **WHEN** пользователь впервые открывает экран правил в текущей неделе
- **THEN** RuleEngine вычисляет полный набор `RuleViolation` за все доступные дни недели

#### Scenario: Дельта нового дня
- **WHEN** пользователь сохраняет новый приём пищи
- **THEN** RuleEngine пересчитывает нарушения только для этого дня и обновляет `RuleViolation`

#### Scenario: Редактирование старого приёма
- **WHEN** пользователь редактирует приём за предыдущий день недели
- **THEN** RuleEngine пересчитывает нарушения только для этого дня

### Requirement: Пропуск skipped-дней в агрегации
Система SHALL исключать skipped-приёмы из оценки всех правил кроме `who_meal_regularity`. Если все приёмы за день skipped — день пропускается в агрегации.

#### Scenario: Все приёмы skipped
- **WHEN** все приёмы за день имеют статус `skipped`
- **THEN** день не учитывается в агрегации для всех правил, minDaysData уменьшается

#### Scenario: Часть приёмов skipped
- **WHEN** часть приёмов за день skipped, а часть structured
- **THEN** skipped-приёмы исключаются из агрегатов, structured-приёмы участвуют в оценке

### Requirement: ParseFailed-приёмы исключены
Система SHALL исключать приёмы со статусом `parseFailed` из оценки полностью.

#### Scenario: Приём с parseFailed
- **WHEN** приём имеет статус `parseFailed`
- **THEN** приём не участвует в агрегации ни для одного правила

### Requirement: Presentation нарушений отделено от `RuleEngine`
Система SHALL преобразовывать `RuleViolation` и связанные данные правила в typed presentation model до локализации пользовательского explanation text.

#### Scenario: Range-нарушение преобразуется в presentation model
- **WHEN** нарушение имеет `reasonCode = "exceeds_upper"` и связано с range-правилом
- **THEN** presentation layer получает typed case для range deviation с данными о правиле, текущем значении и пороге вместо готовой пользовательской строки

#### Scenario: Presence-нарушение преобразуется в presentation model
- **WHEN** нарушение имеет `reasonCode = "category_missing"`
- **THEN** presentation layer получает typed case с stable category id вместо заранее собранного текста на конкретном языке
