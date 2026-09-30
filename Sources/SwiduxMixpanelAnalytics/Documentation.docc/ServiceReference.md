# Service Reference

API reference for ``MixpanelAnalyticsService`` — the Mixpanel-backed `AnalyticsService` conformer that the analytics plugin consumes.

## Overview

`MixpanelAnalyticsService` owns the Mixpanel SDK on the app's behalf. The token-taking initializer calls `Mixpanel.initialize` internally. It takes most `MixpanelOptions` settings, plus logging and geolocation by IP, which `MixpanelOptions` lacks. It has no `proxyServerConfig`, `autocaptureOptions`, or feature-flag settings; for those, build the instance yourself and use `init(instance:)`. Consent controls are methods on the service. The app never needs to `import Mixpanel` on the happy path.

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
        excludeProperties: Set<String> = [],
        loggingEnabled: Bool = false,
        useIPAddressForGeoLocation: Bool = true
    )

    public init(instance: MixpanelInstance)

    public var isOptedOut: Bool { get }
    public func setOptedOut(_ optedOut: Bool) async
    public func optOutTracking() async
    public func optInTracking(distinctID: String? = nil, properties: [String: AnalyticsValue]? = nil) async
}
```

Value type holding a reference to a `MixpanelInstance`; every copy shares the instance. It is `@unchecked Sendable` because the SDK serializes its tracking work on internal queues. Cheap to pass into `AnalyticsPlugin`.

The SDK applies most calls later, on its own serial queue, while checking consent on the caller's thread. The adapter closes the gaps that leaves; each method below says how.

#### Initializers

```swift
public init(token: String, ...)
```

Builds a `MixpanelOptions` and calls `Mixpanel.initialize(options:)` internally, retaining the resulting instance. Parameters mirror `MixpanelOptions` — including its `useGzipCompression: true` default; `superProperties` takes `[String: AnalyticsValue]` so the app does not need to reference `MixpanelType`, and `deviceIdProvider` supplies a custom stable device ID (see <doc:HowToImplementService> for the contract: cached value only, no inline I/O).

`MixpanelOptions` has no settings for logging or geolocation by IP, so the initializer sets `loggingEnabled` and `useIPAddressForGeoLocation` on the instance right after `Mixpanel.initialize`, and only when they differ from the defaults. The SDK's logger is shared by every Mixpanel instance in the process: `loggingEnabled: true` turns logging on for all of them, and `false` leaves it as it is. Neither property is synchronized, and the SDK's queues may still be running work for the instance when they are written. When the SDK is compiled for Debug, turning logging on reads the instance's super properties without the lock its tracking queue writes them under, and the work `Mixpanel.initialize` queues writes them when there are super properties or a default opt-out to apply. Flushes read the geolocation setting on the SDK's network queue, so a second service with the same name can write it during a flush.

The Mixpanel SDK keys instances by `instanceName` (falling back to `token`); constructing a second service with the same name returns the existing SDK instance, and none of the options passed to `Mixpanel.initialize` take effect. The new service is still a separate adapter: settings the adapter applies itself do reach the shared instance, and the state it keeps is its own, not shared with the first service. For example, it writes `loggingEnabled: true` and `useIPAddressForGeoLocation: false` to the instance. After its `reset()` or opt-in, the instance carries this service's `superProperties`, or none. With `optOutTrackingByDefault: true` and no stored consent choice, it reports `isOptedOut` as `true`, even if the instance is opted in, until a flush it starts on the instance completes, and its consent, `identify`, `alias`, and `reset()` calls wait for that flush. Services for different projects can safely be built concurrently: the adapter looks its instance up by name, working around an SDK race that could otherwise hand one service the other's instance. `superProperties` are re-applied after `reset()` and after opting back in, since the SDK drops them at both points and ignores them while opted out.

```swift
public init(instance: MixpanelInstance)
```

Escape hatch for apps that need to build their own `MixpanelInstance` (for example, to use `ProxyServerConfig`). Most apps should prefer the token initializer; this is the only path that requires `import Mixpanel` in your app. Super properties registered on such an instance are the app's to manage.

#### `track(_:) async`

Forwards to `MixpanelInstance.track(event:properties:)`. Empty `properties` are passed as `nil` rather than an empty dictionary, and properties that translate to null are omitted (see <doc:ValueTranslation>). Returns immediately; Mixpanel batches and flushes on its own schedule.

#### `identify(userID:properties:) async`

Forwards to `MixpanelInstance.identify(distinctId:)`, then sets `properties` on the user's profile with `instance.people.set(properties:)`; properties that translate to null are unset instead. A key left out of a later call is not sent, so its saved value stays, and `.null` unsets it. Each `$set` also carries the SDK's automatic people properties unless `excludeProperties` lists them, and a null nested in an array or dictionary is dropped from that value before it is sent (see <doc:HowToImplementService>). Empty `userID`s are dropped entirely: the SDK rejects blank distinct IDs, and forwarding the people update anyway would attribute it to the previous identity. Calls made while opted out are dropped.

When the user changes, everything queued for the previous user is sent first, and `identify` waits for it — the SDK attributes queued profile updates to whoever is identified when they are sent.

#### `alias(newID:previousID:) async`

Forwards to `MixpanelInstance.createAlias(_:distinctId:andIdentify:)` with `andIdentify: false`, so the alias never changes who is identified locally — the SDK default would re-identify the device as `previousID`, undoing a preceding sign-in. When `previousID` is `nil`, the anonymous distinct ID the device's events were sent under is used. The SDK sends its queue after every alias, and `alias` waits for that so the send can't overlap the next flush and duplicate rows. Empty `newID`s are dropped, mirroring the SDK's blank-alias rejection. Projects on Mixpanel's Simplified ID Merge ignore aliases; see <doc:HowToImplementService>.

#### `reset() async`

Sends everything queued and waits for it, then forwards to `MixpanelInstance.reset(completion:)` and awaits its callback — the SDK's own `reset()` sends one 50-record batch and deletes the rest. Clears Mixpanel's local distinct ID, super properties, and timed events, then re-applies the initializer's super properties. The SDK's `reset()` also erases the persisted consent choice, so the adapter writes it back: an opted-in user stays opted in after the next launch (no second `$opt_in` is sent), an opted-out user stays opted out, and a user who never chose is left on the default. If consent changes through the adapter while the queue is being sent, the latest choice is the one kept. While opted out it leaves the SDK alone, since opting out has already cleared the identity and the queue.

#### `flush() async`

Forwards to `MixpanelInstance.flush(performFullFlush: true, completion:)` and awaits its callback, so the whole queue is sent rather than the SDK's default 50-record batch. The SDK sends one request per 50 records, each bounded at 120 seconds, and stops at the first failure, so a hung server can hold this for minutes — use the plugin's `flush(timeout:)` on shutdown paths. The SDK delivers the callback on the main queue; never block the main thread waiting for it. The plugin's own `flush()` is the deterministic sync point in tests — it awaits all pending fire-and-forget tracking tasks and then calls this.

#### `setOptedOut(_:) async`

Calls `optOutTracking()` for `true` and `optInTracking()` for `false`. Shaped for the plugin's `onConsentChange` hook: `onConsentChange: { await service.setOptedOut($0) }`.

#### `optOutTracking() async`

Forwards to `MixpanelInstance.optOutTracking()`, then deletes everything queued and resets the local identity with `MixpanelInstance.reset(completion:)`, and returns once the SDK has applied it. Nothing queued is sent, and the call does not wait for the network. From then on `track`, `identify`, and `alias` are dropped until ``MixpanelAnalyticsService/optInTracking(distinctID:properties:)``. Does nothing when already opted out. Persists across launches: the SDK's `reset()` erases the persisted opt-out, so the adapter opts out a second time to write it back.

An upload already in progress is not cancelled. The SDK checks consent when a flush starts and before it moves from events to profile updates, but not between requests. A flush that is already sending events still sends every event it had read; for a full flush such as `flush()`, that is the whole event queue, 50 events per request. Profile updates that flush had read are not sent.

It does **not** delete the user's Mixpanel profile. The SDK's own opt-out queues a `$delete` that is never sent and that would later delete the next identified user's profile; the adapter deletes it with the rest of the queue. Use Mixpanel's GDPR deletion API from your server to erase data.

#### `optInTracking(distinctID:properties:) async`

Forwards to `MixpanelInstance.optInTracking(distinctId:properties:)` and returns once the SDK has applied it, so an `identify` issued straight afterwards is honored. The SDK identifies the user as `distinctID` (when non-empty) and records a `$opt_in` event carrying `properties` — they are event properties, not profile properties. The event is queued a moment after the opt-in takes effect, so a `flush()` issued straight away may leave it for the next one. When the user is already opted in, no `$opt_in` is sent and only the `distinctID` identify happens. Before opting in, anything the SDK kept queued while opted out is discarded — only a stale profile deletion or unattributed leftovers can be there. The wait for the SDK is bounded at 30 seconds; hitting the bound logs a fault.

#### `isOptedOut: Bool`

Whether the user is opted out, answered synchronously so it can seed `AnalyticsState(isOptedOut:)` when the store is built. At launch it reports the stored choice if there is one, and otherwise the default. With `optOutTrackingByDefault` and no stored choice it is `true` as soon as the initializer returns, although the SDK only applies that default on its queue a moment later and reads as opted in until then.

A change made through `setOptedOut(_:)`, `optOutTracking()`, or `optInTracking(distinctID:properties:)` shows by the time the call returns, unless another change has landed after it; read while a change is still in progress, it gives the old value or the new one. `reset()` does not change it. With `init(instance:)` it reads only `MixpanelInstance.hasOptedOutTracking()`, so it shows opted in until the SDK has applied its `optOutTrackingByDefault`.

## See Also

- <doc:HowToImplementService>
- <doc:ValueTranslation>
- <doc:RecordingServiceReference>
- ``MixpanelAnalyticsService``
