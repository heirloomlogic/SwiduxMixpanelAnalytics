# Contributing

## Enable dev tooling before your first build

`SwiduxMixpanelAnalytics` publishes a library product, so its dev-only tooling — the [Persnicket](https://github.com/HeirloomLogic/Persnicket) `Persnoop` swift-format linter and the DocC plugin — is **gated behind a gitignored `.dev-tooling` sentinel file** so it never leaks into downstream consumers' dependency graphs. The sentinel exists only in maintainer clones and in CI.

Create it once, **before your first build**:

```sh
touch .dev-tooling
```

With the sentinel present, `swift build` runs the Persnoop linter on every build and the DocC plugin is available. Without it, you build in "consumer mode" — no linting, no DocC — and a PR that passes locally can still fail CI's lint check.

### If you built before creating the sentinel

SwiftPM caches the evaluated manifest by its text, and the sentinel is external to that text — so toggling `.dev-tooling` after a build won't take effect until you clear that cache layer:

```sh
swift package purge-cache
swift package resolve
```

Note: `swift package reset` does **not** clear the evaluated-manifest cache — `purge-cache` is the specific verb. A fresh clone that runs `touch .dev-tooling` before its very first build avoids this entirely.

## Linting

Lint runs automatically on every build once the sentinel is in place. It uses your project's own `.swift-format` if one is present, otherwise Persnicket's bundled default — the same file CI's `.persnicket-ci/bin/ci-lint-setup` copies in before running the strict check (see `.github/workflows/lint.yml`). `.swift-format` is gitignored, so a fresh clone doesn't have one; to run the PR checklist's exact strict command locally, copy it out of the resolved Persnicket checkout once `.dev-tooling` has pulled it in:

```sh
cp .build/checkouts/Persnicket/.swift-format .swift-format
xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Sources Tests
```

To reformat in place on demand:

```sh
swift package plugin --allow-writing-to-package-directory format-source-code
```
