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
    private static func makeInstance(name: String = #function) -> MixpanelInstance {
        #if os(macOS)
        return Mixpanel.initialize(
            token: "test-token",
            instanceName: name,
            optOutTrackingByDefault: true
        )
        #else
        return Mixpanel.initialize(
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
        let service = MixpanelAnalyticsService(instance: Self.makeInstance())
        await service.track(AnalyticsEvent("smoke", ["amount": .int(1)]))
    }

    @Test func identifyAliasResetFlushAllResolve() async {
        let service = MixpanelAnalyticsService(instance: Self.makeInstance())
        await service.identify(userID: "u1", properties: ["tier": .string("free")])
        await service.alias(newID: "alias-1", previousID: "u1")
        await service.reset()
        await service.flush()
    }

    @Test func flushContinuationResumes() async {
        let service = MixpanelAnalyticsService(instance: Self.makeInstance())
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await service.flush() }
            await group.waitForAll()
        }
    }
}
