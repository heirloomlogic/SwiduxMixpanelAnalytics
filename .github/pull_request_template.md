## Summary

<!-- What does this change and why? Link any related issue: Closes #NN -->

## Checklist

- [ ] `.dev-tooling` sentinel created before building (`touch .dev-tooling`; run
      `swift package purge-cache` if you added it after a prior build).
- [ ] `swift test` passes on macOS.
- [ ] swift-format lint passes:
      `xcrun swift-format lint --strict --parallel --recursive --configuration .swift-format Sources Tests`.
- [ ] Public API changes are reflected in the DocC guides under `Sources/**/Documentation.docc/`.
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`.
- [ ] The app-facing happy path still requires no `import Mixpanel` (SDK stays behind the adapter).

## Notes for reviewers

<!-- Anything that needs extra attention: contract changes, concurrency, consent/PII handling -->
