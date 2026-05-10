# Service Reference

API reference for ``MixpanelAnalyticsService`` — the Mixpanel-backed `AnalyticsService` conformer that the analytics plugin consumes.

## Overview

`MixpanelAnalyticsService` adapts a `MixpanelInstance` to the `AnalyticsService` protocol that `SwiduxAnalytics.AnalyticsPlugin` requires. It does one job: forward `AnalyticsEvent`, identify, alias, reset, and flush calls to the underlying SDK while translating `AnalyticsValue` into Mixpanel's `Properties` payload. Configuration of the Mixpanel SDK itself remains the caller's responsibility.

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
    public init()
    public init(instance: MixpanelInstance)
}
```

Value type holding a single reference to a `MixpanelInstance`. `@unchecked Sendable` is justified by Mixpanel's documented thread-safety. Cheap to pass into `AnalyticsPlugin`.

#### Initializers

```swift
public init()
```

Wraps `Mixpanel.mainInstance()`. You must call `Mixpanel.initialize(token:trackAutomaticEvents:)` (or a macOS-equivalent overload) before constructing the service — `Mixpanel.mainInstance()` traps when uninitialized.

```swift
public init(instance: MixpanelInstance)
```

Wraps an explicitly-provided instance. Use this when the app runs multiple Mixpanel projects under named instances.

#### `track(_:) async`

Forwards to `MixpanelInstance.track(event:properties:)`. Empty `properties` are passed as `nil` rather than an empty dictionary. Returns immediately; Mixpanel batches and flushes on its own schedule.

#### `identify(userID:properties:) async`

Forwards to `MixpanelInstance.identify(distinctId:)`, then — if `properties` is non-empty — calls `instance.people.set(properties:)` to update people-level properties.

#### `alias(newID:previousID:) async`

Forwards to `MixpanelInstance.createAlias(_:distinctId:)`. When `previousID` is `nil`, the call uses `instance.distinctId` as the source ID, matching Mixpanel's recommended anonymous-to-identified aliasing flow.

#### `reset() async`

Forwards to `MixpanelInstance.reset(completion:)` and awaits its callback. Clears Mixpanel's local distinct ID, super properties, and identity.

#### `flush() async`

Forwards to `MixpanelInstance.flush(completion:)` and awaits its callback. The plugin's own `flush()` is the deterministic sync point in tests — it awaits all pending fire-and-forget tracking tasks and then calls this.

## See Also

- <doc:HowToImplementService>
- <doc:ValueTranslation>
- <doc:MockServiceReference>
- ``MixpanelAnalyticsService``
