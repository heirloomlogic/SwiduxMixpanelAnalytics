//
//  RecordingMixpanelAnalyticsServiceTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import SwiduxAnalytics
import SwiduxMixpanelAnalytics
import Testing

@Suite("RecordingMixpanelAnalyticsService")
struct RecordingMixpanelAnalyticsServiceTests {
    @Test func forwardsServiceCallsToTheRecorder() async {
        let service = RecordingMixpanelAnalyticsService()
        await service.identify(userID: "user-1", properties: ["tier": .string("pro")])
        await service.track(AnalyticsEvent("opened", ["count": .int(2)]))
        await service.alias(newID: "user-1", previousID: "anon")
        await service.reset()
        await service.flush()

        #expect(
            await service.recorder.calls == [
                .identify(userID: "user-1", properties: ["tier": .string("pro")]),
                .track(AnalyticsEvent("opened", ["count": .int(2)])),
                .alias(newID: "user-1", previousID: "anon"),
                .reset,
                .flush,
            ])
    }

    @Test func consentChangesJoinTheOrderedLog() async {
        let service = RecordingMixpanelAnalyticsService()
        await service.track(AnalyticsEvent("before"))
        await service.optOutTracking()
        await service.reset()
        await service.optInTracking(distinctID: "user-1", properties: ["source": .string("settings")])
        await service.flush()

        #expect(
            await service.recorder.calls == [
                .track(AnalyticsEvent("before")),
                .setOptedOut(true),
                .reset,
                .setOptedOut(false),
                .flush,
            ])
        #expect(
            await service.optInCalls == [
                .init(distinctID: "user-1", properties: ["source": .string("settings")])
            ])
    }

    @Test func optOutAndOptInTrackTheState() async {
        let service = RecordingMixpanelAnalyticsService()
        #expect(service.isOptedOut == false)

        await service.optOutTracking()
        #expect(service.isOptedOut)

        await service.optInTracking()
        #expect(service.isOptedOut == false)
    }

    @Test func setOptedOutRoutesToOptOutAndOptIn() async {
        let service = RecordingMixpanelAnalyticsService(optedOut: true)
        #expect(service.isOptedOut)

        await service.setOptedOut(false)
        #expect(await service.optInCalls == [.init()])
        #expect(service.isOptedOut == false)

        await service.setOptedOut(true)
        #expect(service.isOptedOut)
        #expect(await service.recorder.calls == [.setOptedOut(false), .setOptedOut(true)])
    }
}
