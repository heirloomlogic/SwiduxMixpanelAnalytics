# Getting Started with SwiduxMixpanelAnalytics

Add the package, initialize Mixpanel, register the analytics plugin with `MixpanelAnalyticsService`, and start dispatching events.

## Overview

This guide is the shortest path from a wired Swidux app with `SwiduxAnalytics` registered to events landing in Mixpanel. It assumes you have already followed Swidux's [Add Analytics](https://heirloomlogic.github.io/Swidux/documentation/swidux/howtoaddanalytics) guide through Step 5 — that is, your `AppState` has an `analytics` slice, your `AppAction` routes `.analytics(_:)`, and you have an `AnalyticsMapper` declared.

## Add the package

**Xcode:** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics`. Add the `SwiduxMixpanelAnalytics` product to your target.

**Package.swift:**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics", branch: "main"),
```

```swift
.product(name: "SwiduxMixpanelAnalytics", package: "SwiduxMixpanelAnalytics"),
```

## Initialize Mixpanel at launch

`MixpanelAnalyticsService()` wraps `Mixpanel.mainInstance()`. Initialize Mixpanel before constructing the store so the main instance is ready:

```swift
import Mixpanel
import SwiftUI

@main
struct MyApp: App {
    @State private var store: AppStore

    init() {
        Mixpanel.initialize(token: "your-mixpanel-token", trackAutomaticEvents: false)
        _store = State(wrappedValue: AppStore.configured())
    }

    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}
```

`Mixpanel.initialize` exposes additional knobs (EU server URL, opt-out by default, super properties); pick the overload that fits your app and call it once. See the [Mixpanel iOS SDK](https://github.com/mixpanel/mixpanel-swift) for the full list.

## Register the plugin with `MixpanelAnalyticsService`

Pass `MixpanelAnalyticsService()` to `AnalyticsPlugin` in your `Store.configured()` factory:

```swift
import Swidux
import SwiduxAnalytics
import SwiduxMixpanelAnalytics

extension Store where State == AppState, Action == AppAction {
    static func configured() -> AppStore {
        let plugins = PluginHost<AppState, AppAction>()

        plugins.register(
            AnalyticsPlugin<AppState, AppAction>(
                state: \.analytics,
                action: AppAction.analytics,
                extractAction: { if case .analytics(let a) = $0 { return a }; return nil },
                service: MixpanelAnalyticsService(),
                mapper: analyticsMapper,
                identity: analyticsIdentity
            )
        )

        return Store(
            initialState: AppState(),
            reducer: AppReducer().reduce,
            plugins: plugins
        )
    }
}
```

That's it — the plugin will route mapped events through the service, auto-identify the user when `analyticsIdentity.userID` returns a value, and flush on your call to `store.analyticsPlugin.flush()` from `scenePhase == .background`.

## Verify the wiring

Dispatch a screen view from your root view's `.onAppear` and confirm the event arrives in Mixpanel's Live View:

```swift
struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        RootContent()
            .onAppear { store.send(.analytics(.screenView("Home"))) }
    }
}
```

## Next Steps

- <doc:HowToImplementService> — `Mixpanel.initialize` overloads, EU residency, opt-out by default.
- <doc:HowToPreviewAndTest> — Drive analytics state from previews and tests using ``MockMixpanelAnalyticsService``.
- <doc:ValueTranslation> — How `AnalyticsValue` cases map onto Mixpanel `Properties`.
