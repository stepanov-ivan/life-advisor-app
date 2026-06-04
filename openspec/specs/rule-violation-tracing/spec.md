## Purpose

Трейсинг нарушений правил питания от правила через день и приём до конкретного ингредиента с хранением в SwiftData.

## Requirements

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

### Requirement: Трейсинг цепочки нарушения
Система SHALL предоставлять drill-down от правила через день и приём до конкретного ингредиента с указанием structured presentation case, причины и величины отклонения. Пользовательское описание нарушения SHALL строиться вне доменного слоя и локализоваться на активном языке приложения.

#### Scenario: Раскрытие нарушения до ингредиента на английском языке
- **WHEN** effective language приложения английский и пользователь открывает нарушение правила на экране детали правила
- **THEN** система строит drill-down через stable rule ids и reason codes, а пользовательский explanation text отображается на английском языке через presentation layer

#### Scenario: Нарушение дня без конкретного ингредиента
- **WHEN** нарушение не привязано к конкретному ингредиенту
- **THEN** drill-down останавливается на уровне приёма или дня, а explanation text всё равно формируется через локализованный presentation layer

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
