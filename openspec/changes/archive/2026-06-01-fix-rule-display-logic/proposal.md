## Why

Сейчас правила питания оцениваются только после 3+ дней с приёмами за неделю — пользователь не видит ни статистики, ни нарушений при первых приёмах. Подсветки (highCalorieFlag, border) неинформативны: не показывают, какое правило нарушено и какой продукт в этом виноват. Нужна трехуровневая система подсветки (продукт → приём → день) с контрибьюшн-анализом, работающая с первого приёма.

## What Changes

- **BREAKING**: Удалить `minDaysData` из JSON-конфига и модели `RuleDefinition` — правила оцениваются при ≥1 structured-приёме
- **Трехуровневая подсветка нарушений**:
  - **Продукт**: при нарушении правила за день — контрибьюшн-анализ (вклад >30% от метрики → продукт подсвечен). Для presence-правил — флаг категории. Правило не нарушено → продукты не подсвечиваются
  - **Приём пищи**: инлайн-список нарушенных правил с названием и причиной прямо в карточке `MealSlotCard`
  - **День**: аналитическая панель с 3 группами правил (макронутриенты / ограничения / качество + режим) вместо кнопки «Совет дня»
- **Убрать**: `highCalorieFlag` (поле и всю логику), красный/жёлтый border у `MealSlotCard`, восклицательный знак в `MealEventEditorView`
- **Оставить**: цветовой фон карточки приёма по статусу (structured/pendingEstimation/skipped/...)
- **Убрать**: кнопку «Совет дня» и связанную LLM-логику (`requestDailyAdvice`, `DailyAdvice`)

## Capabilities

### New Capabilities

- `meal-rule-feedback`: инлайн-отображение нарушенных правил в карточке приёма пищи с названием, причиной и контрибьюшн-анализом продукта
- `day-analytics-panel`: статическая аналитическая панель за день с группировкой правил по 3 категориям

### Modified Capabilities

- `nutrition-rules`: удаление `minDaysData` и требования «Минимальный порог данных»; правила оцениваются при ≥1 приёме; добавление контрибьюшн-анализа на уровне продукта
- `rule-violation-tracing`: `RuleViolation` хранит `contributionMap` (продукт → доля вклада в метрику); нарушения доступны из контекста приёма без drill-down
- `rule-analytics`: сводная панель выводится не только на экране правил, но и на дашборде в разрезе дня

## Impact

- `RuleEngine.swift` — удаление minDaysData, добавление `contributionMap(for:rule:date:)`, изменение порога оценки, удаление `hasMinData()`
- `RuleDefinition.swift` — удаление поля `minDaysData`
- `RuleViolation.swift` — добавление `contributionJSON: String?` для карты вклада продуктов
- `nutrition_rules.json` — удаление `minDaysData` из всех правил
- `MealSlotCard.swift` — удаление highCalorieFlag и border, замена на инлайн-список нарушений
- `MealEventEditorView` — удаление `isItemViolating` и восклицательного знака
- `EstimateItem.swift` — удаление `highCalorieFlag`
- `EstimationRuntime.swift` — удаление `applyHighCalorieFlags`
- `DashboardView.swift` — удаление кнопки «Совет дня», замена на `DayAnalyticsPanel`
- `RulesListView.swift` — упрощение, удаление избыточных индикаторов
- `AnalyticsView.swift` — возможная интеграция дневной панели
