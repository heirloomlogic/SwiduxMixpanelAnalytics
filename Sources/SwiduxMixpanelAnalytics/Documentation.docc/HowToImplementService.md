# How to Implement the Service

Configure `MixpanelAnalyticsService` to match your privacy, residency, and batching needs — without `import Mixpanel` in your app.

## Overview

``MixpanelAnalyticsService`` is the configuration boundary: every Mixpanel knob worth setting at launch is a parameter on the initializer, and runtime GDPR / diagnostic toggles are methods on the service. The Mixpanel SDK stays a private implementation detail of this package.

## Default initialization

For most apps:

```swift
let service = MixpanelAnalyticsService(token: "your-token")
```

Defaults match the Mixpanel SDK's `MixpanelOptions`: `flushInterval: 60`, `optOutTrackingByDefault: false`, gzip on, a random-UUID anonymous ID, `trackAutomaticEvents: false`. The initializer is the same on every platform.

> Important: The Mixpanel SDK keys instances by `instanceName` (falling back to `token`). Constructing a second service with the same name returns the *existing* SDK instance and silently ignores the new options. Construct the service once, where the store is configured — not per view, per preview, or per test.

> Important: `serverURL` must be an absolute URL with a scheme and host. Requests to anything else fail, and a string that isn't a URL at all makes every `flush()` wait out the SDK's 120-second request timeout. The adapter asserts on this in Debug builds.

## EU / India data residency

Pass `serverURL:`:

```swift
let service = MixpanelAnalyticsService(
    token: "your-token",
    serverURL: "https://api-eu.mixpanel.com"  // or "https://api-in.mixpanel.com"
)
```

Region is fixed at construction; the service has no per-event region knob.

## Opt-out by default

If your jurisdiction requires explicit opt-in, construct the service in opted-out mode and hand ``MixpanelAnalyticsService/setOptedOut(_:)`` to the plugin as its consent hook:

```swift
let service = MixpanelAnalyticsService(
    token: "your-token",
    optOutTrackingByDefault: true
)

AnalyticsPlugin(
    state: \.analytics,
    action: AppAction.analytics,
    extractAction: { if case .analytics(let a) = $0 { a } else { nil } },
    service: service,
    onConsentChange: { await service.setOptedOut($0) }
)
```

From then on `store.send(.analytics(.setOptedOut(_:)))` switches both the plugin's gate and Mixpanel's own. Seed the plugin's `AnalyticsState(isOptedOut:)` from the consent your app stores, and dispatch that value once at launch — see <doc:GettingStarted>.

Both directions return only once the SDK has applied them, so an `identify` dispatched straight after consent is honored and one dispatched straight after withdrawal is dropped. Mixpanel remembers the choice across launches; `optOutTrackingByDefault` only decides the state before the user has chosen.

Opting out deletes whatever is still queued instead of sending it, then clears the local identity, without waiting for the network. An upload that has already started is not cancelled: the SDK checks consent only when a flush starts and between its event and profile queues, so a flush already sending events finishes sending the events it had read. Signing out with `.analytics(.reset)` is different; it sends the queue first, so events recorded before sign-out keep their user.

Opting out does **not** delete the user's Mixpanel profile or data. The SDK's own attempt at that is never sent, and the adapter discards it because it would later delete the next user's profile instead. Erase data with Mixpanel's GDPR deletion API from your server.

`optInTracking(distinctID:properties:)` and `optOutTracking()` remain available for apps that don't route consent through the plugin.

## Custom device IDs

By default Mixpanel makes the anonymous device ID a random UUID, which does not survive app reinstall. `useUniqueDistinctId: true` swaps it for the device's own identifier — the IDFV on iOS, but the Mac's **hardware serial number** on macOS, which most privacy policies won't allow. If your app maintains its own stable device identity — for example a Keychain-minted UUID hydrated into state at launch — hand it to the SDK with `deviceIdProvider:`:

```swift
// Cache the ID at launch; the provider must not do I/O inline.
let deviceID = keychainStore.value(.deviceID) ?? mintAndStoreDeviceID()

let service = MixpanelAnalyticsService(
    token: "your-token",
    deviceIdProvider: { deviceID }
)
```

The SDK calls the closure synchronously on every launch, on `reset()`, and on opt-out, some of those times while holding its internal lock — so it must be fast: return a cached value, never Keychain or network reads, and never call back into the service or Mixpanel, which deadlocks. Return `nil` or a blank string to fall back to the SDK default. Returning the same value every call keeps the device ID stable across resets; returning a fresh value gives ephemeral identities.

> Note: Adding a `deviceIdProvider` to an app that already shipped with the default device ID changes the anonymous identity on that device. The SDK logs a warning when the provided value differs from the persisted one.

## Flush interval

```swift
let service = MixpanelAnalyticsService(token: "your-token", flushInterval: 30)
```

`0` disables the timer. The plugin's `flush()` (called on app shutdown) bypasses the interval and sends everything queued, waiting for the network. The SDK sends one request per 50 records, each bounded at 120 seconds, so use the plugin's `flush(timeout:)` on shutdown paths.

## Diagnostic logging

```swift
await service.setLoggingEnabled(true)
```

Enables the Mixpanel SDK's internal logging — useful when verifying integration in development. Disable in release builds. Set it once at launch: the SDK doesn't synchronize this property.

## Geo by IP

```swift
await service.setUseIPAddressForGeoLocation(false)
```

Opt out of server-side IP-based geo resolution when your privacy policy forbids it. Set it once at launch, for the same reason as logging.

## Aliases and ID merge

Projects on Mixpanel's Simplified ID Merge (check your project's Identity Merge setting) ignore aliases: `identify` alone links the anonymous device to the signed-in user. Dispatch `.analytics(.alias(newID:previousID:))` only for projects on Original ID Merge. There, a `nil` `previousID` aliases the anonymous distinct ID the device's events were sent under, and the alias never changes who is identified locally.

## Switching users

When `identify` moves to a different user, the adapter first sends everything queued for the previous user and waits for it — the SDK otherwise sends every queued profile update under whoever is identified at send time. Dispatching `.analytics(.reset)` on sign-out is still the right shape; it also clears super properties set at runtime (the ones passed to the initializer come back automatically).

## Update and remove profile properties

A property left out of a later `identify` call is not sent, so the value Mixpanel already has stays. To delete a saved property, pass it as `.null`, which sends an `$unset` for that key:

```swift
// Sets `plan` and `experiment_variant`.
await service.identify(
    userID: "user-1",
    properties: ["plan": .string("pro"), "experiment_variant": .string("b")]
)

// Updates `plan`. `experiment_variant` keeps its value.
await service.identify(userID: "user-1", properties: ["plan": .string("team")])

// Deletes `experiment_variant`.
await service.identify(userID: "user-1", properties: ["experiment_variant": .null])
```

This holds when the plugin calls `identify` for you: if you drop a key from the `userProperties` derived from state, the saved value stays. To delete it, map the key to `.null`. Only a top-level `.null` deletes.

Each property you pass is sent whole, and the new value replaces the saved one. A null inside an array or dictionary is dropped before sending, so it does not delete anything by itself, but the rest of that value replaces the saved value. If `prefs` is saved as `{theme: dark}` and you identify with `["prefs": .dict(["theme": .null])]`, the adapter sends `prefs` as `{}` and `theme` is gone from the saved value. To keep the other entries of a dictionary, send them again. See <doc:ValueTranslation> for the translation rules.

Every `$set` the adapter sends also carries the SDK's own automatic people properties (for example `$ios_device_model` and `$swift_lib_version`), except any listed in `excludeProperties`. They are sent whenever a call has at least one property that is not null. A call whose properties are empty or all null sends no `$set`.

## Exclude properties

Strip named property keys from outgoing events and People `$set` / `$set_once` updates before the SDK stores or sends them — a construction-time guard against PII leaking through event properties:

```swift
let service = MixpanelAnalyticsService(
    token: "your-token",
    excludeProperties: ["email", "full_name"]
)
```

Excluded keys are dropped by the Mixpanel SDK itself, so the rule holds no matter which mapper or reducer produced the event. Other People operators (`$add`, `$append`, `$unset`, …) pass through unfiltered, and keys Mixpanel requires for ingestion (`distinct_id`, `token`, …) are never stripped even if listed.

## Multiple instances

If your app sends to more than one Mixpanel project, give each a unique `instanceName`:

```swift
let prodService = MixpanelAnalyticsService(
    token: "prod-token",
    instanceName: "prod"
)
let internalService = MixpanelAnalyticsService(
    token: "internal-token",
    instanceName: "internal"
)
```

Register one `AnalyticsPlugin` per service. Each plugin owns its own state slice.

## Escape hatch: build your own `MixpanelInstance`

For configuration the initializer does not surface — `ProxyServerConfig`, custom delegates, anything that requires direct access to `MixpanelInstance` — use ``MixpanelAnalyticsService/init(instance:)``:

```swift
import Mixpanel  // only required for this advanced path

let instance = Mixpanel.initialize(
    options: MixpanelOptions(
        token: "your-token",
        proxyServerConfig: myProxyConfig
    )
)
let service = MixpanelAnalyticsService(instance: instance)
```

This is the only path that requires importing Mixpanel into your app. If you find yourself reaching for it for something common (an SDK knob the initializer should surface), please open an issue — the goal is to keep the happy path Mixpanel-free.

## See Also

- <doc:GettingStarted>
- <doc:ServiceReference>
- <doc:ValueTranslation>
