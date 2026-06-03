## ADDED Requirements

### Requirement: Карта вклада продуктов в нарушение
Система SHALL хранить в `RuleViolation` JSON-строку `contributionJSON` с картой вклада продуктов в метрику правила: `[{ "itemId": "...", "name": "...", "percent": 45.7 }]`. Поле может быть `nil` для нарушений без привязки к конкретным продуктам (например, пропуск приёма).

#### Scenario: Нарушение с контрибьюшн-картой
- **WHEN** правило `saturated_fat` нарушено за день, а продукт «Сливочное масло» даёт 52% насыщенных жиров
- **THEN** `RuleViolation.contributionJSON` содержит запись с `itemId`, `name: "Сливочное масло"`, `percent: 52.0`

#### Scenario: Нарушение без продуктов
- **WHEN** правило `meal_regularity` нарушено из-за пропуска приёмов
- **THEN** `RuleViolation.contributionJSON = nil`

### Requirement: Нарушения доступны из контекста приёма
Система SHALL предоставлять список `RuleViolation`, связанных с конкретным `MealEvent`, через метод `RuleEngine.violationsForMeal(_:)`. Метод анализирует `contributionJSON` всех нарушений за день: если любой `itemId` из JSON принадлежит `meal.estimateItems` — нарушение включается в результат. Если `contributionJSON` отсутствует или пуст, но `violation.mealEvent == meal` — нарушение также включается (обратная совместимость для правил без контрибьюшн-анализа).

#### Scenario: Запрос нарушений для приёма — найдено через contributionJSON
- **WHEN** `contributionJSON` нарушения `saturated_fat` содержит `itemId` продукта из приёма
- **THEN** `violationsForMeal` возвращает это нарушение

#### Scenario: Запрос нарушений для приёма — прямое совпадение mealEvent
- **WHEN** нарушение `meal_regularity` имеет `contributionJSON = nil`, но `mealEvent` ссылается на данный приём
- **THEN** `violationsForMeal` возвращает это нарушение

#### Scenario: Приём без нарушений
- **WHEN** ни одно нарушение дня не ссылается на продукты данного приёма ни через `contributionJSON`, ни через `mealEvent`
- **THEN** `violationsForMeal` возвращает пустой массив

## MODIFIED Requirements

### Requirement: Модель нарушения правила
Система SHALL хранить каждое нарушение правила в SwiftData-сущности `RuleViolation` с полями: `ruleId`, `date`, `zone`, `magnitude`, `reasonCode`, `contributionJSON` (опционально), и связями `@Relationship` на `MealEvent?` и `EstimateItem?`.

#### Scenario: Создание нарушения с вкладом
- **WHEN** правило оценивается, значение выходит за пределы нормы, и контрибьюшн-анализ находит продукты с вкладом >30%
- **THEN** создаётся `RuleViolation` с зоной, величиной отклонения, `contributionJSON` с топ-3 продуктами, и ссылками на приём и ингредиент

#### Scenario: Создание нарушения без вклада
- **WHEN** правило оценивается и значение выходит за пределы нормы, но контрибьюшн-анализ не находит продуктов с вкладом >30%
- **THEN** создаётся `RuleViolation` с `contributionJSON = nil`, зоной и величиной отклонения

#### Scenario: Нарушение без привязки к ингредиенту
- **WHEN** нарушение относится ко дню в целом (например, пропуск приёма)
- **THEN** `mealEvent` и `estimateItem` могут быть `nil`, `contributionJSON = nil`

#### Scenario: Каскадное удаление
- **WHEN** `MealEvent` удаляется из базы
- **THEN** связанные `RuleViolation` удаляются автоматически через `@Relationship` delete cascade
