## 1. Модель данных explainability

- [x] 1.1 Добавить SwiftData-сущность `RuleContributionSnapshot` с полями дневного summary правила (`ruleId`, `date`, `zone`, текущее значение, человекочитаемая норма).
- [x] 1.2 Добавить SwiftData-сущность `RuleContributionItem` со связями на `RuleContributionSnapshot`, `MealEvent` и `EstimateItem`, а также с absolute/percent contribution и day-order index.
- [x] 1.3 Удалить `RuleViolation.contributionJSON` из моделей, хранения и всех связанных сериализаций.

## 2. Пересчёт правил и snapshot-генерация

- [x] 2.1 Перевести дневную оценку `range`-правил на бинарную модель `normal` / `violation` / `no_data` без `warning` и `approaching_*`.
- [x] 2.2 Перевести `countSkipped` и остальные поддерживаемые дневные special-case правила на бинарную модель без `warning`.
- [x] 2.3 На каждом пересчёте дня пересоздавать `RuleContributionSnapshot` и `RuleContributionItem` для поддерживаемых дневных `range` и `presence` правил.
- [x] 2.4 Реализовать расчёт absolute/percent contribution для gram-based, presence и percent-based дневных правил по согласованным форматам отображения.

## 3. Трейсинг нарушений и связи с приёмами

- [x] 3.1 Перевести `violationsForMeal(_:)` на поиск нарушений через связи `RuleContributionItem.mealEvent` и `RuleContributionItem.estimateItem`.
- [x] 3.2 Обновить product-level tracing так, чтобы продукт считался значимым только при вкладе >20% в нарушенное правило.
- [x] 3.3 Убедиться, что один продукт может возвращать несколько нарушенных правил и они сортируются по убыванию вклада.

## 4. `DayAnalyticsPanel` и inline breakdown

- [x] 4.1 Убрать переход из строки правила в отдельный экран и заменить его inline-раскрытием внутри `DayAnalyticsPanel`.
- [x] 4.2 Ограничить `DayAnalyticsPanel` только дневными правилами с поддерживаемым contribution breakdown, скрыв weekly rules и неподдерживаемые rule types.
- [x] 4.3 Реализовать состояние одного одновременно раскрытого правила с повторным тапом для сворачивания.
- [x] 4.4 Показать в строке правила название, текущее значение метрики и disclosure indicator только для раскрываемых правил.
- [x] 4.5 Реализовать раскрытие с коротким summary-header, человекочитаемой нормой и top-3 продуктами по убыванию вклада.
- [x] 4.6 Добавить действие `Ещё X продуктов` / `Свернуть` для хвоста breakdown без отдельной навигации.
- [x] 4.7 Отобразить вклад продукта в формате `абсолютное значение (доля)` для gram/category rules и только `абсолютное значение` для percent-based rules.

## 5. `MealSlotCard` и product-level feedback

- [x] 5.1 Удалить summary нарушений на уровне всего приёма из `MealSlotCard`.
- [x] 5.2 Оставить только product-level highlighting для продуктов с вкладом >20% в нарушенные правила.
- [x] 5.3 Показывать под раскрытым продуктом все нарушенные правила, в которые он внёс значимый вклад, отсортированные по убыванию вклада.
- [x] 5.4 Привести формат строки правила под продуктом к тем же правилам отображения, что и в `DayAnalyticsPanel`.
- [x] 5.5 Обновить цветовую семантику карточки и правил под бинарную модель `normal` / `violation` / `no_data` без warning-палитры.

## 6. Удаление старого UX и точки входа

- [x] 6.1 Убрать entry points в `RuleDetailView` и исключить отдельный экран правила из пользовательского сценария.
- [x] 6.2 Удалить или изолировать legacy-код недельного графика и старого rule drill-down, который больше не используется новым UX.

## 7. Тесты и регрессии

- [x] 7.1 Обновить unit-тесты оценки правил под бинарную модель без `warning`.
- [x] 7.2 Добавить тесты на генерацию `RuleContributionSnapshot` и `RuleContributionItem` для `range` и `presence` правил.
- [x] 7.3 Добавить тесты на `violationsForMeal(_:)` и product-level tracing через contribution entities вместо JSON.
- [x] 7.4 Добавить UI/logic-тесты на inline breakdown в `DayAnalyticsPanel` и на список нарушенных правил под продуктом в `MealSlotCard`.
