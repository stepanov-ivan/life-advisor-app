## MODIFIED Requirements

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
