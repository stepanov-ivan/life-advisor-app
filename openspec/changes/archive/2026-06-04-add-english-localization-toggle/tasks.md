## 1. Ядро языка приложения

- [x] 1.1 Ввести `AppLanguage` и `AppLanguageManager` с поддержкой режимов `system`, `en`, `ru`, восстановлением сохранённого override и вычислением effective language
- [x] 1.2 Подключить effective locale к корню SwiftUI-приложения через `environment(\.locale, ...)`
- [x] 1.3 Добавить тонкий localization helper с поддержкой таблиц `Localizable`, `Rules`, `Prompts` и English fallback
- [x] 1.4 Добавить и локализовать выбор языка `System / English / Русский` в настройках приложения

## 2. Системные окна питания и уведомления

- [x] 2.1 Перевести системные meal windows на stable ids вместо зависимости от display names
- [x] 2.2 Локализовать display labels meal windows через `Localizable` и обновить onboarding/settings/dashboard для работы с ними
- [x] 2.3 Обновить `NotificationManager`, чтобы payload и pending state использовали stable meal window ids, а тексты уведомлений и actions локализовались на активном языке

## 3. Локализация UI и форматирования

- [x] 3.1 Вынести user-facing hardcoded строки из основных SwiftUI-экранов в `Localizable`
- [x] 3.2 Локализовать accessibility labels/hints/values на основных пользовательских экранах
- [x] 3.3 Обновить форматирование дат, чисел, процентов и единиц на locale-aware presentation с использованием effective language

## 4. Rules presentation

- [x] 4.1 Убрать display copy из `RuleDefinition` и rule config, сохранив rules language-agnostic
- [x] 4.2 Реализовать `RulePresentationMapper` для преобразования `RuleViolation` и rule data в typed presentation model
- [x] 4.3 Реализовать `RulePresentationLocalizer` для titles, descriptions, category labels, section titles и violation explanations через таблицу `Rules`
- [x] 4.4 Реализовать `RuleGroupingPolicy` / `RuleSectionBuilder` для `RulesListView` и `DayAnalyticsPanel` на stable ids
- [x] 4.5 Обновить rule-related views и сервисы на использование нового rule presentation stack вместо жёстко зашитых строк и grouping по display text

## 5. LLM prompts и user-facing ошибки

- [x] 5.1 Реализовать `PromptBuilder`, который принимает `AppLanguage` и собирает prompt из общего skeleton и локализуемых fragments таблицы `Prompts`
- [x] 5.2 Обновить `LLMClient`, чтобы он получал готовый prompt и не собирал product copy самостоятельно
- [x] 5.3 Вынести user-facing LLM error text в presentation layer и локализовать его через стандартный localization stack
- [x] 5.4 Убедиться, что новый LLM-сгенерированный пользовательский контент запрашивается на активном языке приложения

## 6. Хранилище переводов и документация

- [x] 6.1 Создать и заполнить `ru`/`en` localization resources для `Localizable`, `Rules` и `Prompts`
- [x] 6.2 Обновить документацию для разработчиков о правилах добавления новых локализуемых строк, fallback и запрете логики на display text

## 7. Проверки и валидация

- [x] 7.1 Добавить automated tests на полноту локализаций для `Localizable`, `Rules` и `Prompts`
- [x] 7.2 Добавить tests для `AppLanguageManager` на override, effective language и English fallback behavior
- [x] 7.3 Добавить/обновить deterministic tests для нового rule presentation и prompt/error presentation seams, где это нужно
- [x] 7.4 Прогнать релевантные тесты и проверить основные пользовательские сценарии `ru/en` перед открытием публичного переключателя языка
