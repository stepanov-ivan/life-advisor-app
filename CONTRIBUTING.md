# Contributing to Life Advisor

Thanks for your interest in contributing.

## Best ways to help

- report bugs with clear reproduction steps
- improve README and user-facing documentation
- add or extend tests around rule evaluation and estimation validation
- improve nutrition-rule coverage and explanation quality
- propose UX improvements for manual correction and meal review

## Development workflow

1. Fork the repository.
2. Create a focused branch for one change.
3. Keep changes small and explain the user or maintainer impact.
4. Add or update tests when behavior changes.
5. Open a pull request with a concise description and validation notes.

## Pull request expectations

- keep PRs scoped to one topic
- describe what changed and why
- mention manual or automated testing performed
- avoid unrelated formatting or cleanup changes
- expect PR checks to run in GitHub Actions
- expect changed production Swift files in PRs to meet the coverage gate configured in CI

## Issue reports

Useful bug reports usually include:

- expected behavior
- actual behavior
- screenshots if the issue is visual
- simulator or device details
- sample meal text if the problem is related to parsing

## Health-related scope

Life Advisor is educational software, not medical advice. Contributions should preserve that framing and avoid making clinical claims that are not clearly sourced.

## Code style

- follow existing Swift and SwiftUI conventions in the repository
- prefer small, readable changes
- preserve deterministic and explainable rule behavior
- avoid introducing opaque logic where an explicit rule is possible
