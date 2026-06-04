# Life Advisor

An iOS app that helps you build healthy eating habits based on **WHO (World Health Organization)** nutrition recommendations.

## What it does

Life Advisor analyzes your meals and gives you real-time feedback on how well your diet aligns with WHO guidelines. It covers all key WHO recommendations — from macronutrient balance to food quality and meal regularity.

## WHO-based nutrition rules

The app tracks 16 WHO-aligned nutrition rules across four categories:

### Macronutrient balance (daily)
- **Protein** — 10–15% of daily energy
- **Total fat** — 15–30% of daily energy
- **Saturated fat** — ≤10% of daily energy
- **Trans fat** — ≤1% of daily energy
- **PUFA** — 6–10% of daily energy
- **Carbohydrates** — 45–75% of daily energy

### Restrictions
- **Free sugar** — ≤10% of daily energy
- **Sodium (salt)** — ≤2000 mg per day
- **Energy balance** — calorie surplus under control (weekly)
- **Fiber** — ≥25 g per day

### Food quality
- **Fruits & vegetables** — ≥400 g per day
- **Whole grains** — include daily
- **Legumes, nuts & seeds** — include daily
- **Red meat** — ≤500 g per week
- **Processed meat** — avoid

### Eating pattern
- **Meal regularity** — no skipped meals

## Key features

- **LLM-powered meal analysis** — describe meals in natural language, get structured nutritional estimates
- **Real-time rule feedback** — see which WHO rules pass or fail for every meal
- **Dashboard** — daily overview with nutrition compliance scores
- **Analytics** — track your trends over time
- **Smart check-ins** — periodic check-ins to stay on track
- **Rule details** — understand each WHO recommendation with descriptions and rationale
- **Food reference database** — look up nutritional values of common foods

## Tech stack

- **SwiftUI** — UI framework
- **SwiftData** — local persistence
- **LLM integration** — natural language meal parsing
- **Rule engine** — deterministic nutrition rule evaluation

## Project structure

```
LifeAdvisorApp/
├── App/                    # App entry point and content view
├── Models/                 # Data models (meal events, rules, violations)
├── Services/               # Business logic (rule engine, LLM client, memory)
├── Views/                  # UI screens (dashboard, analytics, settings)
└── Resources/              # Nutrition rules config, food database

## License

MIT — see [LICENSE](LICENSE)
```
