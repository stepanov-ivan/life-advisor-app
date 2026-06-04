## Context

Сейчас приложение использует русскоязычные user-facing строки прямо в SwiftUI views, сервисах, уведомлениях, presentation-слое nutrition rules и частично в LLM-related тексте. В проекте нет централизованного слоя управления языком приложения, нет стандартной структуры localization resources для разных доменных зон и нет автоматической проверки полноты переводов.

Change затрагивает несколько слоёв одновременно:
- SwiftUI UI и настройки приложения
- non-UI сервисы, которые формируют пользовательский текст
- presentation-слой nutrition rules и explanations
- prompt templates и язык нового LLM-контента
- форматирование дат, чисел и единиц
- developer workflow и CI-проверки локализаций

При этом продукт должен сохранить текущую логику и данные: локализация меняет способ отображения и язык нового системно-сгенерированного/LLM-контента, но не переписывает уже сохранённую пользовательскую историю.

По текущему коду уже видны несколько конкретных seam’ов, которые дизайн обязан закрыть:
- `NotificationManager` кладёт `window.name` в `userInfo` уведомлений и затем использует его в pending state, что создаёт зависимость логики от локализуемого текста.
- `RuleDefinition` и `nutrition_rules.json` смешивают rule logic и display copy через поля `title` и `description`.
- `RuleEngine.violationDescription` и `russianCategoryName` собирают пользовательские описания нарушений прямо в доменном слое.
- `RulesListView` и `DayAnalyticsPanel` группируют правила по русским display titles, а не по stable category ids.
- `LLMClient` содержит user-facing error text прямо в error presentation logic.

Основное ограничение: локализация должна строиться на стандартном Apple stack, без отдельного custom localization framework. Английский становится базовым языком продукта и fallback-языком для отсутствующих переводов.

## Goals / Non-Goals

**Goals:**
- Ввести полноценную локализацию продукта для `ru` и `en` с единым источником истины для effective app language.
- Поддержать режим `System / English / Русский` с сохранением пользовательского override между запусками.
- Обеспечить live-update интерфейса без перезапуска через централизованное пробрасывание locale в SwiftUI.
- Вынести все user-facing hardcoded строки в стандартные localization resources.
- Разделить локализационные ресурсы по зонам ответственности: общий UI, nutrition rules presentation и prompt templates.
- Обеспечить, чтобы notifications, user-facing errors, rule explanations и новый LLM-контент следовали выбранному языку приложения.
- Локализовать accessibility labels/hints и форматирование дат, чисел, процентов и единиц.
- Защитить поведение от зависимости на display text: бизнес-логика должна опираться на stable ids, а не на локализуемые строки.
- Добавить автоматическую проверку полноты локализаций и тесты централизованного language-selection/fallback поведения.
- Обновить developer-facing документацию по правилам добавления новых локализуемых строк.

**Non-Goals:**
- Перевод уже сохранённого пользовательского или исторического контента.
- Data migration ради замены старых русских строк в persistent data.
- Создание отдельного custom localization framework.
- Проектирование системы под произвольное число языков сверх `ru` и `en`.
- Добавление публичного переключателя до готовности реальной локализации продукта.
- Создание отдельной пользовательской настройки языка только для LLM.
- Полные end-to-end тесты качества всех ответов LLM.
- Локализация debug-only и developer-only строк.

## Decisions

### 1. Единый источник истины: `AppLanguageManager`

В приложении вводится отдельный слой `AppLanguageManager` (или близкое по смыслу имя), который отвечает за:
- хранение пользовательского выбора (`system`, `en`, `ru`)
- вычисление effective language на основе системной локали и override
- определение fallback policy
- предоставление текущего `Locale` для UI
- предоставление текущего `AppLanguage` для non-UI кода

Почему так:
- язык влияет не только на `SettingsView`, но и на всё приложение
- singleton-less централизованная модель проще тестируется и не размазывает состояние
- это даёт одну точку правды для UI, notifications, rules и prompts

Альтернативы:
- держать логику в `SettingsViewModel` — отклонено, потому что язык влияет на всю систему, а не только на экран настроек
- использовать `@AppStorage` в нескольких местах без отдельного слоя — отклонено, потому что логика effective language и fallback быстро разъедется

### 2. Хранение выбора языка в `UserDefaults` / `@AppStorage`

Пользовательский выбор языка хранится как app preference, а не как доменные данные. В storage сохраняется именно override (`system`, `en`, `ru`), а не вычисленный effective language.

Почему так:
- это нативный и минимальный путь для пользовательских настроек
- не требует тянуть локализацию в SwiftData models
- сохраняет прозрачную модель поведения

Альтернативы:
- `SwiftData` — отклонено как избыточное решение для простой app preference
- собственный persistent config layer — отложено как ненужное усложнение

### 3. SwiftUI получает язык через `environment(\.locale, ...)`

На корне приложения effective locale пробрасывается в SwiftUI environment. Это позволяет главным экранам и локализуемым `Text`/format styles обновляться на лету при смене языка.

Почему так:
- это стандартный SwiftUI-механизм
- обеспечивает live-update без ручной передачи locale по всему дереву
- помогает автоматически подтянуть локализованное форматирование там, где используются стандартные API

Альтернативы:
- ручная передача locale по view tree — отклонено как шумное и хрупкое решение
- чтение language manager прямо из каждого view/service — отклонено как сильная связность и риск несогласованного поведения

### 4. Non-UI код получает язык явно

Сервисы, notifications, rule presentation и prompt generation не должны скрыто вытягивать язык из глобального состояния. Если код формирует user-facing текст вне SwiftUI view, он должен принимать `AppLanguage` или локализатор, уже связанный с `AppLanguage`.

Почему так:
- меньше скрытой магии
- проще писать deterministic tests
- легче гарантировать правильный язык в асинхронном и фоновом коде

Альтернативы:
- глобальный singleton language manager внутри сервисов — отклонено как менее тестируемый и менее явный подход

Практическое следствие:
- `NotificationManager` не должен хранить или передавать display labels как идентификаторы.
- `PromptBuilder`, `RulePresentationLocalizer` и error presenters получают язык явно через `AppLanguage`.

### 5. Стандартный Apple localization stack + тонкий helper

Основной механизм локализации строится на стандартных Apple resources (`.xcstrings`/`strings` tables и стандартные localization API). Поверх него допускается тонкий helper для:
- выбора нужной таблицы
- English fallback
- единообразной работы с форматируемыми строками

Почему так:
- сохраняется нативный путь без собственного framework
- меньше размазывания table names и fallback-политики по коду
- остаётся совместимость с платформенными инструментами

Альтернативы:
- использовать только прямые вызовы `String(localized:)` везде — отклонено, потому что table/fallback policy начнут дублироваться
- писать собственный registry/framework — отклонено как лишний техдолг

### 6. Разделение локализационных таблиц по предметным зонам

Локализационные ресурсы делятся минимум на три доменные таблицы:
- `Localizable` — общий UI и системный user-facing текст приложения
- `Rules` — nutrition rules presentation: titles, descriptions, category labels, violation reasons, explanation fragments
- `Prompts` — prompt templates и model-facing текстовые фрагменты

Почему так:
- UI, доменная nutrition copy и prompt copy имеют разные циклы изменения
- проще поддерживать и ревьюить переводы по зонам ответственности
- ниже риск смешивания продуктовых строк и model instructions

Альтернативы:
- хранить всё в одной таблице — отклонено, потому что rules/prompts быстро засорят общий каталог
- делать отдельные JSON-файлы правил на язык — отклонено, потому что rule logic и display copy не должны смешиваться

### 7. Rules остаются language-agnostic, локализуется presentation layer

Stable rule ids, category ids и внутренняя логика rule engine остаются язык-независимыми. Пользовательские `title`/`description`/`reason labels` поставляются через локализационный companion layer, привязанный к stable ids.

Почему так:
- локализация не должна влиять на логику правил
- это устраняет риск поломки поведения при переводе display text
- проще поддерживать rule engine и тесты

Альтернативы:
- хранить локализованные titles/descriptions прямо в rule config — отклонено как смешение логики и presentation
- дублировать rules config по языкам — отклонено как риск расхождения логики

Практическое следствие:
- `title` и `description` перестают быть источником истины в `RuleDefinition`/`nutrition_rules.json`.
- `RuleDefinition.categoryTitle` удаляется как presentation-aware свойство модели.
- grouping, section titles и human-readable rule copy не должны собираться из модели правила напрямую.

### 8. Для rules вводится отдельный presentation stack

Rules presentation строится отдельным набором маленьких слоёв:
- `RulePresentationMapper` — преобразует `RuleViolation`, `RuleDefinition` и related domain facts в typed presentation model
- `RulePresentationLocalizer` — превращает presentation model, rule ids и category ids в локализованный user-facing text
- `RuleGroupingPolicy` / `RuleSectionBuilder` — раскладывает правила по секциям для конкретных UI surface’ов

Почему так:
- rules используются в нескольких поверхностях: список правил, day analytics, detail screen, meal-level violations
- domain слой не должен собирать финальные строки
- grouping и localization связаны, но не должны жить в одном комбайне

Альтернативы:
- собирать строки прямо в `RuleEngine` — отклонено, потому что это смешивает доменную логику и presentation
- локализовать всё в view — отклонено, потому что ключи и grouping policy быстро размажутся по коду
- делать один “универсальный” presenter на всё — отклонено, потому что rules, prompts и error presentation имеют разные обязанности

### 9. `RuleEngine` больше не возвращает готовые violation strings

Вместо `violationDescription(for:) -> String` rule-related presentation должен опираться на structured typed model. `RuleEngine` продолжает отвечать за evaluation/persistence, а presentation model собирается mapper’ом.

Почему так:
- typed cases лучше переживают локализацию, форматирование и разные UI surface’ы
- это позволяет тестировать mapping `reasonCode -> presentation case` отдельно от рендера текста
- доменный слой перестаёт знать про русские/английские шаблоны предложений

Альтернативы:
- оставить `String` и просто локализовать шаблоны внутри `RuleEngine` — отклонено как слабая separation
- вернуть localization key + args прямо из доменного слоя — отклонено, потому что ключи локализации тоже относятся к presentation

### 10. Английский — канонический fallback-язык

Английский становится базовым языком продукта. Если перевод ключа отсутствует, пользователь получает английский текст, а не смешанный системный fallback.

Почему так:
- English-friendly OSS surface лучше для публичного репозитория, ревью и демо
- поведение становится предсказуемым
- это снимает риск частичного русского fallback в англоязычном интерфейсе

Практическое следствие:
- completeness tests должны ловить отсутствие переводов
- fallback остаётся safety net, а не заменой полноте локализации

### 11. Новый LLM-контент и prompts подчиняются выбранному языку приложения

UI-язык, notifications и LLM language behavior синхронизируются через один effective app language. Prompt templates локализуются отдельно в таблице `Prompts`, а новый контент генерируется на активном языке.

Почему так:
- иначе пользователь получит английский интерфейс и русские советы модели
- это согласуется с общей моделью “один язык приложения”
- поддержка prompt copy отдельно упрощает ревью и развитие prompting

Ограничение:
- уже сохранённый исторический LLM-контент не перегенерируется и не переводится задним числом

Практическое следствие:
- вводится отдельный `PromptBuilder`, который принимает `AppLanguage` и собирает итоговый prompt из общего skeleton и локализуемых фрагментов
- `LLMClient` получает уже готовый prompt и не занимается product copy assembly
- user-facing error text убирается из `LLMClient` error types и переезжает в отдельный error presentation слой

### 12. Новые системно-создаваемые данные следуют текущему языку, старые не мигрируются

Любой новый системно-создаваемый user-visible контент (например, дефолтные meal windows) должен создаваться на текущем effective language. Уже существующие записи не переписываются.

Почему так:
- это даёт консистентное поведение для новых установок и новых сущностей
- не требует data migration
- согласуется с правилом не трогать историю и пользовательские данные

Практическое следствие:
- fixed meal windows переводятся на stable ids / enum-like identifiers
- display labels meal windows живут в `Localizable`
- notification payload и pending state используют stable meal window ids, а не display names

### 13. Accessibility и formatting входят в ту же definition of localization

Полноценная локализация включает:
- `accessibilityLabel` / `accessibilityHint` / `accessibilityValue`
- форматирование дат, чисел, процентов, единиц и related locale-sensitive presentation

Почему так:
- это часть user-facing experience
- иначе UI будет переведён лишь частично
- `environment(\.locale, ...)` и стандартные formatters уже дают для этого естественную базу

### 14. Проверки качества: completeness tests + manager behavior tests

Автоматическая защита change строится на двух уровнях:
- тесты полноты локализаций по таблицам (`Localizable`, `Rules`, `Prompts`) для поддерживаемых языков
- тесты централизованного language manager, проверяющие override, effective language и English fallback behavior

Почему так:
- это ловит отсутствующие переводы и регрессии в основном механизме
- нет необходимости плодить UI-тесты на переключение каждого экрана, если механизм централизован

Альтернативы:
- только ручная проверка — отклонено как слишком хрупко
- широкие end-to-end LLM tests — отклонено как чрезмерно нестабильные для этого scope

## Risks / Trade-offs

- **[Риск] Скрытые зависимости логики от русских display-строк** → Провести аудит мест, где сравнения или branching могут опираться на user-facing text; заменить такие зависимости stable ids.
- **[Риск] Локализация rules окажется неполной из-за смешения domain и presentation слоёв** → Удалить display copy из `RuleDefinition`, вынести rule presentation в mapper/localizer/grouping stack и использовать stable rule/category ids на всех UI surface’ах.
- **[Риск] Неполное покрытие hardcoded строк и смешанный RU/EN интерфейс** → Вынести все user-facing строки централизованно и добавить completeness tests по таблицам.
- **[Риск] Часть non-UI текста останется на старом языке из-за неявных вызовов** → Требовать явную передачу `AppLanguage` или локализатора в сервисы, notifications и prompt generation.
- **[Риск] Смена языка затронет formatting и приведёт к визуальным регрессиям** → Использовать стандартные locale-aware formatting APIs и вручную проверить ключевые экраны dashboard/analytics/settings.
- **[Риск] Разрастание scope из-за “почти локализованных” хвостов** → Держать публичный переключатель скрытым до финальной готовности и явно документировать остатки, если они останутся.
- **[Риск] Дублирование смыслов между `Localizable`, `Rules` и `Prompts`** → Зафиксировать зоны ответственности таблиц в документации и придерживаться их при добавлении новых строк.
- **[Риск] Старые сервисы продолжат сохранять или передавать display text как идентификатор** → Аудитировать notifications, fixed meal windows и rule grouping paths; там, где есть user-facing text в payload/state, заменить его stable ids.

## Migration Plan

Поскольку публичного релиза ещё не было, отдельная data migration не требуется.

План внедрения:
1. Ввести `AppLanguageManager`, тип языка и хранение override в app preferences.
2. Подключить effective locale к корню SwiftUI-приложения и подготовить settings UI для выбора `System / English / Русский`.
3. Создать localization resources и разделить строки по таблицам `Localizable`, `Rules`, `Prompts`.
4. Перевести fixed meal windows на stable ids и убрать использование display names в notification payload/state.
5. Вынести hardcoded user-facing строки из UI и сервисов.
6. Убрать display copy из rule config/model и ввести `RulePresentationMapper`, `RulePresentationLocalizer` и `RuleGroupingPolicy`.
7. Перевести rule presentation, section titles и violation explanations на stable localization keys.
8. Ввести `PromptBuilder` и вынести user-facing LLM error text в presentation layer.
9. Обновить notifications, user-facing errors и formatting code на использование language context.
10. Добавить completeness tests и tests для language manager.
11. Обновить documentation.
12. Открыть публичный переключатель языка только после того, как локализация будет достаточно полной для основного продуктового пути.

Rollback strategy:
- если локализация окажется неполной, публичный переключатель можно временно не показывать, сохранив внутреннюю инфраструктуру и translations-in-progress
- если отдельные зоны (например prompts) будут нестабильны, их можно временно оставить на English, не ломая общую модель языка

## Open Questions

- Нужно проверить, есть ли в проекте дополнительные system-facing строки вне основного UI, которые не попали в текущий аудит исходников.
- После первого implementation pass нужно оценить, стоит ли дополнительно формализовать shared typing для localization keys, или текущего thin helper будет достаточно.
