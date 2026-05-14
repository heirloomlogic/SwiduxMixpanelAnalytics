# How to Implement the Service

Configure `MixpanelAnalyticsService` to match your privacy, residency, and batching needs — without `import Mixpanel` in your app.

## Overview

``MixpanelAnalyticsService`` is the configuration boundary: every Mixpanel knob worth setting at launch is a parameter on the initializer, and runtime GDPR / diagnostic toggles are methods on the service. The Mixpanel SDK stays a private implementation detail of this package.

## Default initialization

For most apps:

```swift
let service = MixpanelAnalyticsService(token: "your-token")
```

Defaults match the Mixpanel SDK: `flushInterval: 60`, `optOutTrackingByDefault: false`, gzip off, IDFV-based distinct ID. On iOS / tvOS / watchOS, `trackAutomaticEvents` defaults to `false`.

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

If your jurisdiction requires explicit opt-in, construct the service in opted-out mode and flip it at runtime when the user consents:

```swift
let service = MixpanelAnalyticsService(
    token: "your-token",
    optOutTrackingByDefault: true
)

// later, when the user opts in:
await service.optInTracking(distinctID: currentUserID)

// to opt out again:
await service.optOutTracking()
```

`optInTracking` / `optOutTracking` / ``MixpanelAnalyticsService/hasOptedOutTracking()`` cover the GDPR round-trip without forcing the app to touch Mixpanel directly. Pair these with the plugin's own opt-out flag if you maintain one — both must be opted in for events to be sent.

## Flush interval

```swift
let service = MixpanelAnalyticsService(token: "your-token", flushInterval: 30)
```

The plugin's `flush()` (called on app shutdown) bypasses this and forces a synchronous drain.

## Diagnostic logging

```swift
await service.setLoggingEnabled(true)
```

Enables the Mixpanel SDK's internal logging — useful when verifying integration in development. Disable in release builds.

## Geo by IP

```swift
await service.setUseIPAddressForGeoLocation(false)
```

Opt out of server-side IP-based geo resolution when your privacy policy forbids it.

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
    token: "your-token",
    trackAutomaticEvents: false,
    proxyServerConfig: myProxyConfig
)
let service = MixpanelAnalyticsService(instance: instance)
```

This is the only path that requires importing Mixpanel into your app. If you find yourself reaching for it for something common (an SDK knob the initializer should surface), please open an issue — the goal is to keep the happy path Mixpanel-free.

## See Also

- <doc:GettingStarted>
- <doc:ServiceReference>
- <doc:ValueTranslation>
