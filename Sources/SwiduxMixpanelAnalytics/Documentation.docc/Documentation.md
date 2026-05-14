# ``SwiduxMixpanelAnalytics``

Mixpanel adapter for Swidux's `AnalyticsPlugin`. Owns the Mixpanel SDK on the app's behalf — `MixpanelAnalyticsService(token:)` calls `Mixpanel.initialize` internally so apps never need to `import Mixpanel`. Ships a recording mock for previews and tests.

@Metadata {
    @DisplayName("SwiduxMixpanelAnalytics")
}

## Overview

`SwiduxMixpanelAnalytics` is the bridge between Mixpanel's iOS SDK and Swidux's provider-agnostic analytics plugin. The plugin owns analytics state (opt-out flag, current screen, last-identified user) and converts your domain actions into typed `AnalyticsEvent` values; this package translates those events into Mixpanel SDK calls and maps `AnalyticsValue` into Mixpanel's `Properties` payload.

Two types ship in a single product:

- ``MixpanelAnalyticsService`` — the live `AnalyticsService` conformer that constructs and wraps a `MixpanelInstance`.
- ``MockMixpanelAnalyticsService`` — a recording actor for SwiftUI `#Preview` blocks and Swift Testing suites.

The flow:

```
store.send(.counter(.increment(5)))
  → AnalyticsPlugin runs the mapper in afterReduce
  → mapper emits AnalyticsEvent("counter_added", ["amount": .int(5)])
  → MixpanelAnalyticsService.track(_:) forwards to MixpanelInstance.track(event:properties:)
  → Mixpanel SDK queues the event and flushes per its own schedule
```

The plugin and the adapter stay decoupled: the plugin doesn't know about Mixpanel, and the adapter doesn't know about your action tree.

## Topics

### Quickstart

- <doc:GettingStarted>

### How-to Guides

- <doc:HowToImplementService>
- <doc:HowToPreviewAndTest>

### Reference

- <doc:ServiceReference>
- <doc:MockServiceReference>

### Explanation

- <doc:ValueTranslation>

### Service Layer

- ``MixpanelAnalyticsService``

### Testing

- ``MockMixpanelAnalyticsService``
