//
//  MixpanelAnalyticsService.swift
//  SwiduxMixpanelAnalytics
//

import Mixpanel
import SwiduxAnalytics

/// `AnalyticsService` conformer that owns and forwards to a Mixpanel SDK
/// instance.
///
/// The adapter is the configuration boundary: pass the token and any other
/// Mixpanel knobs to ``init(token:trackAutomaticEvents:flushInterval:instanceName:optOutTrackingByDefault:useUniqueDistinctId:superProperties:serverURL:useGzipCompression:excludeProperties:)``
/// and the app never needs to `import Mixpanel`. The initializer is the same
/// on every platform; it builds a `MixpanelOptions` and calls
/// `Mixpanel.initialize(options:)`.
///
/// ```swift
/// let service = MixpanelAnalyticsService(
///     token: Secrets.mixpanelAPIKey,
///     optOutTrackingByDefault: true
/// )
/// ```
///
/// `MixpanelInstance` is documented as thread-safe; this struct is
/// `@unchecked Sendable` to bridge that guarantee through Swift 6 strict
/// concurrency.
public struct MixpanelAnalyticsService: AnalyticsService, @unchecked Sendable {
    private let instance: MixpanelInstance

    /// Initializes Mixpanel with the given token and wraps the resulting
    /// instance.
    ///
    /// Parameters mirror `MixpanelOptions`; the `superProperties` map is typed
    /// as `[String: AnalyticsValue]` so the app does not need to reference
    /// `MixpanelType`.
    ///
    /// - Parameters:
    ///   - token: The Mixpanel project token.
    ///   - trackAutomaticEvents: See the Mixpanel SDK docs for the list of
    ///     automatic events. Defaults to `false`.
    ///   - flushInterval: Seconds between automatic flushes. Defaults to `60`.
    ///   - instanceName: A name for this Mixpanel instance, allowing the app
    ///     to run multiple Mixpanel projects. Defaults to `nil` (main instance).
    ///   - optOutTrackingByDefault: If `true`, the SDK starts opted out. Flip
    ///     with ``optInTracking(distinctID:properties:)``. Defaults to `false`.
    ///   - useUniqueDistinctId: Use a UUID instead of the IDFV as the default
    ///     distinct ID. Defaults to `false`.
    ///   - superProperties: Properties attached to every event. Defaults to
    ///     `nil`.
    ///   - serverURL: Override the Mixpanel API base URL (e.g. EU residency).
    ///     Defaults to `nil`.
    ///   - useGzipCompression: Compress outbound requests with gzip. Defaults
    ///     to `true`, matching `MixpanelOptions`.
    ///   - excludeProperties: Property keys stripped from every event and
    ///     people update before they are stored or sent — e.g. keys that may
    ///     carry PII. Defaults to empty.
    public init(
        token: String,
        trackAutomaticEvents: Bool = false,
        flushInterval: Double = 60,
        instanceName: String? = nil,
        optOutTrackingByDefault: Bool = false,
        useUniqueDistinctId: Bool = false,
        superProperties: [String: AnalyticsValue]? = nil,
        serverURL: String? = nil,
        useGzipCompression: Bool = true,
        excludeProperties: Set<String> = []
    ) {
        self.instance = Mixpanel.initialize(
            options: MixpanelOptions(
                token: token,
                flushInterval: flushInterval,
                instanceName: instanceName,
                trackAutomaticEvents: trackAutomaticEvents,
                optOutTrackingByDefault: optOutTrackingByDefault,
                useUniqueDistinctId: useUniqueDistinctId,
                superProperties: Self.nonEmptyProperties(superProperties),
                serverURL: serverURL,
                useGzipCompression: useGzipCompression,
                excludeProperties: excludeProperties
            )
        )
    }

    private static func nonEmptyProperties(
        _ properties: [String: AnalyticsValue]?
    ) -> Properties? {
        guard let properties, !properties.isEmpty else { return nil }
        return properties.toMixpanelProperties()
    }

    /// Escape hatch for apps that need to construct their own `MixpanelInstance`
    /// (for example, to use `ProxyServerConfig`). Most apps should prefer the
    /// token-based initializer above and never `import Mixpanel`.
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

    /// Opts the user out of all tracking. Subsequent `track` / `identify`
    /// calls are dropped until ``optInTracking(distinctID:properties:)`` is
    /// called. Also clears the existing people profile and charges.
    public func optOutTracking() async {
        instance.optOutTracking()
    }

    /// Opts the user back into tracking and, if `distinctID` is provided,
    /// identifies them. Optional `properties` are recorded against the user
    /// profile; empty properties are passed as `nil`.
    public func optInTracking(
        distinctID: String? = nil,
        properties: [String: AnalyticsValue]? = nil
    ) async {
        instance.optInTracking(
            distinctId: distinctID,
            properties: Self.nonEmptyProperties(properties)
        )
    }

    /// `true` if the user has been opted out.
    public func hasOptedOutTracking() async -> Bool {
        instance.hasOptedOutTracking()
    }

    /// Toggles the Mixpanel SDK's internal logging.
    public func setLoggingEnabled(_ enabled: Bool) async {
        instance.loggingEnabled = enabled
    }

    /// Toggles whether Mixpanel uses the request's IP address for geo
    /// resolution.
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async {
        instance.useIPAddressForGeoLocation = enabled
    }
}
