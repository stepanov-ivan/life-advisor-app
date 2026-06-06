## ADDED Requirements

### Requirement: Persisted snapshot дневного состояния правила
Система SHALL сохранять для каждого поддерживаемого дневного правила отдельный `RuleContributionSnapshot` за выбранный день как persisted read model, независимый от `RuleViolation`.

#### Scenario: Создание snapshot для правила в норме
- **WHEN** дневное правило успешно оценивается и находится в зоне `normal`
- **THEN** система сохраняет `RuleContributionSnapshot` с `ruleId`, `date`, `zone`, текущим значением метрики и нормой

#### Scenario: Создание snapshot для нарушенного правила
- **WHEN** дневное правило успешно оценивается и находится в зоне `violation`
- **THEN** система сохраняет `RuleContributionSnapshot` с теми же summary-полями и ссылкой на связанные вклады продуктов

#### Scenario: Правило без данных
- **WHEN** за день нет данных для оценки правила
- **THEN** система сохраняет snapshot с зоной `no_data` без продуктового списка либо не показывает его в `DayAnalyticsPanel` согласно policy отображения

### Requirement: Persisted item-level contribution records
Система SHALL хранить вклад каждого продукта в виде отдельных `RuleContributionItem`, связанных с `RuleContributionSnapshot`, `MealEvent` и `EstimateItem`.

#### Scenario: Вклад продукта в gram-based правило
- **WHEN** продукт вносит вклад в дневную граммовую метрику правила
- **THEN** система сохраняет `RuleContributionItem` с absolute contribution, percent contribution, display name и порядком продукта в рационе дня

#### Scenario: Вклад продукта в presence-правило
- **WHEN** продукт попадает в релевантную категорию presence-правила
- **THEN** система сохраняет `RuleContributionItem` с абсолютной массой категории и её долей в категориальной базе дня

#### Scenario: Прямая связь с приёмом и продуктом
- **WHEN** contribution item сохраняется для продукта конкретного приёма
- **THEN** item содержит ссылку и на `MealEvent`, и на `EstimateItem`

### Requirement: Snapshot пересчитывается вместе с дневной оценкой правил
Система SHALL пересчитывать и обновлять `RuleContributionSnapshot` и связанные items в том же цикле, что и дневную оценку правил.

#### Scenario: Сохранение нового приёма
- **WHEN** пользователь сохраняет или переоценивает приём за выбранный день
- **THEN** система пересчитывает snapshots и contribution items для поддерживаемых дневных правил этого дня

#### Scenario: Редактирование существующего дня
- **WHEN** пользователь меняет структуру или состав продукта в уже существующем дне
- **THEN** система удаляет устаревшие snapshots/items этого дня и создаёт новые

### Requirement: `contributionJSON` исключается из explainability-модели
Система SHALL использовать `RuleContributionSnapshot` и `RuleContributionItem` как единственный источник truth для product contribution explainability и SHALL NOT сохранять либо читать `RuleViolation.contributionJSON`.

#### Scenario: UI читает breakdown правила
- **WHEN** `DayAnalyticsPanel` запрашивает breakdown правила
- **THEN** данные читаются из snapshot/items, а не из JSON-строки в нарушении

#### Scenario: Подсветка продукта в карточке приёма
- **WHEN** `MealSlotCard` определяет список правил для конкретного продукта
- **THEN** карточка использует связанные contribution items, а не парсинг `contributionJSON`
