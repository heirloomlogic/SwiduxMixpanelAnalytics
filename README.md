# SwiduxMixpanelAnalytics

**Mixpanel adapter for Swidux's `AnalyticsPlugin`.** Implements `AnalyticsService` against a Mixpanel SDK instance it initializes and owns, ships a recording mock for previews and tests, and translates `AnalyticsValue` into Mixpanel's `Properties` payload with no app-level bridging code.

## Why this package

- **Drop-in `AnalyticsService` conformance.** `MixpanelAnalyticsService` forwards `track` / `identify` / `alias` / `reset` / `flush` to the Mixpanel SDK. Empty property dicts are passed as `nil`; nested arrays and dicts are translated recursively. `identify` sends nothing for profile properties it omits, so their saved values stay, and unsets those passed as `.null`.
- **The adapter is the configuration boundary.** Pass the token and any Mixpanel knobs (EU residency, opt-out by default, flush interval, automatic events, gzip, super properties, custom device IDs via `deviceIdProvider:`) to `MixpanelAnalyticsService.init`. The adapter owns `Mixpanel.initialize` internally so apps never `import Mixpanel`. Swapping to a different analytics provider is a one-import, one-line change.
- **GDPR controls without re-coupling.** `setOptedOut(_:)` plugs straight into the plugin's `onConsentChange` hook so Mixpanel's own consent switch follows the plugin's gate, and it returns only once the SDK has applied the change. Opting out deletes the queue instead of sending it; an upload already under way is not cancelled. Logging and geo-by-IP toggles live on the adapter too, and `excludeProperties:` strips named property keys from every event before they are stored or sent.
- **Preview- and test-friendly mock.** `MockMixpanelAnalyticsService` is an actor that records every call and exposes its history (`trackedEvents`, `identifyCalls`, `aliasCalls`, `resetCount`, `flushCount`, `optOutCount`, `optInCalls`, `optedOut`, `loggingEnabled`, `useIPAddressForGeoLocation`) for `#expect` assertions. No Mixpanel SDK runtime needed.
- **Corrects the SDK's sharp edges.** The Mixpanel SDK applies consent changes late, sends only 50 records per flush, deletes queued events on `reset()`, forgets the consent choice on `reset()`, drops super properties after logout, and sends nulls as the string `"<null>"`. The adapter handles each of these so apps don't have to; the [Service Reference](https://heirloomlogic.github.io/SwiduxMixpanelAnalytics/documentation/swiduxmixpanelanalytics/servicereference) has the details.
- **Multiple instances supported.** Pass a unique `instanceName:` to each `MixpanelAnalyticsService` for fan-out to multiple Mixpanel projects. For apps that need to build a `MixpanelInstance` themselves (e.g., `ProxyServerConfig`), `MixpanelAnalyticsService(instance:)` is the documented escape hatch.

## Installation

**Xcode.** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics`. Add the `SwiduxMixpanelAnalytics` product to your target.

**Package.swift.**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics", from: "1.0.0"),
```

```swift
.product(name: "SwiduxMixpanelAnalytics", package: "SwiduxMixpanelAnalytics"),
```

## Quickstart

Construct the service with your token, register the analytics plugin, and dispatch events through Swidux — no `import Mixpanel` required.

```swift
import Swidux
import SwiduxAnalytics
import SwiduxMixpanelAnalytics

// 1. Build the service. The adapter owns `Mixpanel.initialize` internally.
let analyticsService = MixpanelAnalyticsService(
    token: "your-mixpanel-token",
    optOutTrackingByDefault: true  // nothing is sent until the user consents
)

// 2. Plugin registration. `onConsentChange` keeps Mixpanel's own consent
//    switch in step with `.analytics(.setOptedOut(_:))`.
plugins.register(
    AnalyticsPlugin(
        state: \.analytics,
        action: AppAction.analytics,
        extractAction: { if case .analytics(let a) = $0 { return a }; return nil },
        service: analyticsService,
        mapper: analyticsMapper,
        identity: analyticsIdentity,
        onConsentChange: { await analyticsService.setOptedOut($0) }
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
- [Swidux](https://github.com/HeirloomLogic/Swidux) 1.10+ (`SwiduxAnalytics` product)
- [Mixpanel Swift SDK](https://github.com/mixpanel/mixpanel-swift) 6.7.0+

## License

MIT — see [LICENSE](LICENSE).
