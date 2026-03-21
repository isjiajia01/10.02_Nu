# Security Policy

## Supported Scope

This repository is a portfolio project and public code sample. Security fixes may be applied on a best-effort basis.

## Reporting a Vulnerability

Please do not open a public issue for secrets, credential exposure, or exploitable behavior.

If you find a security issue, contact the repository owner privately and include:

- affected file or area
- steps to reproduce
- impact assessment
- suggested remediation if available

## Secret Handling Expectations

- Do not commit real API credentials.
- `REJSEPLANEN_ACCESS_ID` must be injected through environment or build configuration.
- Any accidentally committed credential should be treated as compromised and rotated immediately.

