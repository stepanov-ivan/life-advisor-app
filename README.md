# Life Advisor

Life Advisor is an open-source iOS app for building healthier eating habits with feedback grounded in WHO nutrition guidance.

It combines deterministic nutrition rules with LLM-assisted meal parsing so users can log meals in natural language, review structured estimates, and understand how their eating pattern aligns with evidence-based recommendations.

## Screenshots and demo

Screenshots and a short demo are planned for the first public release.

Recommended showcase assets for grant and repository review:

- onboarding flow with LLM setup
- dashboard with meal slots and nutrition feedback
- analytics view with calorie and macro trends
- rules view with explainable WHO-aligned checks
- short demo video of meal logging to rule feedback

The current UI is primarily Russian-first. English localization is planned so the project can be reviewed more easily by non-Russian-speaking contributors and grant reviewers.

## Why this project matters

- Nutrition apps often optimize for calorie counting, not dietary quality.
- WHO recommendations are public, useful, and hard to operationalize in everyday meal logging.
- Life Advisor turns those guidelines into explainable, testable product behavior instead of opaque wellness scoring.
- The project is designed to explore a practical pattern for hybrid health tooling: LLMs for input understanding, rules for transparent evaluation.

## Current capabilities

- Natural-language meal logging with an LLM-backed nutrition estimation flow
- Rule engine for WHO-aligned nutrition checks
- Daily and weekly rule evaluation across macronutrients, food quality, and eating regularity
- Analytics and dashboard views for trend tracking
- Local persistence with SwiftData
- Memory and suggestion mechanisms for repeated meals
- Contract and rule-engine tests for core behavior

## WHO-aligned rules covered

The app currently tracks 16 nutrition rules across four areas:

### Macronutrient balance

- Protein: 10-15% of daily energy
- Total fat: 15-30% of daily energy
- Saturated fat: <=10% of daily energy
- Trans fat: <=1% of daily energy
- PUFA: 6-10% of daily energy
- Carbohydrates: 45-75% of daily energy

### Restrictions

- Free sugar: <=10% of daily energy
- Sodium: <=2000 mg per day
- Energy balance: weekly surplus under control
- Fiber: >=25 g per day

### Food quality

- Fruits and vegetables: >=400 g per day
- Whole grains: include daily
- Legumes, nuts, and seeds: include daily
- Red meat: <=500 g per week
- Processed meat: avoid

### Eating pattern

- Meal regularity: avoid skipped meals

## Architecture

`LifeAdvisorApp/LifeAdvisorApp/`

- `App/`: app entry point and bootstrap
- `Models/`: SwiftData models and domain entities
- `Services/`: rule engine, LLM client, memory logic, notifications
- `Views/`: dashboard, analytics, onboarding, settings, rule details
- `Resources/`: JSON nutrition rules and food reference data

The core design principle is simple:

1. The LLM converts messy meal text into structured nutrition estimates.
2. The app validates and stores the result locally.
3. The rule engine evaluates the structured data against explicit nutrition rules.
4. The UI shows both outcomes and rationale.

## Reusable open-source building blocks

This repository is not only an end-user app. It also explores reusable patterns that may be valuable to other open-source teams building health, nutrition, and explainable AI products:

- deterministic rule evaluation layered on top of LLM-derived structured input
- validation and contract testing for model output before product logic consumes it
- local-first storage for sensitive user nutrition data
- explainable violation tracing instead of opaque wellness scoring
- maintainable hybrid architecture where probabilistic parsing feeds explicit rules

## Getting started

### Requirements

- macOS with Xcode
- iOS Simulator or physical iPhone
- An LLM provider endpoint, model name, and API key

### Run locally

1. Open `LifeAdvisorApp/LifeAdvisorApp.xcodeproj` in Xcode.
2. Select the `LifeAdvisorApp` scheme.
3. Run the app on an iOS Simulator.
4. On first launch, enter:
   - endpoint, for example `https://api.openai.com/v1`
   - API key
   - model name, for example `gpt-4o-mini`

The app stores the API key in the Keychain and keeps app data locally with SwiftData.

## Running tests

Use Xcode's test action for the `LifeAdvisorApp` scheme, or run:

```bash
xcodebuild test \
  -project LifeAdvisorApp/LifeAdvisorApp.xcodeproj \
  -scheme LifeAdvisorApp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project status

This repository is actively evolving. The current focus is:

- improving nutrition rule clarity and explainability
- strengthening estimation validation and failure handling
- making meal memory and repeated-entry flows more reliable
- growing the testing and release discipline around the core engine

See `ROADMAP.md` for planned milestones and `CHANGELOG.md` for public project history.

## Release status

The project is currently pre-release.

The intended first public milestone is:

- `v0.1.0`: stable open-source showcase release with documented setup, passing tests, cleaner public repository surface, and English-localization groundwork

## Open source priorities

Areas where outside contributions are especially helpful:

- nutrition rule coverage and validation
- UX for manual correction of LLM estimates
- multilingual nutrition logging
- privacy-preserving health UX patterns
- CI, release engineering, and documentation

See `CONTRIBUTING.md` for contribution guidelines.

## Maintainer use of Codex and API credits

This project is a strong fit for Codex for OSS because Codex can help with recurring maintainer work around:

- triaging issues and turning bug reports into reproducible test cases
- generating regression tests for nutrition rules and parsing contracts
- reviewing pull requests for rule coverage and edge cases
- maintaining docs, templates, and release notes
- automating safe refactors in the rule engine and supporting services

## Repository hygiene notes

- License: MIT
- Tests: included for rule evaluation and LLM contract validation
- Security policy: see `SECURITY.md`
- Contribution guide: see `CONTRIBUTING.md`
- Code of conduct: see `CODE_OF_CONDUCT.md`
- Roadmap: see `ROADMAP.md`
- Changelog: see `CHANGELOG.md`
- Release prep: see `docs/release-checklist.md`

## License

MIT. See `LICENSE`.
