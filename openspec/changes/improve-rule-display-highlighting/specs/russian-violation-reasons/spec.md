## ADDED Requirements

### Requirement: Генерация русских описаний нарушений
Система SHALL предоставлять метод `violationDescription(for:)` в `RuleEngine`, который генерирует человекочитаемое описание нарушения на русском языке на основе `RuleViolation.reasonCode` и данных правила.

#### Scenario: Превышение верхней границы
- **WHEN** нарушение имеет `reasonCode = "exceeds_upper"`, правило `who_free_sugar` с `upper: 0.10`, текущее значение 14,2%
- **THEN** метод возвращает «Превышение: 14,2% при норме ≤10%»

#### Scenario: Недостаток нижней границы
- **WHEN** нарушение имеет `reasonCode = "below_lower"`, правило `who_fiber` с `lower: 25`, текущее значение 18 г
- **THEN** метод возвращает «Недостаточно: 18 г при норме ≥25 г»

#### Scenario: Приближение к верхней границе
- **WHEN** нарушение имеет `reasonCode = "approaching_upper"`, правило `who_saturated_fat` с `upper: 0.10`, текущее значение 9,2%
- **THEN** метод возвращает «Близко к пределу: 9,2% при норме ≤10%»

#### Scenario: Приближение к нижней границе
- **WHEN** нарушение имеет `reasonCode = "approaching_lower"`, правило `who_protein` с `lower: 0.10`, текущее значение 10,5%
- **THEN** метод возвращает «Близко к минимуму: 10,5% при норме ≥10%»

#### Scenario: Отсутствие категории
- **WHEN** нарушение имеет `reasonCode = "category_missing"`, правило `who_whole_grain` с категорией `whole_grain`
- **THEN** метод возвращает «Не хватает продуктов категории "цельные злаки"»

#### Scenario: Присутствие нежелательной категории
- **WHEN** нарушение имеет `reasonCode = "unwanted_category_present"`, правило `who_processed_meat`
- **THEN** метод возвращает «Присутствуют нежелательные продукты: обработанное мясо»

#### Scenario: Много пропусков
- **WHEN** нарушение имеет `reasonCode = "excessive_skips"`, 5 пропусков за неделю
- **THEN** метод возвращает «Много пропусков: 5 за неделю»

#### Scenario: Есть пропуски
- **WHEN** нарушение имеет `reasonCode = "some_skips"`, 2 пропуска за неделю
- **THEN** метод возвращает «Есть пропуски приёмов: 2 за неделю»

### Requirement: Использование русских описаний в UI
Система SHALL использовать `violationDescription(for:)` во всех местах, где сейчас отображается `reasonCode`.

#### Scenario: Карточка приёма
- **WHEN** `MealSlotCard` показывает нарушение правила `who_free_sugar`
- **THEN** отображается результат `violationDescription(for:)` вместо `violation.reasonCode`

#### Scenario: Детальный экран правила
- **WHEN** `RuleDetailView` показывает список нарушений
- **THEN** строка «Причина: ...» использует результат `violationDescription(for:)` вместо `violation.reasonCode`

### Requirement: Сохранение reasonCode в модели
Система SHALL сохранять оригинальный `reasonCode` в модели `RuleViolation` без изменений. Русское описание SHALL генерироваться на лету и использоваться только в UI-слое.

#### Scenario: Обратная совместимость тестов
- **WHEN** существующие тесты проверяют `violation.reasonCode`
- **THEN** тесты продолжают проходить, значение `reasonCode` не изменилось
