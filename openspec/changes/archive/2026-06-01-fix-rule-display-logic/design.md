## Context

Сейчас `RuleEngine` требует минимум 3 дня с structured-приёмами в пределах недели для оценки правил (`minDaysData`). Это означает, что новый пользователь или пользователь с нерегулярным трекингом не видит обратной связи по правилам. Подсветки в UI (`highCalorieFlag`, border) либо неинформативны, либо не привязаны к конкретным правилам. Кнопка «Совет дня» вызывает LLM, но не работает и не даёт ценности.

Технологии: SwiftUI, SwiftData (SQLite), `RuleEngine` как `@Observable` сервис.

## Goals / Non-Goals

**Goals:**
- Правила оцениваются при ≥1 structured-приёме (дневные — за день, недельные — за неделю)
- При нарушении правила определяются продукты с наибольшим вкладом (>30%) — подсвечиваются в карточке приёма
- Карточка приёма показывает список нарушенных правил с причиной
- На дашборде появляется статическая аналитическая панель с тремя группами правил
- Удалены: `minDaysData`, `highCalorieFlag`, border карточки, кнопка «Совет дня»

**Non-Goals:**
- Изменение самих порогов правил (lower/upper) или warningRatio
- Изменение логики оценки `range`, `presence`, `countSkipped`
- Персистентность аналитики за прошлые периоды (только текущая неделя)
- Изменение JSON-схемы `nutrition_rules.json` кроме удаления `minDaysData`

## Decisions

### 1. Алгоритм контрибьюшн-анализа

**Решение**: Для каждого range-правила вычисляем долю продукта в нутриенте (не в проценте!), сортируем по убыванию, берём топ-3 с долей >30%.

**Абсолютные метрики** (sodiumMg, fiberGrams, fruitVegGrams, redMeatGrams):
```
contribution(item) = itemValue / dailyTotal × 100%
```

**Процентные метрики** (fatPercent, proteinPercent, carbsPercent, saturatedFatPercent, sugarPercent, energyBalancePercent):
```
contribution(item) = itemNutrient / totalNutrient × 100%
```
Где `itemNutrient` — граммы конкретного нутриента в продукте (fats, proteins, carbs, saturatedFats, sugar), `totalNutrient` — сумма по всем продуктам за день. Для `energyBalancePercent` — `itemCalories / totalCalories × 100%`.

Пример: дневной total 50g жира. Масло даёт 20g → contribution = 40% (подсвечено). Грудка даёт 3g → contribution = 6% (не подсвечено).

**Presence-правила** (`ultra_processed`, `red_meat`, `legume_nut`): продукт целевой категории → 100%.
**Inverse presence** (`water`): продукт не-water → 100%.

**Альтернатива (отвергнута)**: Дельта-вклад через собственную жирность продукта (`itemFats × 9 / itemCalories`). Проблема: продукт с 1g жира на 5 ккал (90%) подсветился бы, хотя его вклад в дневной жир ничтожен.

**Альтернатива (отвергнута)**: Контрибьюшн относительно порога правила. Проблема: сложнее для понимания пользователем.

### 2. Хранение contributionMap

**Решение**: Добавить `contributionJSON: String?` в `RuleViolation`. Формат:
```json
[
  {"itemId": "UUID", "name": "Пирожное", "percent": 45.7},
  {"itemId": "UUID", "name": "Чай с сахаром", "percent": 28.3}
]
```

Только продукты с долей >30%, топ-3.

**Альтернатива (отвергнута)**: `@Relationship` на множество `EstimateItem`. Проблема: SwiftData не поддерживает нативные many-to-many с атрибутами на связи (нужен percent).

**Альтернатива (отвергнута)**: Отдельная сущность `ContributionItem`. Проблема: избыточно для данных, которые живут только в пределах недели.

### 3. Триггер пересчёта нарушений

**Решение**: `RuleEngine.generateViolations(for: date)` вызывается в любой точке, где `event.status = .structured` и применены `applyTotals`. Это три сценария:

1. Успешная LLM-оценка (`estimate()`, после `event.status = .structured`)
2. Memory-оценка (`estimate()`, ветка memorySuggestion)
3. Ручная коррекция (`applyManualCorrection()`)

Дополнительно — в `DashboardView.onAppear` как fallback (подхватывает случаи возврата с другого экрана). Полный `fullRebuild` — только при открытии `RulesListView`.

### 4. Удаление minDaysData

**Решение**: Удалить поле `minDaysData` из `RuleDefinition`, из `nutrition_rules.json`, и все проверки в `RuleEngine` (`evaluateRangeRule`, `evaluateCountSkippedRule`, `bestWeekEvaluationDate`, `hasMinData`). Заменить на `daysWithStructuredMeals >= 1`.

### 5. DayAnalyticsPanel

**Решение**: Новый SwiftUI-компонент, вставляется в `DashboardView.ScrollView` после `DisclosureGroup("Питание")`. Получает `rules: [RuleDefinition]`, `engine: RuleEngine`, `date: Date`. Внутри группирует правила по трём категориям, показывает цветовой индикатор зоны и название. По тапу — навигация в `RuleDetailView`.

Кнопка «Совет дня» и `requestDailyAdvice()` удаляются. Модель `DailyAdvice` удаляется, если не используется в других местах. `Recommendation` остаётся (используется в LLM-агенте).

### 6. Удаление highCalorieFlag

**Решение**: Удалить поле `highCalorieFlag` из `EstimateItem` (SwiftData-модель). Удалить `EstimationRuntime.applyHighCalorieFlags()`. Удалить подсветку в `MealSlotCard` и `MealEventEditorView`. Удалить `isItemViolating` из `MealEventEditorView`.

Вместо этого подсветка продукта идёт через `RuleViolation.contributionJSON`.

### 7. MealSlotCard — переработка

**Решение**:
- Удалить: `highCalorieFlag` (строка 54), border (строки 67-70), `violations.count` badge (строки 15-23)
- Добавить: секцию с `violations`, где для каждого нарушения показывается название правила + причина + вклад продукта
- Фон карточки по `event.status` остаётся без изменений

**Связь нарушения с приёмом**: `violationsForMeal` анализирует `contributionJSON` всех нарушений дня, сверяет `itemId` с `mealEvent.estimateItems`. Если есть пересечение — нарушение относится к этому приёму. Одно нарушение может отображаться в нескольких приёмах (продукты из разных приёмов вместе нарушили правило).

### 8. DayAnalyticsPanel — отображение

**Решение**:
- Всегда видимая секция в скролле дашборда, без `DisclosureGroup`
- Показывает все включённые правила с цветовым индикатором зоны
- Группировка: «Баланс макронутриентов» (5 правил), «Ограничения» (5 правил), «Качество продуктов и режим» (6 правил) — четвёртая группа `eating_pattern` объединена с `food_quality`
- Расчёт всегда по текущим данным за выбранный день (любое количество приёмов)
- Тап по правилу → `NavigationLink` в `RuleDetailView`

## Risks / Trade-offs

- **[Risk] Порог >30% может не найти ни одного продукта при равномерном вкладе** → Показываем нарушение без привязки к продукту, только на уровне дня
- **[Risk] Оценка по одному дню для недельных правил даёт неполную картину** → Показываем статус по доступным дням, label «Данные за N дней» в DayAnalyticsPanel
- **[Risk] Удаление minDaysData ломает обратную совместимость JSON** → Правим `nutrition_rules.json` в bundle, старые версии не поддерживаются
- **[Risk] contributionJSON может устареть при редактировании старого приёма** → `generateViolations` перезаписывает все нарушения за день, включая contributionJSON
- **[Trade-off] contributionJSON — денормализация (имя продукта в JSON)** → Имя нужно для отображения без запроса к БД. При удалении продукта violation удаляется каскадно
