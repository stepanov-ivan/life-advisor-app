## 1. Модели данных — удаление и добавление полей

- [x] 1.1 Удалить поле `minDaysData` из `RuleDefinition.swift`
- [x] 1.2 Удалить `minDaysData` из всех правил в `nutrition_rules.json`
- [x] 1.3 Удалить поле `highCalorieFlag` из `EstimateItem.swift` (SwiftData-модель)
- [x] 1.4 Добавить `contributionJSON: String?` в `RuleViolation.swift`

## 2. RuleEngine — удаление minDaysData

- [x] 2.1 Удалить параметр `minDays` из `bestWeekEvaluationDate(minDays:)` — заменить на `bestWeekEvaluationDate()`
- [x] 2.2 Удалить проверки `daysWithStructuredMeals < rule.minDaysData` в `evaluateRangeRule` — заменить на `daysWithStructuredMeals == 0 → .noData`
- [x] 2.3 Удалить проверку `daysWithStructuredMeals < rule.minDaysData` в `evaluateCountSkippedRule` — заменить на `daysWithStructuredMeals == 0 → .noData`
- [x] 2.4 Удалить метод `hasMinData()` полностью

## 3. RuleEngine — контрибьюшн-анализ

- [x] 3.1 Реализовать `contributionMap(for:rule:date:) -> [(itemId: String, name: String, percent: Double)]` — для range-правил: абсолютные метрики = itemValue/dailyTotal, процентные = itemNutrientGrams/totalNutrientGrams; для presence: 100%; фильтр >30%, топ-3
- [x] 3.2 Реализовать `encodeContributionJSON(_ map:) -> String?` — сериализация карты в JSON
- [x] 3.3 Обновить `generateViolations(for:)` — вызывать `contributionMap`, записывать `contributionJSON` в `RuleViolation`
- [x] 3.4 Обновить `violationsForMeal(_:)` — анализировать `contributionJSON`, сверять `itemId` с `meal.estimateItems`; fallback на `violation.mealEvent == meal` для правил без контрибьюшн

## 4. EstimationRuntime — удаление highCalorieFlag

- [x] 4.1 Удалить метод `applyHighCalorieFlags(for:)` из `EstimationRuntime.swift`
- [x] 4.2 Удалить все вызовы `applyHighCalorieFlags` из `DashboardView.swift` (строки 296, 354, 404, 892)

## 5. DashboardView — пересчёт нарушений после сохранения

- [x] 5.1 Добавить `ruleEngine.generateViolations(for: selectedDate)` в `estimate()` после `event.status = .structured` (LLM-ветка, строка 391)
- [x] 5.2 Добавить `ruleEngine.generateViolations(for: selectedDate)` в `estimate()` после memory-ветки (строка 370)
- [x] 5.3 Добавить `ruleEngine.generateViolations(for: selectedDate)` в `applyManualCorrection()` после `try? modelContext.save()` (строка 904)
- [x] 5.4 Добавить `ruleEngine.generateViolations(for: selectedDate)` в `DashboardView.onAppear` как fallback

## 6. DashboardView — удаление «Совета дня»

- [x] 6.1 Удалить кнопку «Совет дня» и `canGetAdvice` из body
- [x] 6.2 Удалить метод `requestDailyAdvice()` и `clearRecommendationCacheForToday()`
- [x] 6.3 Удалить модель `DailyAdvice` (если есть отдельный файл)
- [x] 6.4 Удалить связанные `@Query`/`FetchDescriptor` для `Recommendation` в контексте советов (сама модель `Recommendation` остаётся)

## 7. DayAnalyticsPanel — новый компонент

- [x] 7.1 Создать `DayAnalyticsPanel.swift` — SwiftUI-компонент с параметрами `rules`, `engine`, `date`
- [x] 7.2 Реализовать группировку правил по 3 категориям: «Баланс макронутриентов» (fat_percent, protein_percent, carbs_percent, energy_balance, pufa), «Ограничения» (saturated_fat, trans_fat, added_sugar, sodium, red_meat), «Качество продуктов и режим» (fiber, fruit_veg, legume_nut, ultra_processed, water, meal_regularity)
- [x] 7.3 Реализовать цветовой индикатор зоны для каждого правила (зелёный/жёлтый/красный/серый)
- [x] 7.4 Реализовать `NavigationLink` в `RuleDetailView` по тапу на правило
- [x] 7.5 Добавить `DayAnalyticsPanel` в `DashboardView.body` после `DisclosureGroup("Питание")`

## 8. MealSlotCard — переработка

- [x] 8.1 Удалить бейдж с количеством нарушений (строки 15-23)
- [x] 8.2 Удалить border (строки 67-70) и `borderColor`
- [x] 8.3 Удалить `highCalorieFlag` подсветку (строка 54)
- [x] 8.4 Добавить инлайн-секцию: для каждого violations показывать название правила + причину + значимые продукты из приёма с их процентом вклада
- [x] 8.5 Для приёма без нарушений — показывать «Все правила соблюдены» зелёным текстом

## 9. MealEventEditorView — очистка

- [x] 9.1 Удалить `isItemViolating` и восклицательный знак (строки 692-695)
- [x] 9.2 Удалить `highCalorieFlag` подсветку из состава блюда

## 10. Финальная проверка

- [x] 10.1 Убедиться что `RulesListView` не сломан — сводка и список правил работают
- [x] 10.2 Убедиться что `RuleDetailView` не сломан — график и список нарушений работают с `contributionJSON`
- [x] 10.3 Проверить что `AnalyticsView` не затронут изменениями
- [x] 10.4 Собрать проект без ошибок компиляции
