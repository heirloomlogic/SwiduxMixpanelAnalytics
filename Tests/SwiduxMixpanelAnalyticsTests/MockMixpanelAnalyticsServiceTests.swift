//
//  MockMixpanelAnalyticsServiceTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import SwiduxAnalytics
import Testing

@testable import SwiduxMixpanelAnalytics

@Suite("MockMixpanelAnalyticsService")
struct MockMixpanelAnalyticsServiceTests {
    @Test func recordsTrackedEventsInOrder() async {
        let mock = MockMixpanelAnalyticsService()
        await mock.track(AnalyticsEvent("first"))
        await mock.track(AnalyticsEvent("second", ["count": .int(2)]))

        let events = await mock.trackedEvents
        #expect(events.count == 2)
        #expect(events[0].name == "first")
        #expect(events[1].name == "second")
        #expect(events[1].properties == ["count": .int(2)])
    }

    @Test func recordsIdentifyCalls() async {
        let mock = MockMixpanelAnalyticsService()
        await mock.identify(userID: "user-1", properties: ["tier": .string("pro")])

        let calls = await mock.identifyCalls
        #expect(calls == [.init(userID: "user-1", properties: ["tier": .string("pro")])])
    }

    @Test func recordsAliasCalls() async {
        let mock = MockMixpanelAnalyticsService()
        await mock.alias(newID: "new", previousID: "old")
        await mock.alias(newID: "fresh", previousID: nil)

        let calls = await mock.aliasCalls
        #expect(calls.count == 2)
        #expect(calls[0] == .init(newID: "new", previousID: "old"))
        #expect(calls[1] == .init(newID: "fresh", previousID: nil))
    }

    @Test func countsResetAndFlush() async {
        let mock = MockMixpanelAnalyticsService()
        await mock.reset()
        await mock.reset()
        await mock.flush()

        let resets = await mock.resetCount
        let flushes = await mock.flushCount
        #expect(resets == 2)
        #expect(flushes == 1)
    }

    @Test func optOutTogglesStateAndIncrementsCount() async {
        let mock = MockMixpanelAnalyticsService()
        #expect(await mock.optedOut == false)
        #expect(await mock.hasOptedOutTracking() == false)

        await mock.optOutTracking()
        await mock.optOutTracking()

        #expect(await mock.optOutCount == 2)
        #expect(await mock.optedOut == true)
        #expect(await mock.hasOptedOutTracking() == true)
    }

    @Test func optInRecordsCallAndClearsOptOutState() async {
        let mock = MockMixpanelAnalyticsService()
        await mock.optOutTracking()

        await mock.optInTracking(
            distinctID: "user-1",
            properties: ["tier": .string("pro")]
        )
        await mock.optInTracking()

        let calls = await mock.optInCalls
        #expect(calls.count == 2)
        #expect(
            calls[0]
                == .init(
                    distinctID: "user-1",
                    properties: ["tier": .string("pro")]))
        #expect(calls[1] == .init(distinctID: nil, properties: nil))
        #expect(await mock.optedOut == false)
        #expect(await mock.hasOptedOutTracking() == false)
    }

    @Test func recordsLoggingAndGeoToggles() async {
        let mock = MockMixpanelAnalyticsService()
        #expect(await mock.loggingEnabled == nil)
        #expect(await mock.useIPAddressForGeoLocation == nil)

        await mock.setLoggingEnabled(true)
        await mock.setUseIPAddressForGeoLocation(false)

        #expect(await mock.loggingEnabled == true)
        #expect(await mock.useIPAddressForGeoLocation == false)
    }
}
