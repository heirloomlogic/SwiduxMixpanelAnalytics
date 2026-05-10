# How to Preview and Test

Drive `AnalyticsService` from SwiftUI previews and Swift Testing suites without touching Mixpanel's network.

## Overview

`MixpanelAnalyticsService` calls into a real `MixpanelInstance`. For previews and tests, swap it for ``MockMixpanelAnalyticsService`` — an actor that records every call and exposes its history for assertions. The mock has no Mixpanel dependency and runs offline.

## In a SwiftUI preview

Inject a mock-backed store and the analytics work flows without spinning up the SDK:

```swift
#Preview {
    let store = AppStore.configured(analyticsService: MockMixpanelAnalyticsService())
    return ContentView().environment(store)
}
```

This requires that `AppStore.configured` accepts an injected `AnalyticsService`. See Swidux's [Add Analytics](https://heirloomlogic.github.io/Swidux/documentation/swidux/howtoaddanalytics) guide for the factory pattern.

## In a Swift Testing suite

Use the mock to verify mapper behavior. Await the plugin's `flush()` to make assertions deterministic:

```swift
import SwiduxMixpanelAnalytics
import Testing

@Test
func incrementMapsToCounterAdded() async {
    let mock = MockMixpanelAnalyticsService()
    let store = AppStore.configured(analyticsService: mock)

    store.send(.counter(.increment(5)))
    await store.analyticsPlugin.flush()

    let events = await mock.trackedEvents
    #expect(events.first?.name == "counter_added")
    #expect(events.first?.properties["amount"] == .int(5))
}
```

## Asserting on identify and alias

The mock records identify and alias calls in order:

```swift
@Test
func userSignInIdentifies() async {
    let mock = MockMixpanelAnalyticsService()
    let store = AppStore.configured(analyticsService: mock)

    store.send(.auth(.signIn(userID: "user-1")))
    await store.analyticsPlugin.flush()

    let calls = await mock.identifyCalls
    #expect(calls == [.init(userID: "user-1", properties: ["tier": .string("free")])])
}
```

`MockMixpanelAnalyticsService` is an actor, so its accessors are async — wrap them in `await`.

## See Also

- <doc:GettingStarted>
- <doc:MockServiceReference>
