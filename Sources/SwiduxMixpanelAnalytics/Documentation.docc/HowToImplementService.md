# How to Implement the Service

Configure the underlying `MixpanelInstance` to match your privacy, residency, and batching needs, then hand it to ``MixpanelAnalyticsService``.

## Overview

`MixpanelAnalyticsService` is intentionally thin: it wraps a `MixpanelInstance` and forwards every `AnalyticsService` call. All Mixpanel-specific configuration — region, opt-out defaults, flush interval, automatic events — happens at `Mixpanel.initialize` time, before the service is constructed. This keeps the service surface minimal and lets you use any of the SDK's `initialize` overloads.

## Default initialization

For most apps:

```swift
Mixpanel.initialize(token: "your-token", trackAutomaticEvents: false)
let service = MixpanelAnalyticsService()
```

`MixpanelAnalyticsService()` wraps `Mixpanel.mainInstance()`. It traps if Mixpanel has not been initialized first.

## EU / India data residency

Pass `serverURL:` (iOS) when initializing:

```swift
Mixpanel.initialize(
    token: "your-token",
    trackAutomaticEvents: false,
    serverURL: "https://api-eu.mixpanel.com"  // or "https://api-in.mixpanel.com"
)
```

The service has no per-event region knob — region is a property of the instance.

## Opt-out by default

If your jurisdiction requires explicit opt-in, initialize Mixpanel in opted-out mode:

```swift
Mixpanel.initialize(
    token: "your-token",
    trackAutomaticEvents: false,
    optOutTrackingByDefault: true
)
```

Then pair this with the plugin's own `.analytics(.setOptedOut(false))` action when the user opts in. The plugin's opt-out flag and Mixpanel's are tracked separately; both must be opted-in for events to be sent.

## Flush interval

Mixpanel's default 60-second flush interval is set at initialization:

```swift
Mixpanel.initialize(token: "your-token", trackAutomaticEvents: false, flushInterval: 30)
```

The plugin's `flush()` (called on app shutdown) bypasses this and forces a synchronous drain.

## Multiple instances

If your app sends to more than one Mixpanel project, initialize each instance with a name and construct one service per instance:

```swift
let prod = Mixpanel.initialize(
    token: "prod-token",
    trackAutomaticEvents: false,
    instanceName: "prod"
)
let analytics = Mixpanel.initialize(
    token: "internal-token",
    trackAutomaticEvents: false,
    instanceName: "internal"
)

let prodService = MixpanelAnalyticsService(instance: prod)
let analyticsService = MixpanelAnalyticsService(instance: analytics)
```

Register one `AnalyticsPlugin` per service. Each plugin owns its own state slice.

## See Also

- <doc:GettingStarted>
- <doc:ServiceReference>
- <doc:ValueTranslation>
