## ADDED Requirements

### Requirement: SwiftData-сущность NutritionRuleConfig
Система SHALL хранить настройки включения/выключения правил в SwiftData-модели `NutritionRuleConfig` с полями `ruleId: String` и `isEnabled: Bool`.

#### Scenario: Создание конфига для нового правила
- **WHEN** RuleEngine встречает правило из JSON, для которого нет `NutritionRuleConfig`
- **THEN** система создаёт новую запись с `isEnabled = true`

#### Scenario: Удаление конфига для удалённого правила
- **WHEN** правило удалено из JSON
- **THEN** соответствующий `NutritionRuleConfig` удаляется при следующей загрузке

### Requirement: SwiftData-сущность RuleViolation
Система SHALL хранить нарушения правил в SwiftData-модели `RuleViolation` с полями: `ruleId: String`, `date: Date`, `zone: String`, `magnitude: Double`, `reasonCode: String`, и связями `@Relationship` на `MealEvent?` и `EstimateItem?`.

#### Scenario: Создание нарушения с привязкой к приёму
- **WHEN** правило нарушено и нарушение связано с конкретным приёмом
- **THEN** `RuleViolation` сохраняется с `mealEvent` и `estimateItem` ссылками

#### Scenario: Каскадное удаление при удалении MealEvent
- **WHEN** `MealEvent` удаляется
- **THEN** связанные `RuleViolation` удаляются автоматически

### Requirement: Новые поля в EstimateItem
Система SHALL добавить опциональные поля в `EstimateItem`: `estimatedSaturatedFats`, `estimatedSugar`, `estimatedFiber`, `estimatedSodium` (все `Double`) и `foodCategory: String?`.

#### Scenario: LLM вернул все новые поля
- **WHEN** LLM возвращает saturated_fats, sugar, fiber, sodium и food_category для ингредиента
- **THEN** все поля сохраняются в `EstimateItem`

#### Scenario: LLM не вернул часть полей
- **WHEN** LLM возвращает только часть новых полей
- **THEN** отсутствующие поля сохраняются как `nil` или `0`, не ломая сохранение

#### Scenario: Старый приём без новых полей
- **WHEN** приём был создан до добавления новых полей
- **THEN** значения по умолчанию (0/Double или nil) не вызывают ошибок при агрегации

## MODIFIED Requirements

### Requirement: Модель MealEvent
Система SHALL хранить для `MealEvent` источник структуры (`memory_suggestion`/`llm`/`manual_override`) и флаг синхронности текста и структуры (`out_of_sync`).

#### Scenario: Лог создан из подсказки
- **WHEN** пользователь выбирает подсказку из памяти
- **THEN** `MealEvent` сохраняется с источником `memory_suggestion`

#### Scenario: Текст изменён после подстановки
- **WHEN** пользователь редактирует текст после подстановки структуры
- **THEN** `MealEvent`/черновик помечается как `out_of_sync`

#### Scenario: Ручная правка структуры
- **WHEN** пользователь вручную изменил структуру после подстановки
- **THEN** источник структуры сохраняется как `manual_override`

### Requirement: Хранение памяти подсказок
Система SHALL хранить memory-шаблоны для быстрого повторного ввода и обновлять основной шаблон только при правке в пределах 30% по калориям.

#### Scenario: Правка в пределах порога
- **WHEN** пользователь скорректировал структуру и изменение калорий не превышает 30%
- **THEN** основной memory-шаблон обновляется

#### Scenario: Правка выше порога
- **WHEN** изменение калорий превышает 30%
- **THEN** запись сохраняется как `candidate` без перезаписи основного шаблона

#### Scenario: Продвижение candidate в основной шаблон
- **WHEN** candidate повторился 2 или более раз в пределах одного canonical-шаблона
- **THEN** candidate становится основным шаблоном, а предыдущий основной сохраняется как fallback

#### Scenario: Лимит версий шаблона
- **WHEN** число версий шаблона в canonical-группе превышает 3
- **THEN** система удаляет самые старые fallback-версии и сохраняет только текущую и 2 последние fallback

### Requirement: Data-gap хранилище
Система SHALL хранить записи `data-gap`, закрывать их автоматически после 2 подтверждённых уточнений по похожему блюду и удалять неактивные записи через 60 дней.

#### Scenario: Автозакрытие data-gap
- **WHEN** по похожему блюду получены 2 повторных уточнения порции
- **THEN** соответствующий `data-gap` помечается как закрытый

#### Scenario: Retention data-gap
- **WHEN** запись `data-gap` не обновлялась 60 дней
- **THEN** система удаляет эту запись

### Requirement: Гипотезы памяти
Система SHALL хранить гипотезы предпочтений со статусом и датой следующего показа и удалять неподтверждённые гипотезы через 60 дней неактивности.

#### Scenario: Отложенный повтор гипотезы
- **WHEN** пользователь выбирает `Спросить позже`
- **THEN** дата следующего показа устанавливается не ранее чем через 3 дня

#### Scenario: Retention неподтверждённой гипотезы
- **WHEN** гипотеза находится в `pending_confirmation` и не обновлялась 60 дней
- **THEN** система удаляет эту гипотезу
