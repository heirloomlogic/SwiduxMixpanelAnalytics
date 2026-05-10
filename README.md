# SwiduxMixpanelAnalytics

**Mixpanel adapter for Swidux's `AnalyticsPlugin`.** Implements `AnalyticsService` against `Mixpanel.mainInstance()`, ships a recording mock for previews and tests, and translates `AnalyticsValue` into Mixpanel's `Properties` payload with no app-level bridging code.

## Why this package

- **Drop-in `AnalyticsService` conformance.** `MixpanelAnalyticsService` forwards `track` / `identify` / `alias` / `reset` / `flush` to the Mixpanel SDK. Empty property dicts are passed as `nil`; nested arrays and dicts are translated recursively.
- **Per-instance configuration stays with Mixpanel.** All Mixpanel-specific knobs (token, EU residency, opt-out by default, flush interval, automatic events) are set at `Mixpanel.initialize` time. The service has zero configuration of its own — it wraps whichever `MixpanelInstance` you hand it.
- **Preview- and test-friendly mock.** `MockMixpanelAnalyticsService` is an actor that records every call and exposes its history (`trackedEvents`, `identifyCalls`, `aliasCalls`, `resetCount`, `flushCount`) for `#expect` assertions. No Mixpanel SDK runtime needed.
- **Multiple instances supported.** Initialize a `MixpanelInstance` per project and pass each to its own `MixpanelAnalyticsService(instance:)` for fan-out to multiple Mixpanel projects.

## Installation

**Xcode.** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics`. Add the `SwiduxMixpanelAnalytics` product to your target.

**Package.swift.**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics", branch: "main"),
```

```swift
.product(name: "SwiduxMixpanelAnalytics", package: "SwiduxMixpanelAnalytics"),
```

## Quickstart

Initialize Mixpanel at launch, register the analytics plugin with `MixpanelAnalyticsService`, and dispatch events through Swidux:

```swift
import Mixpanel
import Swidux
import SwiduxAnalytics
import SwiduxMixpanelAnalytics

// 1. App launch
Mixpanel.initialize(token: "your-mixpanel-token", trackAutomaticEvents: false)

// 2. Plugin registration
plugins.register(
    AnalyticsPlugin(
        state: \.analytics,
        action: AppAction.analytics,
        extractAction: { if case .analytics(let a) = $0 { return a }; return nil },
        service: MixpanelAnalyticsService(),
        mapper: analyticsMapper,
        identity: analyticsIdentity
    )
)

// 3. Dispatch
store.send(.analytics(.screenView("Home")))
```

See the [Getting Started](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/gettingstarted) guide for the full walk-through.

## Documentation

Full DocC reference at https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/. Starting points by intent:

- **I want the shortest path to events in Mixpanel** — [Getting Started](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/gettingstarted)
- **I need EU residency, opt-out by default, or multiple instances** — [How to Implement the Service](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/howtoimplementservice)
- **I want to preview / test without Mixpanel** — [How to Preview and Test](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/howtopreviewandtest)
- **I want the API** — [Service Reference](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/servicereference), [Mock Service Reference](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/mockservicereference)
- **I want to know how `AnalyticsValue` cases land in Mixpanel** — [Value Translation](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/valuetranslation)

## Requirements

- Swift 6.2 / Xcode 26+
- iOS 18 / macOS 15
- [Swidux](https://github.com/HeirloomLogic/Swidux) (`SwiduxAnalytics` product)
- [Mixpanel iOS SDK](https://github.com/mixpanel/mixpanel-swift) 4.3+

## License

MIT — see [LICENSE](LICENSE).
