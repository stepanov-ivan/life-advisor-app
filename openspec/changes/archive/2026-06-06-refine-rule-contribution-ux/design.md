## Context

Текущий explainability UX правил питания раздвоен между `DayAnalyticsPanel`, `MealSlotCard` и отдельным экраном детали правила. Отдельный экран с недельным графиком даёт лишнюю навигацию и не отвечает на главный вопрос пользователя: какие именно продукты сформировали метрику правила за выбранный день. Одновременно текущая модель вкладов опирается на `RuleViolation.contributionJSON`, который смешивает доменную оценку нарушения с UI-данными, не покрывает правила в зоне `normal` и требует хрупкого парсинга JSON в UI.

Change затрагивает несколько слоёв сразу: модель оценки правил, локальное хранилище explainability-данных, `DayAnalyticsPanel`, `MealSlotCard` и tracing между правилом, продуктом и приёмом. Дополнительно change упрощает продуктовую модель зон, убирая `warning` из пользовательского поведения и оставляя бинарную схему `normal` / `violation`.

## Goals / Non-Goals

**Goals:**
- Сделать `DayAnalyticsPanel` главным explainability surface для дневных правил.
- Убрать drill-down в отдельный экран правила и заменить его inline-раскрытием правила.
- Показывать breakdown только для дневных `range` и `presence` правил.
- Хранить дневной explainability read model отдельно от `RuleViolation`.
- Удалить зависимость UI от `contributionJSON` и перевести tracing на связанные SwiftData-сущности.
- Сохранить product-level highlighting в `MealSlotCard`, но ограничить его только нарушенными правилами и вкладом >20%.
- Упростить оценку правил до бинарной модели `normal` / `violation` / `no_data`.

**Non-Goals:**
- Не возвращать недельный график или альтернативный экран детали правила.
- Не поддерживать breakdown для недельных правил в `DayAnalyticsPanel`.
- Не строить explainability для правил `countSkipped` и других недневных behavioral правил в этой панели.
- Не делать отдельную миграцию данных; старые warning-based и JSON-based данные исчезают при обычном пересчёте.
- Не добавлять новый навигационный surface вместо удаляемого экрана правила.

## Decisions

### 1. `DayAnalyticsPanel` становится единственным местом rule contribution breakdown
`DayAnalyticsPanel` показывает только дневные правила, у которых есть честно вычислимый product contribution. Тап по строке правила не ведёт в другой экран, а раскрывает inline-block под этим правилом. Одновременно раскрыто может быть только одно правило, чтобы панель оставалась компактной.

**Почему так:** это сокращает navigation hop и делает объяснение нарушения доступным в том же месте, где пользователь уже видит summary за день.

**Альтернативы:**
- Сохранять отдельный `RuleDetailView` — отвергнуто, потому что экран уже багован и не решает explainability задачу.
- Делать breakdown ещё и в `RulesListView` — отвергнуто ради ограничения scope.

### 2. Отдельная persisted read model для explainability
Вместо расширения `RuleViolation` вводятся две новые SwiftData-сущности:
- `RuleContributionSnapshot` — снимок дневного состояния правила
- `RuleContributionItem` — вклад конкретного продукта в метрику правила

`RuleContributionSnapshot` хранит `ruleId`, `date`, `zone`, текущее значение метрики, человекочитаемую норму и связанные items. `RuleContributionItem` хранит ссылки на `MealEvent` и `EstimateItem`, display name продукта, absolute contribution, percent contribution и day-order index.

**Почему так:** breakdown нужен и для `normal` правил, а `RuleViolation` по смыслу должен оставаться моделью факта нарушения. Отдельный read model позволяет UI читать готовые explainability-данные без доменного пересчёта и без JSON parsing.

**Альтернативы:**
- Расширить `RuleViolation` до normal-case — отвергнуто, потому что смешивает разные сущности.
- Считать breakdown на лету — отвергнуто, потому что это размазывает бизнес-логику по UI.

### 3. `contributionJSON` удаляется полностью
Новая модель snapshot/item заменяет `RuleViolation.contributionJSON`. Все текущие потребители tracing должны перейти на связи через `RuleContributionItem`.

**Почему так:** это убирает dual source of truth и делает explainability-данные типизированными и queryable.

**Альтернативы:**
- Держать JSON и новые сущности параллельно — отвергнуто из-за риска расхождений.

### 4. Бинарная модель оценки правил
Из пользовательского поведения убирается `warning`. `approaching_upper`, `approaching_lower` и `some_skips` больше не создают отдельную зону; до фактического нарушения правило считается `normal`. Визуальная палитра rule-zone контекста после этого использует только `normal`, `violation` и `no_data`.

**Почему так:** текущая warning-логика усложняет UI, продуктово воспринимается неочевидно и конфликтует с новой explainability-моделью.

**Альтернативы:**
- Оставить warning только для части правил — отвергнуто как лишний special-case.

### 5. Разделение ролей `DayAnalyticsPanel` и `MealSlotCard`
- `DayAnalyticsPanel` показывает breakdown правила всегда, если rule type поддерживается и правило дневное.
- `MealSlotCard` больше не показывает summary нарушений на уровне приёма. Вместо этого она подсвечивает только продукты, чей вклад >20% в нарушенное правило, где продукт является culprit для направления нарушения, и при раскрытии продукта показывает все такие нарушенные правила.

Иными словами, breakdown правила и product highlighting используют разные критерии:
- breakdown в `DayAnalyticsPanel` показывает contributors, то есть все продукты, из которых складывается метрика правила;
- highlighting в `MealSlotCard` показывает только culprits, то есть продукты, которые толкают правило в сторону нарушения.

Для deфицитных нарушений вроде `below_lower` и `category_missing` продукты SHALL участвовать в breakdown правила, но SHALL NOT подсвечиваться в карточке приёма, даже если их вклад в текущую метрику больше 20%.

**Почему так:** правило объясняется на уровне правила, а карточка приёма остаётся быстрым локальным сигналом по продукту.

**Альтернативы:**
- Оставить rule-summary в карточке приёма — отвергнуто как дублирование.
- Убрать раскрытие продукта полностью — отвергнуто, потому что пользователь хочет видеть все затронутые правила для конкретного продукта.

### 6. Формат отображения вкладов
- Для gram/mass/category правил: `11 г (37%)`
- Для percent-based правил: только абсолютное значение метрики, например `4.8%`
- В `DayAnalyticsPanel` внутри раскрытия показываются top-3 продукта по убыванию вклада, затем `Ещё X продуктов` / `Свернуть`.
- В `MealSlotCard` правила под продуктом сортируются по убыванию вклада продукта в каждое правило и используют тот же формат отображения.

**Почему так:** абсолютное значение даёт человеку основной смысл, процент — контекст доли. Для percent rules второй процент только путает.

### 7. Новая точка truth для meal-level tracing
`RuleEngine.violationsForMeal(_:)` и product highlighting в `MealSlotCard` должны работать через связи `RuleContributionItem.mealEvent` и `RuleContributionItem.estimateItem`, а не через разбор `contributionJSON`.

**Почему так:** новая модель already хранит прямые связи и позволяет избежать ручного сопоставления `itemId`.

## Risks / Trade-offs

- **[Риск] Удаление warning может поломать существующие тесты и UX-ожидания** → пересобрать specs и unit tests под бинарную модель, явно удалить warning-сценарии.
- **[Риск] Удаление `contributionJSON` затрагивает несколько мест сразу** → переводить все потребители на snapshot/item в одном change, без промежуточного dual mode.
- **[Риск] Persisted explainability read model может устаревать при частичном редактировании дня** → пересчитывать snapshots в том же цикле, что и дневную rule evaluation.
- **[Риск] `DayAnalyticsPanel` станет длинной при большом числе продуктов** → single-expanded rule, top-3 + explicit reveal для хвоста.
- **[Риск] Presence rules и percent rules могут требовать разной математики вклада** → зафиксировать две отдельные contribution formula families в specs и в tests.

## Migration Plan

1. Добавить новые SwiftData-сущности `RuleContributionSnapshot` и `RuleContributionItem`.
2. Перевести расчёт дневных правил на генерацию snapshots одновременно с оценкой дня.
3. Удалить генерацию и чтение `contributionJSON`.
4. Перевести `DayAnalyticsPanel` на snapshots и inline expansion.
5. Перевести `MealSlotCard` на product highlighting по contribution items.
6. Удалить entry points в `RuleDetailView` и убрать экран из пользовательского сценария.
7. Обновить тесты под бинарную модель `normal` / `violation`.

Rollback не проектируется как отдельный runtime-механизм; change рассчитан на локальную разработку без публичного релиза и может быть откатан на уровне git.

## Open Questions

- Нет открытых продуктовых вопросов; scope и interaction model для change согласованы.
