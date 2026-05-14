//
//  MixpanelAnalyticsServiceTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import Mixpanel
import SwiduxAnalytics
import Testing

@testable import SwiduxMixpanelAnalytics

/// Smoke tests for the real Mixpanel-backed service. The Mixpanel SDK queues
/// to local disk when offline, so `flush()` resolves without a network round
/// trip. We do not assert on outbound network state — only that the service's
/// async surface returns and the `AnalyticsService` contract holds.
@Suite("MixpanelAnalyticsService")
struct MixpanelAnalyticsServiceTests {
    /// Constructs a service via the public token init, with a unique
    /// `instanceName` per test so suites can run in parallel.
    private static func makeService(name: String = #function) -> MixpanelAnalyticsService {
        #if os(macOS)
        return MixpanelAnalyticsService(
            token: "test-token",
            instanceName: name,
            optOutTrackingByDefault: true
        )
        #else
        return MixpanelAnalyticsService(
            token: "test-token",
            trackAutomaticEvents: false,
            instanceName: name,
            optOutTrackingByDefault: true
        )
        #endif
    }

    @Test func conformsToAnalyticsServiceAndSendable() {
        let _: any AnalyticsService.Type = MixpanelAnalyticsService.self
        let _: any Sendable.Type = MixpanelAnalyticsService.self
    }

    @Test func trackResolvesWithoutThrowing() async {
        let service = Self.makeService()
        await service.track(AnalyticsEvent("smoke", ["amount": .int(1)]))
    }

    @Test func identifyAliasResetFlushAllResolve() async {
        let service = Self.makeService()
        await service.identify(userID: "u1", properties: ["tier": .string("free")])
        await service.alias(newID: "alias-1", previousID: "u1")
        await service.reset()
        await service.flush()
    }

    /// Repeated `identify` for the same `userID` must be idempotent updates,
    /// not alias rotations. We can't observe `people.set` directly, so this
    /// only smoke-tests resolution under rapid mutation.
    @Test func repeatedIdentifyCallsWithMutatingPropertiesResolve() async {
        let service = Self.makeService()
        await service.identify(userID: "u1", properties: ["is_pro": .bool(false)])
        await service.identify(userID: "u1", properties: ["is_pro": .bool(true)])
        await service.identify(
            userID: "u1",
            properties: [
                "is_pro": .bool(true),
                "experiment_variant": .string("b"),
            ])
        await service.flush()
    }

    @Test func flushContinuationResumes() async {
        let service = Self.makeService()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await service.flush() }
            await group.waitForAll()
        }
    }

    @Test func optOutAndOptInResolve() async {
        // Mixpanel's opt-out flag is updated on the SDK's internal serial
        // queue, so `hasOptedOutTracking()` can race the write — state
        // semantics live in `MockMixpanelAnalyticsServiceTests`. Here we
        // only verify the calls resolve without throwing.
        let service = Self.makeService()
        await service.optInTracking(
            distinctID: "u2",
            properties: ["tier": .string("pro")])
        await service.optOutTracking()
        _ = await service.hasOptedOutTracking()
    }

    @Test func setLoggingAndGeoTogglesResolve() async {
        let service = Self.makeService()
        await service.setLoggingEnabled(true)
        await service.setUseIPAddressForGeoLocation(false)
        await service.setLoggingEnabled(false)
    }

    /// Escape hatch: an app that constructs its own `MixpanelInstance` (e.g.,
    /// for `ProxyServerConfig`) can still wrap it. This is the only test path
    /// that touches `Mixpanel` directly.
    @Test func escapeHatchInitWrapsExplicitInstance() async {
        #if os(macOS)
        let instance = Mixpanel.initialize(
            token: "test-token",
            instanceName: "escape-hatch-mac",
            optOutTrackingByDefault: true
        )
        #else
        let instance = Mixpanel.initialize(
            token: "test-token",
            trackAutomaticEvents: false,
            instanceName: "escape-hatch-ios",
            optOutTrackingByDefault: true
        )
        #endif
        let service = MixpanelAnalyticsService(instance: instance)
        await service.track(AnalyticsEvent("escape-hatch"))
        await service.flush()
    }
}
