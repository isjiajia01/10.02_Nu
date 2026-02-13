# Release Engineering

## Versioning Policy
- `MARKETING_VERSION`: SemVer (`MAJOR.MINOR.PATCH`), e.g. `1.1.0`.
- `CURRENT_PROJECT_VERSION`: monotonically increasing integer build number.

## Build Profiles
- Debug:
  - diagnostics enabled
  - testability enabled
- Release:
  - diagnostics disabled via compile flags
  - no debug-only log output

## Local / CI Commands
```bash
make build
make test
make lint
make format
```

## Release Checklist
1. Set `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION`.
2. Confirm `REJSEPLANEN_ACCESS_ID` is injected from CI secrets, not source code.
3. Run `make build` and `make test`.
4. Validate English-only UI copy on key paths.
5. Validate location-denied fallback path.
6. Archive with Release config and verify no debug diagnostics in runtime logs.
