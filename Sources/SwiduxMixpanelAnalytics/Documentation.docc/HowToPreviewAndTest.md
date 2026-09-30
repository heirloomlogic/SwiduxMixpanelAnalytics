# How to Preview and Test

Drive `AnalyticsService` from SwiftUI previews and Swift Testing suites without touching Mixpanel's network.

## Overview

`MixpanelAnalyticsService` calls into a real `MixpanelInstance`. Previews and tests use a recorder instead. There are two:

- `RecordingAnalyticsService`, from `SwiduxAnalytics`, records every service call. Use it for tests that only check what the plugin sent. Those tests don't mention Mixpanel, so they stay the same if the app changes provider.
- ``RecordingMixpanelAnalyticsService`` adds recorded versions of Mixpanel's consent, logging, and geolocation controls. Use it where the code under test calls those controls.

Neither needs the Mixpanel SDK at runtime or touches the network.

## In a SwiftUI preview

Inject a recorder-backed store so the analytics work runs without the SDK:

```swift
#Preview {
    let store = AppStore.configured(analyticsService: RecordingAnalyticsService())
    return ContentView().environment(store)
}
```

This requires that `AppStore.configured` accepts an injected `AnalyticsService`. See Swidux's [Add Analytics](https://heirloomlogic.github.io/Swidux/documentation/swidux/howtoaddanalytics) guide for the factory pattern.

## In a Swift Testing suite

Use the recorder to verify mapper behavior. Await the plugin's `flush()` so every queued call has arrived before you assert:

```swift
import SwiduxAnalytics
import Testing

@Test
func incrementMapsToCounterAdded() async {
    let recorder = RecordingAnalyticsService()
    let store = AppStore.configured(analyticsService: recorder)

    store.send(.counter(.increment(5)))
    await store.analyticsPlugin.flush()

    let events = await recorder.trackedEvents
    #expect(events.first?.name == "counter_added")
    #expect(events.first?.properties["amount"] == .int(5))
}
```

## Asserting on identify and alias

The recorder keeps identify and alias calls in order:

```swift
@Test
func userSignInIdentifies() async {
    let recorder = RecordingAnalyticsService()
    let store = AppStore.configured(analyticsService: recorder)

    store.send(.auth(.signIn(userID: "user-1")))
    await store.analyticsPlugin.flush()

    let calls = await recorder.identifyCalls
    #expect(calls == [.init(userID: "user-1", properties: ["tier": .string("free")])])
}
```

## Asserting on consent

Wire the consent hook to ``RecordingMixpanelAnalyticsService/setOptedOut(_:)``, as you would for the real service. Opt-ins and opt-outs then appear in `recorder.calls` next to the service calls, which lets you check their order:

```swift
@Test
func optOutStopsMixpanelBeforeReset() async {
    let service = RecordingMixpanelAnalyticsService()
    let store = AppStore.configured(
        analyticsService: service,
        onConsentChange: { await service.setOptedOut($0) }
    )

    store.send(.analytics(.setOptedOut(true)))
    await store.analyticsPlugin.flush()

    #expect(await service.recorder.calls == [.setOptedOut(true), .reset, .flush])
    #expect(await service.hasOptedOutTracking())
}
```

A test that doesn't need the Mixpanel controls can wire the hook to `RecordingAnalyticsService.setOptedOut(_:)` instead and assert the same `calls`.

Both recorders are actors, so read their properties with `await`.

## See Also

- <doc:GettingStarted>
- <doc:RecordingServiceReference>
