//
//  MixpanelAnalyticsService.swift
//  SwiduxMixpanelAnalytics
//

import Mixpanel
import SwiduxAnalytics

/// `AnalyticsService` conformer that forwards to a Mixpanel SDK instance.
///
/// Configure Mixpanel at app launch (so you can pick the right `initialize`
/// overload for your platform and needs), then construct the service:
///
/// ```swift
/// Mixpanel.initialize(token: "your-token", trackAutomaticEvents: false)
/// let service = MixpanelAnalyticsService()
/// ```
///
/// `MixpanelInstance` is documented as thread-safe; this struct is
/// `@unchecked Sendable` to bridge that guarantee through Swift 6 strict
/// concurrency.
public struct MixpanelAnalyticsService: AnalyticsService, @unchecked Sendable {
    private let instance: MixpanelInstance

    /// Wraps `Mixpanel.mainInstance()`.
    ///
    /// You must call `Mixpanel.initialize(token:...)` before constructing the
    /// service.
    public init() {
        self.instance = Mixpanel.mainInstance()
    }

    /// Wraps an explicitly-provided Mixpanel instance — useful when the app
    /// runs multiple Mixpanel projects under named instances.
    public init(instance: MixpanelInstance) {
        self.instance = instance
    }

    /// Forwards an event to `MixpanelInstance.track(event:properties:)`. Empty
    /// `event.properties` are passed as `nil`.
    public func track(_ event: AnalyticsEvent) async {
        let properties: Properties? = event.properties.isEmpty ? nil : event.properties.toMixpanelProperties()
        instance.track(event: event.name, properties: properties)
    }

    /// Sets the active Mixpanel distinct ID and, if `properties` is non-empty,
    /// updates people-level properties via `instance.people.set`.
    public func identify(userID: String, properties: [String: AnalyticsValue]) async {
        instance.identify(distinctId: userID)
        if !properties.isEmpty {
            instance.people.set(properties: properties.toMixpanelProperties())
        }
    }

    /// Forwards to `MixpanelInstance.createAlias(_:distinctId:)`. When
    /// `previousID` is `nil`, the current `instance.distinctId` is used.
    public func alias(newID: String, previousID: String?) async {
        instance.createAlias(newID, distinctId: previousID ?? instance.distinctId)
    }

    /// Forwards to `MixpanelInstance.reset(completion:)` and awaits the
    /// completion callback before returning.
    public func reset() async {
        await withCheckedContinuation { continuation in
            instance.reset { continuation.resume() }
        }
    }

    /// Forwards to `MixpanelInstance.flush(completion:)` and awaits the
    /// completion callback before returning.
    public func flush() async {
        await withCheckedContinuation { continuation in
            instance.flush { continuation.resume() }
        }
    }
}
