## 1. Agent Foundation

- [x] 1.1 Добавить глобальную CTA-кнопку агента поверх `ContentView`/`TabView` как единую точку входа в agent flow
- [x] 1.2 Ввести общий in-memory state для одной активной agent-сессии с lifecycle `idle / chat-input / planning / executing / completed / cancelled`
- [x] 1.3 Реализовать общий `AgentScenarioRouter`, который пока маршрутизирует только в meal domain, но не зашит как meal-only решение

## 2. Meal Classification And Planning

- [x] 2.1 Реализовать `MealScenarioClassifier` для сценариев `meal-create` и `meal-edit` с определением временного контекста запроса
- [x] 2.2 Реализовать `MealStepPlanner`, который строит нормализованные шаги `create/edit` с группировкой по дням и детерминированным порядком meal slots
- [x] 2.3 Определить и внедрить JSON-контракт обмена между LLM-классификацией, planner-ом и локальным runtime для `scenario`, `steps`, `productsDraft` и resolve-state
- [x] 2.4 Передавать в planner/LLM контекст существующего дня для релевантных create/edit сценариев

## 3. Execution Shell And Dashboard Integration

- [x] 3.1 Добавить общий execution shell с progress bar, кнопкой закрытия и переключением на home surface meal domain
- [x] 3.2 Перевести `DashboardView` в execution mode для meal domain без открытия отдельного editor-экрана
- [x] 3.3 Реализовать активное состояние карточки приёма пищи для текущего шага execution chain
- [x] 3.4 Добавить группировку шагов по дням и автоматическое переключение `selectedDate` при переходе между day groups

## 4. Meal Draft Editing And Resolve

- [x] 4.1 Ввести ephemeral meal draft state для каждого шага без раннего создания persisted `MealEvent`
- [x] 4.2 Реализовать локальные действия над draft-ом: `add product`, `remove product`, `change portion`
- [x] 4.3 Зафиксировать `date` и `mealSlot` как read-only после планирования и исключить их прямое ручное редактирование в execution mode
- [x] 4.4 Реализовать resolve-сценарии для конфликтов и нехватки аргументов через управляемые UI-контролы day/slot и переход `create -> edit`

## 5. Meal-Level Commit And Existing Pipeline Reuse

- [x] 5.1 Реализовать meal-level commit для шага `create` с сохранением `MealEvent` только после подтверждения draft-а
- [x] 5.2 Реализовать meal-level commit для шага `edit` с обновлением существующего `MealEvent` только после подтверждения draft-а
- [x] 5.3 Подключить существующий pipeline сохранения `EstimateItem`, totals и rule recomputation после каждого подтверждённого шага
- [x] 5.4 Реализовать auto-advance к следующему шагу после успешного commit-а и корректное завершение chain на последнем шаге

## 6. Replace Legacy Meal Logging Flow

- [x] 6.1 Убрать старый slot-based flow ввода через `LogSheetView` как основной пользовательский сценарий логирования
- [x] 6.2 Убрать старый flow проваливания в meal input/editor как основной путь создания и правки приёма пищи
- [x] 6.3 Перенести необходимую информацию из старого meal editor на карточку приёма пищи и в execution mode
- [x] 6.4 Сохранить совместимость с существующими persisted meal models без миграции данных

## 7. Verification

- [x] 7.1 Добавить тесты на классификацию `meal-create` и `meal-edit` и построение single-step/multi-step планов
- [x] 7.2 Добавить тесты на multi-day execution chain, day grouping и single active session
- [x] 7.3 Добавить тесты на resolve-конфликт `create` при занятом `date + mealSlot`
- [x] 7.4 Добавить тесты на partial completion: подтверждённые шаги сохраняются, неподтверждённый хвост теряется при отмене
