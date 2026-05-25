## Why

Приложение умеет фиксировать питание, но не даёт устойчивой, объяснимой обратной связи по качеству рациона на уровне паттернов. Нужен ненавязчивый механизм правил, который оценивает текущую неделю, показывает конкретные нарушения и помогает пользователю корректировать поведение без обязательного онбординга.

## What Changes

- Добавить отдельную секцию `Правила` в нижнюю навигацию рядом с текущими разделами (`Дашборд`, `Аналитика`, `Настройки`).
- Реализовать 16 правил питания на основе рекомендаций ВОЗ/ФАО (2024), определённых в JSON-файле в bundle.
- Реализовать единый вычислительный примитив `range` с опциональными границами (`lower`/`upper`) и параметром окна (`day`/`week`), покрывающий 14 из 16 правил. Оставшиеся 2 (`presence`, `countSkipped`) — особые случаи в RuleEngine.
- Правила оцениваются в фиксированной неделе (понедельник–воскресенье) с минимумом 3 днями данных (≥1 structured приём в день).
- Расчёт инкрементальный: первичный слепок на неделю, далее только дельта нового дня.
- Статус правила отражает сегодняшний день (daily freshness); если данных за сегодня нет — «нет данных» (серый).
- Три зоны оценки: normal / warning (≥85% порога) / violation (превышение порога).
- Все правила включены по умолчанию. Пользователь может включить/выключить каждое правило через `NutritionRuleConfig` в SwiftData.
- Конфигурация порогов пользователем не реализуется в v1 — используются фиксированные пороги ВОЗ.
- Трейсинг нарушений до конкретного приёма пищи и ингредиента с причиной и величиной отклонения.
- Экран детали правила с графиком за текущую неделю и списком нарушений с drill-down: день → приём → ингредиент.
- Навигация от нарушения: `selectedDate` поднят на `ContentView`, проброшен как `@Binding`. Тап по нарушению → переключение таба на Дашборд + установка даты + открытие приёма.
- Подсветка нарушений в ленте питания: цветной левый бордер (красный при наличии violation) и бейдж с количеством нарушений у MealSlotCard (вынесен в отдельный файл); иконка у ингредиента-нарушителя в MealEventEditorView.
- Контекст нарушения: какое правило, причина, величина отклонения, ссылка на приём пищи.

## 16 правил ВОЗ (4 категории)

### Баланс макронутриентов
1. Белок 10–15% энергии (range, day)
2. Жиры 15–30% энергии (range, day)
3. Насыщенные жиры ≤10% энергии (range, day, только upper)
4. Трансжиры ≤1% энергии (range, day, только upper)
5. ПНЖК 6–10% энергии (range, day)
6. Углеводы 45–75% энергии (range, day)

### Ограничения
7. Свободный сахар ≤10% энергии (range, day, только upper)
8. Соль ≤2000 мг натрия (range, day, только upper)
9. Энергобаланс: сравнение с целью пользователя (range, week)
10. Клетчатка ≥25 г (range, day, только lower)

### Качество продуктов
11. Овощи и фрукты ≥400 г/день (range, day, только lower; сумма grams по категориям fruit + vegetable)
12. Цельные злаки ежедневно (presence, хотя бы 1 ингредиент с foodCategory=whole_grain)
13. Бобовые/орехи/семена ежедневно (presence, хотя бы 1 с foodCategory=legume или nut_seed)
14. Красное мясо ≤500 г/неделю (range, week, только upper; сумма grams по foodCategory=red_meat)
15. Обработанное мясо отсутствует (presence, ни одного с foodCategory=processed_meat)

### Режим питания
16. Регулярность приёмов: пропуски окон (countSkipped, 1–3 = warning, 4+ = violation из недели)

**Исключено из v1:** правило «Вода» (нет трекинга воды в приложении).

## Data Model

### Новые SwiftData-сущности
- `NutritionRuleConfig`: ruleId (String), isEnabled (Bool). Создаётся для каждого правила при первом запуске. SwiftData — источник истины для enabled/disabled, JSON — read-only определения.
- `RuleViolation`: ruleId, date, zone ("warning" | "violation"), magnitude, reasonCode. Связан через `@Relationship` с `MealEvent?` и `EstimateItem?`.

### Расширение EstimateItem (опциональные поля)
- `estimatedSaturatedFats: Double` — насыщенные жиры (г)
- `estimatedSugar: Double` — свободный сахар (г)
- `estimatedFiber: Double` — клетчатка (г)
- `estimatedSodium: Double` — натрий (мг)
- `foodCategory: String?` — одно из: fruit, vegetable, whole_grain, legume, nut_seed, red_meat, processed_meat, other

### Агрегация
MealEvent не хранит агрегаты новых полей — они суммируются на лету из EstimateItem.
Skipped-приёмы исключаются из всех правил кроме who_meal_regularity.
ParseFailed-приёмы исключаются из оценки (missing data).
Если все приёмы за день skipped — день пропускается в агрегации.

## Rule Engine

- `Services/RuleEngine.swift` — загрузка JSON из bundle, валидация field names и параметров, evaluation orchestration, инкрементальный пересчёт, zone calculation.
- `Services/RuleEvaluation.swift` — чистые функции: `range` примитив, `presence` и `countSkipped` как особые случаи.
- `RuleDefinition` — Codable struct, маппинг на JSON-схему.
- `nutrition_rules.json` в Resources/ — определения правил, пороги, warningRatio, категории.
- Оценка ленивая: вычисляется при входе на экран правил + инкремент при сохранении приёма.
- DashboardView запрашивает RuleEngine при onAppear и после saveMealEvent для подсветки карточек.
- Валидация JSON при загрузке: проверка `field` на соответствие модели, `type == "range"`, `window` ∈ ["day", "week"]. Некорректные правила логируются и пропускаются.
- В понедельник: недельные правила сбрасываются, старые `RuleViolation` удаляются.

## LLM-контракт

Новые опциональные поля в JSON-ответе LLM (один промпт для всех полей):
- На уровне item: saturated_fats, sugar, fiber, sodium, food_category
- На уровне totals: saturated_fats, sugar, fiber, sodium
- Поля опциональны — отсутствие поля не ломает парсинг, правило получает статус «недостаточно данных».
- Только новые приёмы получают расширенные данные. Старые приёмы выпадают из окна естественно.
- foodCategory: только 8 значений (fruit, vegetable, whole_grain, legume, nut_seed, red_meat, processed_meat, other).

## UI

- 4-й таб «Правила» в TabView.
- Список правил с 4 секциями, каждая строка: индикатор (зелёный/жёлтый/красный/серый), название, статус.
- Сводная плашка: «N из 16 правил соблюдаются».
- Экран детали: график за текущую неделю (значение по дням, линии порогов и warning-зоны), список нарушений с раскрытием до ингредиента.
- Тап по нарушению → `RuleDetailView` пишет дату в `selectedDate` на `ContentView` → переключение таба на Дашборд → открытие MealEventEditorView.
- MealSlotCard (отдельный файл): цветной левый бордер (красный при violation) + бейдж с количеством нарушений.
- MealEventEditorView: иконка у ингредиента-нарушителя.
- Минимум данных: 3 дня из недели с ≥1 structured. Меньше → серый индикатор «Недостаточно данных».

## Миграция

Destructive reset при изменении схемы (существующий механизм).

## Capabilities

### New Capabilities
- `nutrition-rules`: каталог из 16 правил ВОЗ, включение/выключение.
- `rule-violation-tracing`: модель и журнал нарушений rule → day → meal → ingredient с zone, magnitude, reasonCode.
- `rule-analytics`: агрегирование недельных метрик, 3-зонная оценка, minimum data threshold.

### Modified Capabilities
- `dashboard-date-navigation`: 4-й таб `Правила`, переходы из нарушения в дашборд.
- `event-logging`: подсветка нарушений в MealSlotCard и MealEventEditorView.
- `local-storage`: новые SwiftData-сущности NutritionRuleConfig, RuleViolation; новые поля в EstimateItem.
- `llm-client`: расширенный JSON-контракт с опциональными полями нутриентов и foodCategory.

## Impact

- UI: новая вкладка, экран списка правил, экран детали с графиком и drill-down, индикаторы нарушений в ленте.
- Domain/Services: RuleEngine, RuleEvaluation, единый range-примитив, инкрементальный пересчёт.
- Data model: +2 сущности, +5 полей в EstimateItem.
- Existing flows: MealSlotCard (вынесен в отдельный файл) и MealEventEditorView получают индикаторы нарушений. `selectedDate` поднят на `ContentView`.
- LLM: расширенный промпт и контракт ответа.
- Тестирование: unit-тесты для range-примитива, presence/countSkipped, evaluation engine, zone calculation, валидации JSON.
