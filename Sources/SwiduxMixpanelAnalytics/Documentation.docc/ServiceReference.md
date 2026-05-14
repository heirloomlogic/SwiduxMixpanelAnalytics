# Service Reference

API reference for ``MixpanelAnalyticsService`` — the Mixpanel-backed `AnalyticsService` conformer that the analytics plugin consumes.

## Overview

`MixpanelAnalyticsService` owns the Mixpanel SDK on the app's behalf. The token-taking initializer calls `Mixpanel.initialize` internally; runtime GDPR / diagnostic toggles are methods on the service. The app never needs to `import Mixpanel` on the happy path.

For a step-by-step integration walkthrough, see <doc:HowToImplementService>. For value-mapping rules, see <doc:ValueTranslation>.

## Library target

- Product: `SwiduxMixpanelAnalytics`
- Import: `import SwiduxMixpanelAnalytics`

`Package.swift`:

```swift
.product(name: "SwiduxMixpanelAnalytics", package: "SwiduxMixpanelAnalytics"),
```

## Types

### ``MixpanelAnalyticsService``

```swift
public struct MixpanelAnalyticsService: AnalyticsService, @unchecked Sendable {
    // iOS / tvOS / watchOS
    public init(
        token: String,
        trackAutomaticEvents: Bool = false,
        flushInterval: Double = 60,
        instanceName: String? = nil,
        optOutTrackingByDefault: Bool = false,
        useUniqueDistinctId: Bool = false,
        superProperties: [String: AnalyticsValue]? = nil,
        serverURL: String? = nil,
        useGzipCompression: Bool = false
    )

    // macOS — same as above, minus `trackAutomaticEvents`.
    public init(
        token: String,
        flushInterval: Double = 60,
        instanceName: String? = nil,
        optOutTrackingByDefault: Bool = false,
        useUniqueDistinctId: Bool = false,
        superProperties: [String: AnalyticsValue]? = nil,
        serverURL: String? = nil,
        useGzipCompression: Bool = false
    )

    public init(instance: MixpanelInstance)
}
```

Value type holding a single reference to a `MixpanelInstance`. `@unchecked Sendable` is justified by Mixpanel's documented thread-safety. Cheap to pass into `AnalyticsPlugin`.

#### Initializers

```swift
public init(token: String, ...)
```

Calls `Mixpanel.initialize(token:...)` internally and retains the resulting instance. Parameters mirror the Mixpanel SDK; `superProperties` takes `[String: AnalyticsValue]` so the app does not need to reference `MixpanelType`. On macOS, `trackAutomaticEvents` is omitted (the SDK does not accept it there).

```swift
public init(instance: MixpanelInstance)
```

Escape hatch for apps that need to build their own `MixpanelInstance` (for example, to use `ProxyServerConfig`). Most apps should prefer the token initializer; this is the only path that requires `import Mixpanel` in your app.

#### `track(_:) async`

Forwards to `MixpanelInstance.track(event:properties:)`. Empty `properties` are passed as `nil` rather than an empty dictionary. Returns immediately; Mixpanel batches and flushes on its own schedule.

#### `identify(userID:properties:) async`

Forwards to `MixpanelInstance.identify(distinctId:)`, then — if `properties` is non-empty — calls `instance.people.set(properties:)` to update people-level properties.

#### `alias(newID:previousID:) async`

Forwards to `MixpanelInstance.createAlias(_:distinctId:)`. When `previousID` is `nil`, the call uses `instance.distinctId` as the source ID, matching Mixpanel's recommended anonymous-to-identified aliasing flow.

#### `reset() async`

Forwards to `MixpanelInstance.reset(completion:)` and awaits its callback. Clears Mixpanel's local distinct ID, super properties, and identity.

#### `flush() async`

Forwards to `MixpanelInstance.flush(completion:)` and awaits its callback. The plugin's own `flush()` is the deterministic sync point in tests — it awaits all pending fire-and-forget tracking tasks and then calls this.

#### `optOutTracking() async`

Forwards to `MixpanelInstance.optOutTracking()`. Subsequent `track` / `identify` calls are dropped until ``MixpanelAnalyticsService/optInTracking(distinctID:properties:)`` is called. Also clears the existing people profile and charges.

#### `optInTracking(distinctID:properties:) async`

Forwards to `MixpanelInstance.optInTracking(distinctId:properties:)`. Optionally identifies the user and records people-profile properties as part of opting in.

#### `hasOptedOutTracking() async -> Bool`

Forwards to `MixpanelInstance.hasOptedOutTracking()`.

#### `setLoggingEnabled(_:) async`

Sets `MixpanelInstance.loggingEnabled`. Useful during development; disable in release.

#### `setUseIPAddressForGeoLocation(_:) async`

Sets `MixpanelInstance.useIPAddressForGeoLocation`. Disable when your privacy policy forbids IP-based geo resolution.

## See Also

- <doc:HowToImplementService>
- <doc:ValueTranslation>
- <doc:MockServiceReference>
- ``MixpanelAnalyticsService``
