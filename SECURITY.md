# Security Policy

## Supported versions

Only the latest minor release receives security fixes. Older releases should upgrade — the public API follows semantic versioning, so upgrades within a major version are source-compatible.

| Version | Supported |
| --- | --- |
| Latest 1.x minor | ✅ |
| Earlier releases | ❌ |

## Reporting a vulnerability

Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics/security/advisories/new) — please do not open a public issue for anything security-sensitive.

Include what you can: affected version, a description of the issue, and reproduction steps or a proof of concept. You can expect an acknowledgment within a week. Fixes ship as a patch release, and the advisory is published once a fixed version is available.

## Scope

This package is a thin adapter over the [Mixpanel Swift SDK](https://github.com/mixpanel/mixpanel-swift). Issues in the SDK itself (network transport, on-device persistence, ingestion) should be reported to Mixpanel; issues in how this adapter configures or forwards to the SDK — token handling, property filtering, consent state, identity calls — belong here. When in doubt, report here and we'll route it.
