## 1. Подготовка доменной модели agent-first

- [ ] 1.1 Обновить модель статусов логирования: добавить `pending-estimation` и `parse_failed` с корректным отображением в UI.
- [ ] 1.2 Обновить модель хранения оценки в `MealEvent` (или связанной сущности): `mode`, `totals`, `confidence`, `modelId`, `promptVersion`, `estimationSchemaVersion`.
- [ ] 1.3 Добавить хранение explainability-полей (`impact_score`, `reason`, `high_calorie_flag`) на уровне компонентов оценки.
- [ ] 1.4 Добавить поля для raw payload LLM и метки времени для retention-очистки.
- [ ] 1.5 Добавить флаг применения памяти правок (memory-applied) в модели результата.
- [ ] 1.6 Ввести новую сущность `EstimateItem` с обязательными полями (`name`, estimated macros, `impact_score`, `reason`, `high_calorie_flag`, `sourceMode`) и связью к `MealEvent`.
- [ ] 1.7 Выполнить destructive migration: удалить/заменить старую модель `Ingredient` на `EstimateItem`.

## 2. Удаление справочника и связанных потоков

- [ ] 2.1 Удалить обязательное использование `FoodItem` в расчётах логирования и переоценки.
- [ ] 2.2 Удалить UI-потоки structured-ввода: «Из справочника», «Из истории», «Шаблоны».
- [ ] 2.3 Удалить/деактивировать seed-инициализацию справочника продуктов и связанный код поиска.
- [ ] 2.4 Проверить и убрать неиспользуемые модели/сервисы справочника из рантайм-потока.

## 3. Новый контракт LLM и валидация схемы

- [ ] 3.1 Обновить prompt и ответ `LLMClient` под строгий JSON-контракт agent-first.
- [ ] 3.2 Реализовать schema-валидацию обязательных полей (`mode`, `totals`, `confidence`, `items`, explainability).
- [ ] 3.3 Добавить проверку консистентности `ingredient_breakdown`: сумма компонентов к totals в пределах ±5%.
- [ ] 3.4 Добавить нормализацию `impact_score` в диапазон [0..1] на клиенте.
- [ ] 3.5 Реализовать fail-fast поведение без retry: при ошибке валидации выставлять `parse_failed`.

## 4. Логика оценки и сценарии переоценки

- [ ] 4.1 Реализовать основной поток: free-text → `pending-estimation` → `structured` при успешном ответе.
- [ ] 4.2 Реализовать `composite_item` и `ingredient_breakdown` режимы сохранения результата.
- [ ] 4.3 Реализовать поведение parse-failed для нового лога: сохранить rawText и показать действие правки/повторной отправки.
- [ ] 4.4 Реализовать поведение parse-failed при переоценке существующего лога: не затирать last good estimate и показывать stale-индикатор в UI.
- [ ] 4.5 Реализовать ручную корректировку оценки и сохранение правки как memory prior.
- [ ] 4.6 Реализовать snapshot overwrite: при успешной переоценке полностью заменять набор `EstimateItem` для `MealEvent`.

## 5. UI-обновления под agent-first

- [ ] 5.1 Обновить `LogSheetView`: оставить единый путь создания лога через текст.
- [ ] 5.2 Обновить карточки/детальный экран: показать confidence, explainability и high-impact подсветку.
- [ ] 5.3 Добавить non-blocking UX для `low confidence` (warning + быстрые действия без блокировки сохранения).
- [ ] 5.4 Добавить единое действие для `parse_failed`: правка текста перед повторной отправкой.
- [ ] 5.5 Добавить индикацию применения памяти правок в UI результата.

## 6. Память правок и retention

- [ ] 6.1 Реализовать нормализованный fingerprint для пользовательских логов.
- [ ] 6.2 Реализовать сохранение и поиск memory prior по fingerprint.
- [ ] 6.3 Реализовать применение memory prior без жёсткого override финальной оценки агента.
- [ ] 6.4 Реализовать lazy purge raw payload старше 90 дней (на старте и/или после сохранения новых логов), сохраняя `parse_error_summary`.

## 7. Тестирование и валидация изменения

- [ ] 7.1 Добавить тесты на JSON-schema валидацию ответа LLM (включая missing fields и invalid format).
- [ ] 7.2 Добавить тесты на dual-mode (`composite_item`/`ingredient_breakdown`) и правило ±5% консистентности.
- [ ] 7.3 Добавить тесты на lifecycle-статусы (`pending-estimation`, `structured`, `parse_failed`).
- [ ] 7.4 Добавить тест на сохранение last good estimate при parse-failed переоценке.
- [ ] 7.5 Добавить тесты на memory prior, флаг применения памяти и non-blocking low-confidence UX.
- [ ] 7.6 Добавить тесты на destructive migration (`Ingredient` -> `EstimateItem`) и корректность snapshot overwrite.
