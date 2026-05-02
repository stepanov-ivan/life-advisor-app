## ADDED Requirements

### Requirement: Модель MealEvent
Система SHALL хранить данные о приёмах пищи в сущности `MealEvent` со следующими полями: `id` (UUID), `windowLabel` (String), `timestamp` (Date), `status` (enum: empty, raw, structured, skipped), `rawText` (String?), агрегированные `calories`, `proteins`, `fats`, `carbs` (Double, вычисляются из связанных `Ingredient`).

#### Scenario: Создание MealEvent с сырым текстом
- **WHEN** пользователь вводит текст «овсянка с ягодами» для слота «Завтрак»
- **THEN** создаётся запись `MealEvent` с `windowLabel = "Завтрак"`, `status = raw`, `rawText = "овсянка с ягодами"`, агрегированные поля = 0

#### Scenario: Обновление до structured после обработки
- **WHEN** LLM возвращает структурированные ингредиенты для `MealEvent` со статусом `raw`
- **THEN** статус меняется на `structured`, агрегированные поля пересчитываются из связанных `Ingredient`

### Requirement: Модель Ingredient
Система SHALL хранить ингредиенты приёма пищи в сущности `Ingredient` со связью many-to-one к `MealEvent`. Поля: `name` (String), `amount` (Double), `unit` (String), `calories`, `proteins`, `fats`, `carbs` (Double).

#### Scenario: Создание ингредиентов после LLM-структуризации
- **WHEN** LLM возвращает `[{name: "овсянка", amount: 100, unit: "г"}, {name: "ягоды", amount: 50, unit: "г"}]`
- **THEN** создаются две записи `Ingredient`, связанные с родительским `MealEvent`, БЖУ заполняются из справочника `FoodItem`

#### Scenario: Удаление MealEvent каскадно удаляет Ingredient
- **WHEN** пользователь удаляет приём пищи
- **THEN** все связанные `Ingredient`-записи также удаляются

### Requirement: Модель FoodItem
Система SHALL хранить справочник продуктов в сущности `FoodItem` с полями: `name` (String, уникальное), `category` (String), `calories`, `proteins`, `fats`, `carbs`, `fiber` (Double, на 100г).

#### Scenario: Seed-заполнение при первом запуске
- **WHEN** приложение запускается впервые
- **THEN** `ModelContainer` засевает `FoodItem`-таблицу данными из JSON-файла в бандле (500–1000 продуктов) с категориями: крупы, мясо, овощи, фрукты, молочка, напитки, полуфабрикаты

#### Scenario: Добавление пользовательского продукта
- **WHEN** пользователь добавляет новый продукт через интерфейс справочника
- **THEN** создаётся запись `FoodItem`, доступная для поиска и выбора

### Requirement: Модель MealTemplate
Система SHALL хранить пользовательские шаблоны приёмов пищи в сущности `MealTemplate` с полями: `name` (String) и связью one-to-many к `TemplateIngredient` (аналог `Ingredient`, но для шаблона).

#### Scenario: Сохранение шаблона из structured-события
- **WHEN** пользователь нажимает «Сохранить как шаблон» на зелёной карточке
- **THEN** создаётся `MealTemplate` с копией ингредиентов из `MealEvent`

### Requirement: Агрегация БЖУ
Система SHALL автоматически пересчитывать агрегированные поля `calories`, `proteins`, `fats`, `carbs` в `MealEvent` при любом изменении связанных `Ingredient`.

#### Scenario: Пересчёт при добавлении ингредиента
- **WHEN** к `MealEvent` добавляется новый `Ingredient`
- **THEN** агрегированные поля родительского `MealEvent` обновляются как сумма всех связанных ингредиентов

### Requirement: Хранение окна питания
Система SHALL хранить настройки окон питания в сущности `MealWindow` с полями: `name` (String), `startTime` (DateComponents), `endTime` (DateComponents), `order` (Int). До 6 окон.

#### Scenario: Настройка окон в onboarding
- **WHEN** пользователь завершает onboarding
- **THEN** создаются 3 стандартных окна: Завтрак (7:00–10:00), Обед (12:00–15:00), Ужин (18:00–21:00)

#### Scenario: Удаление окна не удаляет события
- **WHEN** пользователь удаляет окно «Перекус», для которого существуют `MealEvent` с `windowLabel = "Перекус"`
- **THEN** окно удаляется, но `MealEvent` сохраняются в БД. При создании нового окна с тем же названием старые события снова отображаются на дашборде

### Requirement: Модель DailyAdvice
Система SHALL хранить историю советов дня в сущности `DailyAdvice` с полями: `date` (Date, уникальное на день), `adviceText` (String), `createdAt` (Date).

#### Scenario: Сохранение совета дня
- **WHEN** LLM возвращает совет дня
- **THEN** создаётся или обновляется `DailyAdvice` за текущую дату с текстом ответа LLM

#### Scenario: Просмотр истории советов
- **WHEN** пользователь открывает предыдущий совет дня
- **THEN** отображается сохранённый `adviceText` без повторного LLM-запроса

### Requirement: Модель Recommendation
Система SHALL хранить последнюю рекомендацию по питанию в сущности `Recommendation` с полями: `date` (Date), `recommendationText` (String), `createdAt` (Date). Одна рекомендация на день — перезаписывается при новом запросе.

#### Scenario: Сохранение рекомендации
- **WHEN** LLM возвращает рекомендацию на оставшиеся приёмы
- **THEN** создаётся или обновляется `Recommendation` за текущую дату

#### Scenario: Отображение рекомендации на слоте
- **WHEN** пользователь открывает вкладку «Рекомендация» на любом незаполненном слоте
- **THEN** отображается сохранённый `recommendationText`, если он есть за сегодня
