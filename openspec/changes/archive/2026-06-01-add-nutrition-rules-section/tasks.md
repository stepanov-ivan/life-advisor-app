## 1. Модели данных

- [x] 1.1 Добавить поля `estimatedSaturatedFats`, `estimatedSugar`, `estimatedFiber`, `estimatedSodium`, `foodCategory` в `EstimateItem`
- [x] 1.2 Создать `NutritionRuleConfig` — SwiftData @Model с полями `ruleId: String`, `isEnabled: Bool`
- [x] 1.3 Создать `RuleViolation` — SwiftData @Model с полями `ruleId`, `date`, `zone`, `magnitude`, `reasonCode` и @Relationship на `MealEvent?` и `EstimateItem?`
- [x] 1.4 Обновить `ModelContainer` в `LifeAdvisorApp.swift` для регистрации новых сущностей

## 2. JSON-конфигурация правил

- [x] 2.1 Создать `Resources/nutrition_rules.json` с 16 правилами ВОЗ/ФАО (4 категории, единый примитив `range`, presence/countSkipped как особые случаи)
- [x] 2.2 Создать `RuleDefinition` — Codable struct для парсинга JSON (id, type, field, params, warningRatio, category, title, description, window, minDaysData)
- [x] 2.3 Реализовать валидацию правил при загрузке: проверка `field` на соответствие модели, `type == "range"`, `window` ∈ ["day", "week"], границы корректны; некорректные правила логировать и пропускать

## 3. Rule Engine

- [x] 3.1 Создать `Services/RuleEvaluation.swift` — чистая функция `evaluateRange(value:lower:upper:warningRatio:) -> Zone`, особые функции `evaluatePresence` и `evaluateCountSkipped`
- [x] 3.2 Создать `Services/RuleEngine.swift` — загрузка JSON, фильтрация enabled, оркестрация оценки, вычисление агрегатов из `EstimateItem` на лету
- [x] 3.3 Реализовать инкрементальный пересчёт: полный слепок при первом входе/начале новой недели, дельта дня при сохранении/редактировании приёма
- [x] 3.4 Реализовать логику пропуска skipped-приёмов (все правила кроме `who_meal_regularity`) и parseFailed-приёмов, пропуск дня если все приёмы skipped
- [x] 3.5 Реализовать вычисление процентов от калорийности (fat × 9, protein/carbs/sugar × 4), обработка totalCalories = 0
- [x] 3.6 Реализовать сброс недельных правил в понедельник, удаление старых `RuleViolation`
- [x] 3.7 Реализовать синхронизацию `NutritionRuleConfig` с JSON — создание конфигов для новых правил, удаление для отсутствующих

## 4. LLM-контракт

- [x] 4.1 Расширить JSON-контракт в `LLMClient.swift` — опциональные поля `saturated_fats`, `sugar`, `fiber`, `sodium`, `food_category` на уровне item и totals
- [x] 4.2 Обновить промпт LLM — добавить описание новых полей и 8 значений `food_category` в системный промпт
- [x] 4.3 Обновить парсинг ответа LLM — маппинг новых полей в `EstimateItem`, валидация `foodCategory` (неизвестные значения → "other")
- [x] 4.4 Обновить memory-путь — маппинг новых полей из `ManualDraftStructure` и memory-suggestion items

## 5. Экран списка правил

- [x] 5.1 Создать `Views/RulesListView.swift` — список правил с 4 секциями (макронутриенты, ограничения, качество продуктов, режим питания)
- [x] 5.2 Добавить сводную плашку «N из M правил соблюдаются» с цветовой кодировкой
- [x] 5.3 Добавить индикатор зоны для каждого правила (зелёный/жёлтый/красный/серый) и статус daily freshness («нет данных» если сегодня нет приёмов)
- [x] 5.4 Добавить toggle enabled/disabled для каждого правила через `NutritionRuleConfig`
- [x] 5.5 Добавить отображение минимального порога данных: серый статус если <3 дней structured

## 6. Экран детали правила

- [x] 6.1 Создать `Views/RuleDetailView.swift` — график значения по дням недели (пн–вс) с линиями порогов и warning-зон
- [x] 6.2 Реализовать отрисовку графика: линия значений, линии lower/upper, затенённые warning-зоны, разрывы для дней без данных
- [x] 6.3 Добавить список нарушений за неделю с drill-down: правило → дата → приём → ингредиент, с `reasonCode` и `magnitude`
- [x] 6.4 Реализовать навигацию от нарушения: тап → запись даты в `selectedDate` → переключение таба на Дашборд → открытие `MealEventEditorView`

## 7. Интеграция с дашбордом

- [x] 7.1 Поднять `selectedDate` с `DashboardView` на `ContentView`, пробросить как `@Binding` в `DashboardView`
- [x] 7.2 Вынести `MealSlotCard` в отдельный файл `Views/MealSlotCard.swift`
- [x] 7.3 Добавить цветной левый бордер на `MealSlotCard` (красный при violation) и бейдж с количеством нарушений
- [x] 7.4 Добавить вызов `RuleEngine.violationsForMeal(meal:)` в `DashboardView.onAppear` и после `saveMealEvent`
- [x] 7.5 Добавить иконку ингредиента-нарушителя в `MealEventEditorView` для строк с `EstimateItem`, связанным с `RuleViolation`

## 8. Навигация и табы

- [x] 8.1 Добавить 4-й таб «Правила» в `TabView` (`ContentView.swift`) с программным переключением
- [x] 8.2 Реализовать программное переключение табов из `RuleDetailView` через `@Binding` на `selectedTab`

## 9. Тестирование

- [x] 9.1 Unit-тесты для range-примитива: обе границы, только lower, только upper, day/week окно
- [x] 9.2 Unit-тесты для presence и countSkipped
- [x] 9.3 Unit-тесты для трёхзонной оценки (normal/warning/violation) и warningRatio
- [x] 9.4 Unit-тесты для вычисления процентов от калорийности
- [x] 9.5 Unit-тесты для валидации JSON-правил (корректные, некорректные, отсутствующие поля)
- [x] 9.6 Unit-тесты для инкрементального пересчёта (слепок, дельта, сброс недели)
