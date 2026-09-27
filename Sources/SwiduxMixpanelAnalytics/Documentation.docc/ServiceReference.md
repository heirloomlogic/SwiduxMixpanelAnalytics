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
    // Identical on every platform.
    public init(
        token: String,
        trackAutomaticEvents: Bool = false,
        flushInterval: Double = 60,
        instanceName: String? = nil,
        optOutTrackingByDefault: Bool = false,
        useUniqueDistinctId: Bool = false,
        deviceIdProvider: (@Sendable () -> String?)? = nil,
        superProperties: [String: AnalyticsValue]? = nil,
        serverURL: String? = nil,
        useGzipCompression: Bool = true,
        excludeProperties: Set<String> = []
    )

    public init(instance: MixpanelInstance)

    public func setOptedOut(_ optedOut: Bool) async
    public func optOutTracking() async
    public func optInTracking(distinctID: String? = nil, properties: [String: AnalyticsValue]? = nil) async
    public func hasOptedOutTracking() async -> Bool
    public func setLoggingEnabled(_ enabled: Bool) async
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async
}
```

Value type holding a reference to a `MixpanelInstance`; every copy shares the instance. It is `@unchecked Sendable` because the SDK serializes its tracking work on internal queues. The diagnostic setters are the exception — they write properties the SDK doesn't synchronize, so call them once at launch. Cheap to pass into `AnalyticsPlugin`.

The SDK applies most calls later, on its own serial queue, while checking consent on the caller's thread. The adapter closes the gaps that leaves; each method below says how.

#### Initializers

```swift
public init(token: String, ...)
```

Builds a `MixpanelOptions` and calls `Mixpanel.initialize(options:)` internally, retaining the resulting instance. Parameters mirror `MixpanelOptions` — including its `useGzipCompression: true` default; `superProperties` takes `[String: AnalyticsValue]` so the app does not need to reference `MixpanelType`, and `deviceIdProvider` supplies a custom stable device ID (see <doc:HowToImplementService> for the contract: cached value only, no inline I/O).

The Mixpanel SDK keys instances by `instanceName` (falling back to `token`); constructing a second service with the same name returns the existing SDK instance and silently ignores the new options. Services for different projects can safely be built concurrently: the adapter looks its instance up by name, working around an SDK race that could otherwise hand one service the other's instance. `superProperties` are re-applied after `reset()` and after opting back in, since the SDK drops them at both points and ignores them while opted out.

```swift
public init(instance: MixpanelInstance)
```

Escape hatch for apps that need to build their own `MixpanelInstance` (for example, to use `ProxyServerConfig`). Most apps should prefer the token initializer; this is the only path that requires `import Mixpanel` in your app. Super properties registered on such an instance are the app's to manage.

#### `track(_:) async`

Forwards to `MixpanelInstance.track(event:properties:)`. Empty `properties` are passed as `nil` rather than an empty dictionary, and properties that translate to null are omitted (see <doc:ValueTranslation>). Returns immediately; Mixpanel batches and flushes on its own schedule.

#### `identify(userID:properties:) async`

Forwards to `MixpanelInstance.identify(distinctId:)`, then sets `properties` on the user's profile with `instance.people.set(properties:)`; properties that translate to null are unset instead. Empty `userID`s are dropped entirely: the SDK rejects blank distinct IDs, and forwarding the people update anyway would attribute it to the previous identity. Calls made while opted out are dropped.

When the user changes, everything queued for the previous user is sent first, and `identify` waits for it — the SDK attributes queued profile updates to whoever is identified when they are sent.

#### `alias(newID:previousID:) async`

Forwards to `MixpanelInstance.createAlias(_:distinctId:andIdentify:)` with `andIdentify: false`, so the alias never changes who is identified locally — the SDK default would re-identify the device as `previousID`, undoing a preceding sign-in. When `previousID` is `nil`, the anonymous distinct ID the device's events were sent under is used. The SDK sends its queue after every alias, and `alias` waits for that so the send can't overlap the next flush and duplicate rows. Empty `newID`s are dropped, mirroring the SDK's blank-alias rejection. Projects on Mixpanel's Simplified ID Merge ignore aliases; see <doc:HowToImplementService>.

#### `reset() async`

Sends everything queued and waits for it, then forwards to `MixpanelInstance.reset(completion:)` and awaits its callback — the SDK's own `reset()` sends one 50-record batch and deletes the rest. Clears Mixpanel's local distinct ID, super properties, and timed events, then re-applies the initializer's super properties. While opted out it leaves the SDK alone: its `reset()` would also erase the persisted opt-out, and the user would be tracked again from the next launch.

#### `flush() async`

Forwards to `MixpanelInstance.flush(performFullFlush: true, completion:)` and awaits its callback, so the whole queue is sent rather than the SDK's default 50-record batch. The SDK sends one request per 50 records, each bounded at 120 seconds, and stops at the first failure, so a hung server can hold this for minutes — use the plugin's `flush(timeout:)` on shutdown paths. The SDK delivers the callback on the main queue; never block the main thread waiting for it. The plugin's own `flush()` is the deterministic sync point in tests — it awaits all pending fire-and-forget tracking tasks and then calls this.

#### `setOptedOut(_:) async`

Calls `optOutTracking()` for `true` and `optInTracking()` for `false`. Shaped for the plugin's `onConsentChange` hook: `onConsentChange: { await service.setOptedOut($0) }`.

#### `optOutTracking() async`

Sends everything queued, resets the local identity, then forwards to `MixpanelInstance.optOutTracking()` and returns once the SDK has applied it. From then on `track`, `identify`, and `alias` are dropped until ``MixpanelAnalyticsService/optInTracking(distinctID:properties:)``. Does nothing when already opted out. Persists across launches.

It does **not** delete the user's Mixpanel profile. The SDK's own opt-out queues a `$delete` that is never sent and that would later delete the next identified user's profile; resetting the identity first stops it being queued. Use Mixpanel's GDPR deletion API from your server to erase data.

#### `optInTracking(distinctID:properties:) async`

Forwards to `MixpanelInstance.optInTracking(distinctId:properties:)` and returns once the SDK has applied it, so an `identify` issued straight afterwards is honored. The SDK identifies the user as `distinctID` (when non-empty) and records a `$opt_in` event carrying `properties` — they are event properties, not profile properties. The event is queued a moment after the opt-in takes effect, so a `flush()` issued straight away may leave it for the next one. When the user is already opted in, no `$opt_in` is sent and only the `distinctID` identify happens. Before opting in, anything the SDK kept queued while opted out is discarded — only a stale profile deletion or unattributed leftovers can be there. The wait for the SDK is bounded at 30 seconds; hitting the bound logs a fault.

#### `hasOptedOutTracking() async -> Bool`

Forwards to `MixpanelInstance.hasOptedOutTracking()`. On a first launch with `optOutTrackingByDefault`, it first waits for the SDK to apply the default — until it does, the SDK reports the user as opted in. (Not with `init(instance:)`, which doesn't know the instance's options.)

#### `setLoggingEnabled(_:) async`

Sets `MixpanelInstance.loggingEnabled`. Useful during development; disable in release. Set it once at launch.

#### `setUseIPAddressForGeoLocation(_:) async`

Sets `MixpanelInstance.useIPAddressForGeoLocation`. Disable when your privacy policy forbids IP-based geo resolution. Set it once at launch.

## See Also

- <doc:HowToImplementService>
- <doc:ValueTranslation>
- <doc:MockServiceReference>
- ``MixpanelAnalyticsService``
