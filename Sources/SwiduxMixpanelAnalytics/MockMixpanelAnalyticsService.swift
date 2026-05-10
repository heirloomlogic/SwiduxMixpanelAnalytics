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
}
