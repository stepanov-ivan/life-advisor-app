# Changelog

All notable changes to this project will be documented in this file.

The format is inspired by Keep a Changelog, adapted for the current early-stage repository.

## [Unreleased]

- Ongoing stabilization and release follow-up work after `v0.1.0`.

## [0.1.0] - 2026-06-06

First public open-source baseline release focused on a usable product demo, clearer nutrition explainability, stronger repository presentation, and contributor readiness.

### Added

- stronger public README with product overview, architecture, and setup guidance
- contributing, security, and code-of-conduct documents
- GitHub issue templates, PR template, and iOS CI workflow
- roadmap, release checklist, and first release notes documentation
- inline daily rule contribution breakdowns in the dashboard
- persisted daily rule contribution snapshots and per-item tracing for explainability
- English and Russian localization across the main product flows

### Changed

- simplified rule evaluation UX around daily nutrition feedback
- replaced rule drill-down flow with inline dashboard explainability
- refined meal-card highlighting to focus on culprit-style violations
- lowered culprit highlighting threshold from 30% to 20% for better multi-product detection
- improved README and OSS presentation for public review
- removed the blocking changed-files coverage gate from CI while keeping automated tests

### Fixed

- stale nutrition rules after `Re-estimate from text`
- localization leaks such as Russian `ккал` in English UI
- incorrect product highlighting for deficit-style rules
- simulator selection fragility in iOS GitHub Actions runs
- floating-point-sensitive rule-engine test behavior in CI
