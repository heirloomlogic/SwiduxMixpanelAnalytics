# Getting Started with SwiduxMixpanelAnalytics

Add the package, build `MixpanelAnalyticsService` with your token, register the analytics plugin, and start dispatching events.

## Overview

This guide is the shortest path from a wired Swidux app with `SwiduxAnalytics` registered to events landing in Mixpanel. It assumes you have already followed Swidux's [Add Analytics](https://heirloomlogic.github.io/Swidux/documentation/swidux/howtoaddanalytics) guide through Step 5 — that is, your `AppState` has an `analytics` slice, your `AppAction` routes `.analytics(_:)`, and you have an `AnalyticsMapper` declared.

## Add the package

**Xcode:** File > Add Package Dependencies, paste `https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics`. Add the `SwiduxMixpanelAnalytics` product to your target.

**Package.swift:**

```swift
.package(url: "https://github.com/HeirloomLogic/SwiduxMixpanelAnalytics", from: "1.0.0"),
```

```swift
.product(name: "SwiduxMixpanelAnalytics", package: "SwiduxMixpanelAnalytics"),
```

## Build the service at launch

`MixpanelAnalyticsService` owns `Mixpanel.initialize` internally — you do not need to `import Mixpanel`. Construct the service with your token (and any Mixpanel knobs you care about) before configuring the store:

```swift
import SwiduxMixpanelAnalytics
import SwiftUI

@main
struct MyApp: App {
    @State private var store: AppStore

    init() {
        let analyticsService = MixpanelAnalyticsService(
            token: "your-mixpanel-token",
            optOutTrackingByDefault: true
        )
        _store = State(wrappedValue: AppStore.configured(analyticsService: analyticsService))
    }

    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}
```

The initializer surfaces every Mixpanel knob the app would otherwise need to set on `Mixpanel.initialize` (EU `serverURL`, `optOutTrackingByDefault`, `flushInterval`, `instanceName`, `superProperties`, `useGzipCompression`, `trackAutomaticEvents`, `excludeProperties`) and is identical on every platform. Pick what you need; everything else has a sensible default. See <doc:HowToImplementService> for the longer treatment.

## Register the plugin with `MixpanelAnalyticsService`

Pass the service to `AnalyticsPlugin` in your `Store.configured()` factory:

```swift
import Swidux
import SwiduxAnalytics
import SwiduxMixpanelAnalytics

extension Store where State == AppState, Action == AppAction {
    static func configured(analyticsService: some AnalyticsService) -> AppStore {
        let plugins = PluginHost<AppState, AppAction>()

        plugins.register(
            AnalyticsPlugin<AppState, AppAction>(
                state: \.analytics,
                action: AppAction.analytics,
                extractAction: { if case .analytics(let a) = $0 { return a }; return nil },
                service: analyticsService,
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

That's it — the plugin will route mapped events through the service, re-fire `identify` whenever the `(userID, userProperties)` pair derived from state changes, and flush on your call to `store.analyticsPlugin.flush()` from `scenePhase == .background`.

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

- <doc:HowToImplementService> — EU residency, opt-out by default, multiple Mixpanel projects, the `MixpanelInstance` escape hatch.
- <doc:HowToPreviewAndTest> — Drive analytics state from previews and tests using ``MockMixpanelAnalyticsService``.
- <doc:ValueTranslation> — How `AnalyticsValue` cases map onto Mixpanel `Properties`.
