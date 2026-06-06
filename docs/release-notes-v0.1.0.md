# `v0.1.0` - Public OSS baseline

## What the app does

Life Advisor is an open-source iOS app for building healthier eating habits with feedback grounded in WHO nutrition guidance.

It combines:

- natural-language meal logging with an LLM-backed estimation flow
- deterministic nutrition rules for explainable evaluation
- dashboard and analytics views for daily feedback and trend review
- local-first storage with SwiftData

## Highlights in `v0.1.0`

- first public open-source baseline release
- stronger README, contributor docs, security docs, and release hygiene
- improved dashboard explainability with inline rule contribution breakdowns
- clearer meal-level culprit highlighting for products that materially drive violations
- English and Russian localization across the main user-facing flows
- more reliable meal editing, re-estimation, and nutrition-rule recomputation
- improved iOS CI reliability for simulator-based test runs

## Known limitations

- the app still depends on user-provided LLM credentials and endpoint configuration
- nutrition estimation quality depends on the source model and the clarity of meal text
- some deeper analytics and legacy rule-detail surfaces still need cleanup after the first public release
- localization has improved significantly, but edge-case UI copy may still need audit over time

## Where contributors can help next

- rule explainability and wording polish
- regression tests around meal editing and estimation correction flows
- nutrition-rule coverage and validation
- repeated-meal memory and suggestion quality
- public release polish, docs, and issue triage
