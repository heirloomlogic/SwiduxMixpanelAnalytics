---
name: Feature request
about: Suggest a Mixpanel knob to surface, or another improvement
title: ""
labels: enhancement
assignees: ""
---

## What's missing

Describe the capability you need. If it's a Mixpanel SDK option the initializer doesn't yet
surface, name the `MixpanelOptions` field or `MixpanelInstance` API.

## Why the escape hatch isn't enough

`MixpanelAnalyticsService(instance:)` lets you build any `MixpanelInstance` yourself. The goal is
to keep the happy path `import Mixpanel`-free — so tell us why this belongs on the token-based
initializer rather than the escape hatch.

## Proposed shape

If you have one, sketch the API (parameter name, type, default).

## Additional context

Links to Mixpanel docs, related issues, or use cases.
