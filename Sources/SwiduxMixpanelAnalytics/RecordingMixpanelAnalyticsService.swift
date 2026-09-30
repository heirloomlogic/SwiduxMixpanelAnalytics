//
//  RecordingMixpanelAnalyticsService.swift
//  SwiduxMixpanelAnalytics
//

import SwiduxAnalytics

/// Recording stand-in for ``MixpanelAnalyticsService``, for SwiftUI previews
/// and Swift Testing suites.
///
/// The five `AnalyticsService` calls go to ``recorder``, a
/// `RecordingAnalyticsService` from `SwiduxAnalytics`, so assertions about
/// them read the same as they would for any other provider. This type adds
/// recorded versions of the Mixpanel-only controls: consent, SDK logging,
/// and geolocation by IP.
///
/// Opting in or out also records `.setOptedOut(_:)` in `recorder.calls`, so
/// one ordered log shows consent changes next to the service calls. Wire
/// ``setOptedOut(_:)`` as the plugin's `onConsentChange` hook exactly as for
/// the real service.
///
/// The recorder keeps every call, including ones the real service would
/// drop while opted out. Assert consent through ``hasOptedOutTracking()`` or
/// the `.setOptedOut` entries, not the absence of events.
///
/// > Warning: The recorder's log grows without limit, so this is not a
/// > production service. `RecordingAnalyticsService` logs a fault at init
/// > in Release builds.
public actor RecordingMixpanelAnalyticsService: AnalyticsService {
    /// The arguments of one ``optInTracking(distinctID:properties:)`` call.
    public struct OptInCall: Sendable, Equatable {
        /// The distinct ID passed to opt-in, or `nil`.
        public let distinctID: String?
        /// The `$opt_in` event properties passed to opt-in, or `nil`.
        public let properties: [String: AnalyticsValue]?

        /// Creates a record, e.g. as the expected value in an assertion.
        public init(distinctID: String? = nil, properties: [String: AnalyticsValue]? = nil) {
            self.distinctID = distinctID
            self.properties = properties
        }
    }

    /// Records every `AnalyticsService` call and every consent change, in
    /// arrival order.
    public let recorder = RecordingAnalyticsService()

    /// Every ``optInTracking(distinctID:properties:)`` call, in order.
    public private(set) var optInCalls: [OptInCall] = []
    private var optedOut: Bool
    /// The last value passed to ``setLoggingEnabled(_:)``, or `nil`.
    public private(set) var loggingEnabled: Bool?
    /// The last value passed to ``setUseIPAddressForGeoLocation(_:)``, or `nil`.
    public private(set) var useIPAddressForGeoLocation: Bool?

    /// Creates a recording service.
    ///
    /// - Parameter optedOut: The initial opt-out state, standing in for the
    ///   real service's `optOutTrackingByDefault`. Defaults to `false`.
    public init(optedOut: Bool = false) {
        self.optedOut = optedOut
    }

    /// Records the call in ``recorder``.
    public func track(_ event: AnalyticsEvent) async {
        await recorder.track(event)
    }

    /// Records the call in ``recorder``.
    public func identify(userID: String, properties: [String: AnalyticsValue]) async {
        await recorder.identify(userID: userID, properties: properties)
    }

    /// Records the call in ``recorder``.
    public func alias(newID: String, previousID: String?) async {
        await recorder.alias(newID: newID, previousID: previousID)
    }

    /// Records the call in ``recorder``.
    public func reset() async {
        await recorder.reset()
    }

    /// Records the call in ``recorder``.
    public func flush() async {
        await recorder.flush()
    }

    /// Calls ``optOutTracking()`` for `true` and ``optInTracking(distinctID:properties:)``
    /// for `false`, as the real service does.
    public func setOptedOut(_ optedOut: Bool) async {
        if optedOut {
            await optOutTracking()
        } else {
            await optInTracking()
        }
    }

    /// Opts out and records `.setOptedOut(true)` in ``recorder``.
    public func optOutTracking() async {
        optedOut = true
        await recorder.setOptedOut(true)
    }

    /// Appends to ``optInCalls``, opts in, and records `.setOptedOut(false)`
    /// in ``recorder``.
    public func optInTracking(
        distinctID: String? = nil,
        properties: [String: AnalyticsValue]? = nil
    ) async {
        optInCalls.append(OptInCall(distinctID: distinctID, properties: properties))
        optedOut = false
        await recorder.setOptedOut(false)
    }

    /// Returns the state set by the last opt-in or opt-out, or the `optedOut`
    /// passed to init if neither has been called.
    public func hasOptedOutTracking() async -> Bool {
        optedOut
    }

    /// Records the requested logging state in ``loggingEnabled``.
    public func setLoggingEnabled(_ enabled: Bool) async {
        loggingEnabled = enabled
    }

    /// Records the requested geo-by-IP state in ``useIPAddressForGeoLocation``.
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async {
        useIPAddressForGeoLocation = enabled
    }
}
