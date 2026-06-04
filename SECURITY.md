# Security Policy

## Supported scope

Security reports are welcome for:

- exposed secrets or unsafe credential handling
- unsafe network behavior
- data leakage involving user nutrition logs or stored metadata
- vulnerabilities in repository automation or dependencies

## Reporting

Please do not open public issues for suspected security problems.

Instead, contact the maintainer privately through GitHub or the repository contact channel with:

- a short description of the issue
- reproduction steps
- impact assessment
- suggested remediation if available

## Handling notes

- API keys are intended to be stored in the device Keychain
- app data is stored locally with SwiftData
- the project should avoid committing real secrets, tokens, or personal health data samples

Reports will be acknowledged as quickly as possible, and validated issues will be fixed before public disclosure when practical.
