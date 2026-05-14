# Mock Service Reference

API reference for ``MockMixpanelAnalyticsService`` — a recording `AnalyticsService` for SwiftUI previews and Swift Testing suites.

## Overview

`MockMixpanelAnalyticsService` is an actor that conforms to `AnalyticsService` and records every call it receives. Use it in `#Preview` blocks (where you don't want real network traffic) and in tests (where you want deterministic assertions on what the plugin dispatched).

It has no Mixpanel SDK dependency — it imports `SwiduxAnalytics` only — so previews compile against it without configuring Mixpanel.

For usage examples, see <doc:HowToPreviewAndTest>.

## Types

### ``MockMixpanelAnalyticsService``

```swift
public actor MockMixpanelAnalyticsService: AnalyticsService {
    public init()

    public private(set) var trackedEvents: [AnalyticsEvent]
    public private(set) var identifyCalls: [IdentifyCall]
    public private(set) var aliasCalls: [AliasCall]
    public private(set) var resetCount: Int
    public private(set) var flushCount: Int
    public private(set) var optOutCount: Int
    public private(set) var optInCalls: [OptInCall]
    public private(set) var optedOut: Bool
    public private(set) var loggingEnabled: Bool?
    public private(set) var useIPAddressForGeoLocation: Bool?

    public struct IdentifyCall: Sendable, Equatable {
        public let userID: String
        public let properties: [String: AnalyticsValue]
    }

    public struct AliasCall: Sendable, Equatable {
        public let newID: String
        public let previousID: String?
    }

    public struct OptInCall: Sendable, Equatable {
        public let distinctID: String?
        public let properties: [String: AnalyticsValue]?
    }
}
```

#### Recorded state

- `trackedEvents` — every `AnalyticsEvent` passed to `track(_:)`, in dispatch order.
- `identifyCalls` — every `(userID, properties)` pair passed to `identify(userID:properties:)`.
- `aliasCalls` — every `(newID, previousID)` pair passed to `alias(newID:previousID:)`.
- `resetCount` — number of times `reset()` was called.
- `flushCount` — number of times `flush()` was called.
- `optOutCount` — number of times `optOutTracking()` was called.
- `optInCalls` — every `(distinctID, properties)` pair passed to `optInTracking(distinctID:properties:)`.
- `optedOut` — current tracked opt-out state, also returned from `hasOptedOutTracking()`.
- `loggingEnabled` — last value passed to `setLoggingEnabled(_:)`, or `nil` if never set.
- `useIPAddressForGeoLocation` — last value passed to `setUseIPAddressForGeoLocation(_:)`, or `nil` if never set.

All accessors are `async` — wrap reads in `await`.

#### Determinism

The mock holds no buffers and adds no latency: every `track`/`identify`/`alias` records synchronously inside the actor. The plugin's own `flush()` is still the right sync point for test assertions, since it drains the plugin's own fire-and-forget task counter before the mock is queried.

## See Also

- <doc:HowToPreviewAndTest>
- <doc:ServiceReference>
