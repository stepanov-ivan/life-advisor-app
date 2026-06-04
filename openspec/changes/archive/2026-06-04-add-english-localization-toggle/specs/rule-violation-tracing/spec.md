## MODIFIED Requirements

### Requirement: Трейсинг цепочки нарушения
Система SHALL предоставлять drill-down от правила через день и приём до конкретного ингредиента с указанием structured presentation case, причины и величины отклонения. Пользовательское описание нарушения SHALL строиться вне доменного слоя и локализоваться на активном языке приложения.

#### Scenario: Раскрытие нарушения до ингредиента на английском языке
- **WHEN** effective language приложения английский и пользователь открывает нарушение правила на экране детали правила
- **THEN** система строит drill-down через stable rule ids и reason codes, а пользовательский explanation text отображается на английском языке через presentation layer

#### Scenario: Нарушение дня без конкретного ингредиента
- **WHEN** нарушение не привязано к конкретному ингредиенту
- **THEN** drill-down останавливается на уровне приёма или дня, а explanation text всё равно формируется через локализованный presentation layer

## ADDED Requirements

### Requirement: Presentation нарушений отделено от `RuleEngine`
Система SHALL преобразовывать `RuleViolation` и связанные данные правила в typed presentation model до локализации пользовательского explanation text.

#### Scenario: Range-нарушение преобразуется в presentation model
- **WHEN** нарушение имеет `reasonCode = "exceeds_upper"` и связано с range-правилом
- **THEN** presentation layer получает typed case для range deviation с данными о правиле, текущем значении и пороге вместо готовой пользовательской строки

#### Scenario: Presence-нарушение преобразуется в presentation model
- **WHEN** нарушение имеет `reasonCode = "category_missing"`
- **THEN** presentation layer получает typed case с stable category id вместо заранее собранного текста на конкретном языке
