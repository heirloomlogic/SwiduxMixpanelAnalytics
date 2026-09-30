//
//  MixpanelAnalyticsServiceTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import Foundation
import Mixpanel
import SwiduxAnalytics
import Testing

@testable import SwiduxMixpanelAnalytics

/// Smoke tests for the real Mixpanel-backed service: the async surface
/// resolves and the SDK is configured as asked. What reaches the wire is
/// asserted in `MixpanelCapturePipelineTests`, whose interceptor these tests
/// also send through, so nothing leaves the process.
@Suite("MixpanelAnalyticsService", .timeLimit(.minutes(1)))
struct MixpanelAnalyticsServiceTests {
    private static let serverURL =
        "https://\(MixpanelCapturePipelineTests.MixpanelCaptureURLProtocol.host)"

    /// Constructs a service via the public token init, with a unique
    /// `instanceName` per run so suites can run in parallel and never inherit
    /// a previous run's persisted state.
    private static func makeService(optOutTrackingByDefault: Bool = true) -> MixpanelAnalyticsService {
        _ = MixpanelCapturePipelineTests.MixpanelCaptureURLProtocol.registerOnce
        return MixpanelAnalyticsService(
            token: "test-token",
            trackAutomaticEvents: false,
            instanceName: "smoke-\(UUID().uuidString)",
            optOutTrackingByDefault: optOutTrackingByDefault,
            serverURL: serverURL
        )
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

    /// Consent calls return only once the SDK has applied them.
    @Test func consentStateIsSettledOnReturn() async {
        let service = Self.makeService()
        #expect(service.isOptedOut)

        await service.setOptedOut(false)
        #expect(!service.isOptedOut)

        await service.optOutTracking()
        #expect(service.isOptedOut)

        await service.optInTracking(distinctID: "u2", properties: ["tier": .string("pro")])
        #expect(!service.isOptedOut)
    }

    /// The SDK has no options for logging or geolocation by IP, so the
    /// initializer sets them on the instance. The defaults write nothing, so a
    /// second service for the same instance does not undo them.
    @Test func loggingAndGeoAreSetAtInit() {
        _ = MixpanelCapturePipelineTests.MixpanelCaptureURLProtocol.registerOnce
        let name = "smoke-\(UUID().uuidString)"
        _ = MixpanelAnalyticsService(
            token: "test-token",
            instanceName: name,
            serverURL: Self.serverURL,
            loggingEnabled: true,
            useIPAddressForGeoLocation: false
        )
        _ = MixpanelAnalyticsService(token: "test-token", instanceName: name, serverURL: Self.serverURL)
        let instance = Mixpanel.getInstance(name: name)
        #expect(instance?.loggingEnabled == true)
        #expect(instance?.useIPAddressForGeoLocation == false)
        // The SDK's logger is process-wide; switch it back off.
        instance?.loggingEnabled = false
    }

    /// The SDK consults `deviceIdProvider` only when no persisted identity
    /// exists for the instance name, so the name must be unique per run —
    /// `#function` (stable across runs) would go stale after the first one.
    @Test func deviceIdProviderSeedsDistinctID() async {
        let name = "device-id-\(UUID().uuidString)"
        let customID = "custom-\(UUID().uuidString)"
        let service = MixpanelAnalyticsService(
            token: "test-token",
            instanceName: name,
            optOutTrackingByDefault: true,
            deviceIdProvider: { customID },
            serverURL: Self.serverURL
        )
        await service.flush()
        #expect(Mixpanel.getInstance(name: name)?.distinctId.hasSuffix(customID) == true)
    }

    /// The SDK rejects blank distinct IDs, so the adapter drops the whole
    /// call — otherwise the people update would attach to the previous
    /// identity. Non-delivery isn't observable here; verify clean resolution.
    @Test func identifyWithEmptyUserIDResolves() async {
        let service = Self.makeService()
        await service.identify(userID: "", properties: ["tier": .string("free")])
        await service.flush()
    }

    /// Blank `newID`s are dropped to mirror the SDK's blank-alias rejection.
    /// Also exercises the `previousID: nil` fallback to the anonymous ID.
    @Test func aliasWithEmptyOrNilArgumentsResolves() async {
        let service = Self.makeService()
        await service.alias(newID: "", previousID: nil)
        await service.alias(newID: "alias-nil-previous", previousID: nil)
        await service.flush()
    }

    /// Escape hatch: an app that constructs its own `MixpanelInstance` (e.g.,
    /// for `ProxyServerConfig`) can still wrap it. This is the only test path
    /// that touches `Mixpanel` directly.
    @Test func escapeHatchInitWrapsExplicitInstance() async {
        let instance = Mixpanel.initialize(
            options: MixpanelOptions(
                token: "test-token",
                instanceName: "escape-hatch-\(UUID().uuidString)",
                optOutTrackingByDefault: true,
                serverURL: Self.serverURL
            )
        )
        let service = MixpanelAnalyticsService(instance: instance)
        await service.track(AnalyticsEvent("escape-hatch"))
        await service.flush()
    }
}
