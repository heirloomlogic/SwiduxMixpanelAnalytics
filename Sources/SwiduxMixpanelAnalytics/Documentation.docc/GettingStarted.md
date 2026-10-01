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
        _store = State(
            wrappedValue: AppStore.configured(
                analyticsService: analyticsService,
                onConsentChange: { await analyticsService.setOptedOut($0) }
            ))
    }

    var body: some Scene {
        WindowGroup { ContentView().environment(store) }
    }
}
```

The initializer takes most of the settings the app would otherwise pass to `Mixpanel.initialize` (EU `serverURL`, `optOutTrackingByDefault`, `flushInterval`, `instanceName`, `superProperties`, `useGzipCompression`, `trackAutomaticEvents`, `excludeProperties`, `useUniqueDistinctId`, `deviceIdProvider`), plus `loggingEnabled` and `useIPAddressForGeoLocation`, which the SDK only offers as instance properties. It is identical on every platform. Pick what you need; everything else has a sensible default. See <doc:HowToImplementService> for the longer treatment.

## Register the plugin with `MixpanelAnalyticsService`

Pass the service to `AnalyticsPlugin` in your `Store.configured()` factory:

```swift
import Swidux
import SwiduxAnalytics
import SwiduxMixpanelAnalytics

extension Store where State == AppState, Action == AppAction {
    static func configured(
        analyticsService: some AnalyticsService,
        onConsentChange: (@Sendable (Bool) async -> Void)? = nil
    ) -> AppStore {
        let plugins = PluginHost<AppState, AppAction>()

        plugins.register(
            AnalyticsPlugin<AppState, AppAction>(
                state: \.analytics,
                action: AppAction.analytics,
                extractAction: { if case .analytics(let a) = $0 { return a }; return nil },
                service: analyticsService,
                mapper: analyticsMapper,
                identity: analyticsIdentity,
                onConsentChange: onConsentChange
            )
        )

        var initialState = AppState()
        initialState.analytics = AnalyticsState(isOptedOut: ConsentStore.isOptedOut)

        return Store(
            initialState: initialState,
            reducer: AppReducer().reduce,
            plugins: plugins
        )
    }
}
```

That's it — the plugin will route mapped events through the service, re-fire `identify` whenever the `(userID, userProperties)` pair derived from state changes, and flush on your call to `store.analyticsPlugin.flush()` from `scenePhase == .background`.

## Keep consent in one place

The plugin's `isOptedOut` flag and Mixpanel's own opt-out must agree. `onConsentChange` keeps them in step whenever the app dispatches `.analytics(.setOptedOut(_:))`, but the plugin's flag starts from whatever `AppState()` gives it — `false` by default — while `optOutTrackingByDefault: true` starts Mixpanel opted out. Left like that, the plugin identifies the user at launch, Mixpanel drops the call, and the plugin never retries it.

So keep the user's consent choice in your own storage (`ConsentStore` above stands in for it — `UserDefaults` is fine), seed `AnalyticsState(isOptedOut:)` from it as shown, and dispatch the stored value once at launch — from your root view's `.task` — so Mixpanel matches it:

```swift
.task { store.send(.analytics(.setOptedOut(ConsentStore.isOptedOut))) }
```

If Mixpanel's own record of the choice is enough, seed the flag from the service's synchronous `isOptedOut` instead. The two then agree from the start, and no launch dispatch is needed; see <doc:HowToImplementService>. Consent changes and `reset()` do erase Mixpanel's stored choice for a moment before writing it back. An app killed in that moment starts the next launch from `optOutTrackingByDefault`. Keeping your own copy and dispatching it at launch, as above, covers that case.

Repeating a consent value is harmless: opting in a user who already consented sends nothing, and opting out an opted-out user does nothing.

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
- <doc:HowToPreviewAndTest> — Drive analytics state from previews and tests with a recorder instead of the SDK.
- <doc:ValueTranslation> — How `AnalyticsValue` cases map onto Mixpanel `Properties`.
