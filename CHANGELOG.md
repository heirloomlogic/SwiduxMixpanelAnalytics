# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Releases are tagged with bare semver (e.g. `1.0.0`, no `v` prefix).

## [Unreleased]

### Added

- Custom device identity: a `deviceIdProvider:` closure on `MixpanelAnalyticsService.init`,
  forwarded to `MixpanelOptions`, so apps can supply a stable device ID without importing
  Mixpanel (#6).
- `CODE_OF_CONDUCT.md` and `SECURITY.md` governance docs (#6).
- This changelog.
- GitHub issue and pull-request templates under `.github/`.
- Value-translation tests for arrays of dicts, dicts containing arrays, and deeply nested
  structures, locking in the recursive `AnalyticsValue → MixpanelType` mapping.

### Changed

- `identify` and `alias` now drop blank `userID` / `newID` calls, so a People update is never
  mis-attributed to the previous identity (#6).
- Refreshed README and DocC on SDK-instance keying (`instanceName`, falling back to `token`),
  `excludeProperties` scope, and mock recording semantics (#6).

## [1.0.0] - 2026-06-11

Initial release: a Mixpanel adapter for Swidux's provider-agnostic `AnalyticsPlugin`.

### Added

- `MixpanelAnalyticsService` — an `AnalyticsService` conformer that owns `Mixpanel.initialize`
  internally, so app code never imports `Mixpanel`. The initializer surfaces the common
  `MixpanelOptions` knobs (token, `flushInterval`, `instanceName`, `optOutTrackingByDefault`,
  `useUniqueDistinctId`, `superProperties`, `serverURL`, `useGzipCompression`, `excludeProperties`)
  plus runtime GDPR / diagnostic controls (`optOutTracking`, `optInTracking`,
  `hasOptedOutTracking`, `setLoggingEnabled`, `setUseIPAddressForGeoLocation`).
- `MixpanelAnalyticsService(instance:)` escape hatch for apps that must build their own
  `MixpanelInstance` (e.g. `ProxyServerConfig`).
- `MockMixpanelAnalyticsService` — a recording actor for previews and Swift Testing suites.
- `AnalyticsValue → Mixpanel Properties` translation, mapping every case and recursing through
  nested arrays and dictionaries.
- Verified against the `SwiduxAnalytics` auto-identify contract: repeated same-`userID` identify
  is an idempotent `identify` + `people.set`, never an alias rotation.
- Mixpanel Swift SDK 6.4 adoption and version-pinned dependencies.
- Dev-only tooling (Persnicket swift-format linter, DocC plugin) gated behind a gitignored
  `.dev-tooling` sentinel so it never leaks into downstream dependency graphs.
- DocC documentation and GitHub Actions for tests, linting, and documentation deployment.

[Unreleased]: https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics/compare/1.0.0...HEAD
[1.0.0]: https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics/releases/tag/1.0.0
