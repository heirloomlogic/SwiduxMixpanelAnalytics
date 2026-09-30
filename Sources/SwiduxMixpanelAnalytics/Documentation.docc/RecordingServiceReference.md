# Recording Service Reference

API reference for ``RecordingMixpanelAnalyticsService``, the recording stand-in for ``MixpanelAnalyticsService`` in SwiftUI previews and Swift Testing suites.

## Overview

`RecordingMixpanelAnalyticsService` is an actor that conforms to `AnalyticsService`. It sends the five service calls to a `RecordingAnalyticsService` from `SwiduxAnalytics`, exposed as ``RecordingMixpanelAnalyticsService/recorder``, and records the Mixpanel-only controls itself. Assertions on `recorder` are the same ones you would write for any other provider, so they don't change if the app moves off Mixpanel.

It never creates a Mixpanel instance, so previews run without a token or network. It is not a production service: the log grows without limit, and `RecordingAnalyticsService` logs a fault at init in Release builds.

For usage examples, see <doc:HowToPreviewAndTest>.

## Types

### ``RecordingMixpanelAnalyticsService``

```swift
public actor RecordingMixpanelAnalyticsService: AnalyticsService {
    public init(optedOut: Bool = false)

    public let recorder: RecordingAnalyticsService

    public func setOptedOut(_ optedOut: Bool) async
    public func optOutTracking() async
    public func optInTracking(distinctID: String? = nil, properties: [String: AnalyticsValue]? = nil) async
    public func hasOptedOutTracking() async -> Bool
    public func setLoggingEnabled(_ enabled: Bool) async
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async

    public private(set) var optInCalls: [OptInCall]
    public private(set) var loggingEnabled: Bool?
    public private(set) var useIPAddressForGeoLocation: Bool?

    public struct OptInCall: Sendable, Equatable {
        public init(distinctID: String? = nil, properties: [String: AnalyticsValue]? = nil)
        public let distinctID: String?
        public let properties: [String: AnalyticsValue]?
    }
}
```

#### Recorded state

- `recorder.calls` has every `track`, `identify`, `alias`, `reset`, and `flush` call, plus a `.setOptedOut(_:)` entry for each opt-in and opt-out, in arrival order. The recorder's other properties are in Swidux's [Plugin Analytics Reference](https://heirloomlogic.github.io/Swidux/documentation/swidux/pluginanalyticsreference).
- `optInCalls` has the `(distinctID, properties)` pair from every `optInTracking(distinctID:properties:)` call.
- `hasOptedOutTracking()` returns the state set by the last opt-in or opt-out.
- `loggingEnabled` is the last value passed to `setLoggingEnabled(_:)`, or `nil` if it was never called.
- `useIPAddressForGeoLocation` is the last value passed to `setUseIPAddressForGeoLocation(_:)`, or `nil` if it was never called.

All accessors are `async`, so read them with `await`. The record types have public initializers for building expected values: `#expect(await service.optInCalls == [.init(distinctID: "user-1")])`.

#### Consent

`init(optedOut:)` stands in for the real service's `optOutTrackingByDefault`. `setOptedOut(_:)` routes to `optOutTracking()` or `optInTracking()` as the real service does, so the same `onConsentChange: { await service.setOptedOut($0) }` wiring works for both. Every opt-in and opt-out is recorded, including a repeated one that the real service would ignore.

#### Determinism

The service holds no buffers and adds no latency. Every call is recorded before it returns. Await the plugin's `flush()` before asserting, because the plugin queues service calls and runs them one at a time.

The recorder keeps calls the real service drops: an `identify` with a blank `userID`, an `alias` with a blank `newID` (see <doc:ServiceReference>), and anything sent while opted out. Assert consent through `hasOptedOutTracking()` or the `.setOptedOut` entries, not by the absence of events.

## See Also

- <doc:HowToPreviewAndTest>
- <doc:ServiceReference>
