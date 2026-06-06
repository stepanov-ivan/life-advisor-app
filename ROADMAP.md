# Roadmap

This roadmap reflects the current public direction of Life Advisor as an open-source project.

## Near-term

### `v0.1.x` Stabilization after first public release

- keep tests green in CI after public release
- tighten regression coverage around meal editing and rule recomputation
- continue simplifying explainability UX where rule feedback is still confusing
- improve onboarding clarity for first-time users
- collect early contributor and reviewer feedback from the public release

### Explainability and trust

- continue improving rule rationale and contribution breakdown clarity
- refine manual correction and re-estimation flows based on real usage
- replace weak generic advice with grounded, actionable daily guidance
- add a read-only assistant surface for explaining meals, rules, and trends
- surface confidence and uncertainty more clearly in estimation flows
- strengthen malformed-response handling and recovery UX in LLM flows

## Mid-term

### Localization

- keep English and Russian as first-class supported languages
- continue auditing all user-facing strings for locale coverage
- improve localization coverage in edge-case editor, analytics, and settings flows

### Nutrition intelligence

- extend nutrition-rule coverage where guidance can remain explicit and testable
- improve repeated-meal memory and suggestion quality
- strengthen food-category inference and fallback behavior
- evolve the LLM from meal parser into a tool-based assistant over structured app data
- support assistant-driven actions such as meal correction, preference capture, and reminders

### Assistant UX

- introduce a high-signal assistant chat for grounded nutrition questions
- keep the assistant read-only before enabling state-changing actions
- explore proactive assistant entry points from strong rule or trend triggers
- avoid noisy generic advice in favor of explainable, contextual suggestions

### Contributor experience

- add more contributor-friendly issues
- improve docs for app setup, testing, and release workflow
- publish a clearer release cadence

## Longer-term

### Reusable open-source value

- document the hybrid LLM-plus-rules architecture as a reusable pattern
- make core nutrition evaluation logic easier to study independently
- improve the repository as a reference implementation for explainable health tooling

## Contribution notes

If you want to help, the best starting points are documentation, tests, rule explainability, localization, and UX improvements for meal correction flows.
