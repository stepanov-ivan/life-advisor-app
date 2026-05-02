## MODIFIED Requirements

### Requirement: Модель MealEvent
Система SHALL хранить данные о приёмах пищи в сущности `MealEvent` с поддержкой agent-first lifecycle-статусов (`pending-estimation`, `structured`, `parse_failed`, `skipped`) и полей оценки LLM.

#### Scenario: Создание события в agent-first потоке
- **WHEN** пользователь вводит текст «овсянка с ягодами» для слота «Завтрак»
- **THEN** создаётся запись `MealEvent` со статусом `pending-estimation`, `rawText = "овсянка с ягодами"` и ожидаемой LLM-оценкой

#### Scenario: Успешная оценка
- **WHEN** LLM возвращает валидную оценку
- **THEN** статус события меняется на `structured`, а агрегированные калории и БЖУ обновляются

#### Scenario: Ошибка парсинга
- **WHEN** LLM-ответ не проходит schema-валидацию
- **THEN** статус события меняется на `parse_failed`, raw текст сохраняется для повторной отправки

### Requirement: Модель EstimateItem
Система SHALL хранить компоненты оценки как LLM-derived explainability-слой в новой сущности `EstimateItem` для режима `ingredient_breakdown`, без зависимости от справочника и семантики «на 100г».

#### Scenario: Breakdown-режим
- **WHEN** LLM возвращает `mode = ingredient_breakdown`
- **THEN** система сохраняет компоненты оценки в `EstimateItem` с оценочными макросами и полями explainability для показа и подсветки high-impact

#### Scenario: Composite-режим
- **WHEN** LLM возвращает `mode = composite_item`
- **THEN** система сохраняет один `EstimateItem` без обязательной декомпозиции на подкомпоненты

### Requirement: Агрегация БЖУ
Система SHALL вычислять итоговые поля `calories`, `proteins`, `fats`, `carbs` из результата LLM и обеспечивать консистентность с компонентами в режиме breakdown.

#### Scenario: Проверка консистентности breakdown
- **WHEN** режим оценки `ingredient_breakdown`
- **THEN** сумма макроэлементов по компонентам совпадает с totals в пределах допуска ±5%

### Requirement: Хранение окна питания
Система SHALL хранить настройки окон питания в сущности `MealWindow` с полями: `name` (String), `startTime` (DateComponents), `endTime` (DateComponents), `order` (Int). До 6 окон.

#### Scenario: Настройка окон в onboarding
- **WHEN** пользователь завершает onboarding
- **THEN** создаются 3 стандартных окна: Завтрак (7:00–10:00), Обед (12:00–15:00), Ужин (18:00–21:00)

#### Scenario: Удаление окна не удаляет события
- **WHEN** пользователь удаляет окно «Перекус», для которого существуют `MealEvent` с `windowLabel = "Перекус"`
- **THEN** окно удаляется, но `MealEvent` сохраняются в БД. При создании нового окна с тем же названием старые события снова отображаются на дашборде

### Requirement: Модель Recommendation
Система SHALL хранить последнюю рекомендацию по питанию в сущности `Recommendation` с полями: `date` (Date), `recommendationText` (String), `createdAt` (Date). Одна рекомендация на день — перезаписывается при новом запросе.

#### Scenario: Сохранение рекомендации
- **WHEN** LLM возвращает рекомендацию на оставшиеся приёмы
- **THEN** создаётся или обновляется `Recommendation` за текущую дату

#### Scenario: Отображение рекомендации на слоте
- **WHEN** пользователь открывает вкладку «Рекомендация» на любом незаполненном слоте
- **THEN** отображается сохранённый `recommendationText`, если он есть за сегодня

## ADDED Requirements

### Requirement: Хранение explainability и версий оценки
Система SHALL сохранять explainability-поля (`confidence`, `impact_score`, `reason`, `assumptions`) и метаданные версии оценки (`modelId`, `promptVersion`, `estimationSchemaVersion`) вместе с результатом логирования.

#### Scenario: Сохранение explainability
- **WHEN** получен валидный ответ LLM
- **THEN** система сохраняет confidence, причину подсветки и версионные поля для последующего отображения и дебага

### Requirement: Хранение raw payload и retention
Система SHALL хранить raw JSON-ответ LLM не более 90 дней и удалять его после истечения срока, сохраняя нормализованные поля.

#### Scenario: Очистка raw payload
- **WHEN** выполняется плановая очистка и возраст raw payload превышает 90 дней
- **THEN** система удаляет raw payload, не удаляя итоговые значения калорий/БЖУ и explainability-поля

### Requirement: Память пользовательских правок
Система SHALL сохранять ручные корректировки как память по нормализованному fingerprint и отмечать применение памяти в логе.

#### Scenario: Применение prior-памяти
- **WHEN** новый ввод совпадает по нормализованному fingerprint с ранее скорректированным кейсом
- **THEN** система применяет память как prior и сохраняет флаг, что память участвовала в оценке

### Requirement: Сохранение последней валидной оценки при parse_failed
Система SHALL сохранять последнюю валидную оценку при переоценке существующего лога, если новый ответ LLM завершился `parse_failed`.

#### Scenario: Parse-failed после успешной оценки
- **WHEN** пользователь запускает переоценку существующего лога и новый ответ LLM не проходит schema-валидацию
- **THEN** система сохраняет статус `parse_failed` и raw текст ошибки, но не затирает предыдущие валидные значения калорий/БЖУ и explainability

#### Scenario: Отображение устаревшей оценки
- **WHEN** лог находится в `parse_failed`, но имеет сохранённую предыдущую валидную оценку
- **THEN** система показывает эту оценку с явной пометкой, что она не обновлена последней попыткой

### Requirement: Snapshot overwrite при переоценке
Система SHALL при успешной переоценке полностью заменять набор `EstimateItem` для соответствующего `MealEvent` новым снапшотом.

#### Scenario: Полная замена компонент оценки
- **WHEN** пользователь повторно оценивает существующий лог и получает валидный ответ LLM
- **THEN** старые `EstimateItem` удаляются, а новые сохраняются как единственный актуальный набор

### Requirement: Retention после удаления raw payload
Система SHALL после purge raw payload сохранять краткую сводку ошибки парсинга (`parse_error_summary`) для диагностики.

#### Scenario: Purge raw с сохранением summary
- **WHEN** raw payload удалён по правилу 90 дней
- **THEN** `parse_error_summary` и нормализованные поля остаются доступными для аналитики и отладки

## REMOVED Requirements

### Requirement: Модель MealTemplate
**Reason**: Шаблоны исключены из основного UX-потока agent-first логирования в рамках данного change.
**Migration**: Повторяемость пользовательского поведения переносится в механизм памяти правок по нормализованному fingerprint.

### Requirement: Модель Ingredient
**Reason**: Модель `Ingredient` заменяется на `EstimateItem` как целевая explainability-модель agent-first оценки.
**Migration**: Выполнить destructive migration схемы и перенести код на использование `EstimateItem`.
