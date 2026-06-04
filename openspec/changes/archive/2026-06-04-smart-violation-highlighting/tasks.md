## 1. RuleEngine — фильтрация contribution

- [x] 1.1 contributionForPresenceRule: исключить category_missing — для inverse:false (правила «должна быть категория X») возвращать пустой массив, чтобы contributionJSON был nil и нарушение не попадало в карточки приёмов
- [x] 1.2 contributionForRangeRule: поднять порог вклада с 30% до 33% (строка `$0.percent > 30` → `$0.percent > 33`)

## 2. RuleEngine — формат описания нарушений

- [x] 2.1 violationDescription(for:): изменить формат с «Превышение: 14,2% при норме ≤10%» на «Добавленный сахар: 14,2% при норме ≤10%» — использовать `rule.title` вместо reasonCode-текста во всех кейсах (exceeds_upper, below_lower, approaching_upper, approaching_lower). Для category_missing, unwanted_category_present, excessive_skips, some_skips оставить текущий формат.

## 3. RulesListView — удаление зоновых индикаторов

- [x] 3.1 Удалить summary-секцию (строка «N из M» + круговой индикатор summaryCircle)
- [x] 3.2 Удалить zoneIndicator (цветной кружок) и zoneLabel (текст «В норме»/«Нарушено») из ruleRow
- [x] 3.3 Удалить вызов `engine.evaluateToday(rule:)` из ruleRow
- [x] 3.4 Убедиться, что категории-секции, названия, описания и toggle вкл/выкл остались

## 4. MealSlotCard — фильтрация нарушений в UI

- [x] 4.1 В productViolationMap: пропускать нарушения с `reasonCode = "below_lower"` и `"approaching_lower"` — не добавлять их продукты в словарь
- [x] 4.2 В списке нарушений (ForEach): фильтровать `violations` — показывать только exceeds_upper, approaching_upper, unwanted_category_present
- [x] 4.3 Убрать зелёную плашку «Все правила соблюдены» — если релевантных нарушений нет, секция просто отсутствует

## 5. Сборка и проверка

- [x] 5.1 Сборка проекта: `xcodebuild -project LifeAdvisorApp/LifeAdvisorApp.xcodeproj -scheme LifeAdvisorApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
- [x] 5.2 Проверить на симуляторе: экран правил без индикаторов, только toggle
- [x] 5.3 Проверить на симуляторе: карточка приёма показывает только релевантные превышения с названиями правил
- [x] 5.4 Проверить на симуляторе: category_missing и below_lower не отображаются в карточках
