//
//  MockMixpanelAnalyticsService.swift
//  SwiduxMixpanelAnalytics
//

import SwiduxAnalytics

/// Recording `AnalyticsService` for previews and Swift Testing suites.
///
/// Captures every call so tests can `#expect` against `trackedEvents`,
/// `identifyCalls`, `aliasCalls`, `resetCount`, and `flushCount` after
/// awaiting the plugin's `flush()` sync point.
///
/// Mirrors the Mixpanel-specific runtime surface on
/// ``MixpanelAnalyticsService`` (opt-out / opt-in / logging / geo) so test
/// code that exercises GDPR or diagnostic flows can verify the same calls
/// against either the real adapter or the mock.
///
/// > Note: Unlike the real SDK, the mock keeps recording `track` / `identify`
/// > calls while opted out — a recording mock should never lose history. To
/// > assert consent behavior, check ``optedOut`` (or
/// > ``hasOptedOutTracking()``) rather than the absence of recorded events.
public actor MockMixpanelAnalyticsService: AnalyticsService {
    /// Captured arguments from a single `identify(userID:properties:)` call.
    public struct IdentifyCall: Sendable, Equatable {
        /// The distinct user ID passed to `identify`.
        public let userID: String
        /// People-level properties captured at identify time.
        public let properties: [String: AnalyticsValue]
    }

    /// Captured arguments from a single `alias(newID:previousID:)` call.
    public struct AliasCall: Sendable, Equatable {
        /// The new alias to assign.
        public let newID: String
        /// The previous distinct ID, or `nil` to use the current one.
        public let previousID: String?
    }

    /// Captured arguments from a single
    /// `optInTracking(distinctID:properties:)` call.
    public struct OptInCall: Sendable, Equatable {
        /// The distinct ID passed to opt-in, or `nil`.
        public let distinctID: String?
        /// The people-profile properties recorded at opt-in, or `nil`.
        public let properties: [String: AnalyticsValue]?
    }

    /// Every event recorded by `track(_:)`, in dispatch order.
    public private(set) var trackedEvents: [AnalyticsEvent] = []
    /// Every `(userID, properties)` pair recorded by `identify(userID:properties:)`.
    public private(set) var identifyCalls: [IdentifyCall] = []
    /// Every `(newID, previousID)` pair recorded by `alias(newID:previousID:)`.
    public private(set) var aliasCalls: [AliasCall] = []
    /// Number of times `reset()` was called.
    public private(set) var resetCount = 0
    /// Number of times `flush()` was called.
    public private(set) var flushCount = 0
    /// Number of times `optOutTracking()` was called.
    public private(set) var optOutCount = 0
    /// Every opt-in call recorded by `optInTracking(distinctID:properties:)`.
    public private(set) var optInCalls: [OptInCall] = []
    /// The mock's current opt-out state, toggled by
    /// `optOutTracking()` / `optInTracking(distinctID:properties:)`.
    public private(set) var optedOut = false
    /// Last value passed to `setLoggingEnabled(_:)`. `nil` if never set.
    public private(set) var loggingEnabled: Bool?
    /// Last value passed to `setUseIPAddressForGeoLocation(_:)`. `nil` if
    /// never set.
    public private(set) var useIPAddressForGeoLocation: Bool?

    /// Creates an empty recording service.
    public init() {}

    /// Records the event in `trackedEvents`.
    public func track(_ event: AnalyticsEvent) async {
        trackedEvents.append(event)
    }

    /// Records the identify call in `identifyCalls`.
    public func identify(userID: String, properties: [String: AnalyticsValue]) async {
        identifyCalls.append(IdentifyCall(userID: userID, properties: properties))
    }

    /// Records the alias call in `aliasCalls`.
    public func alias(newID: String, previousID: String?) async {
        aliasCalls.append(AliasCall(newID: newID, previousID: previousID))
    }

    /// Increments `resetCount`.
    public func reset() async {
        resetCount += 1
    }

    /// Increments `flushCount`.
    public func flush() async {
        flushCount += 1
    }

    /// Increments `optOutCount` and flips `optedOut` to `true`.
    public func optOutTracking() async {
        optOutCount += 1
        optedOut = true
    }

    /// Records the opt-in call and flips `optedOut` to `false`.
    public func optInTracking(
        distinctID: String? = nil,
        properties: [String: AnalyticsValue]? = nil
    ) async {
        optInCalls.append(OptInCall(distinctID: distinctID, properties: properties))
        optedOut = false
    }

    /// Returns the mock's tracked opt-out state.
    public func hasOptedOutTracking() async -> Bool {
        optedOut
    }

    /// Records the requested logging state.
    public func setLoggingEnabled(_ enabled: Bool) async {
        loggingEnabled = enabled
    }

    /// Records the requested geo-by-IP state.
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async {
        useIPAddressForGeoLocation = enabled
    }
}
