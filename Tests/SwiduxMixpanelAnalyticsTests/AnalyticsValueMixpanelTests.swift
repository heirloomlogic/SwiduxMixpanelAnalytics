//
//  AnalyticsValueMixpanelTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import Foundation
import Mixpanel
import SwiduxAnalytics
import Testing

@testable import SwiduxMixpanelAnalytics

@Suite("AnalyticsValue → Mixpanel translation")
struct AnalyticsValueMixpanelTests {
    @Test func stringMapsToString() {
        let value = AnalyticsValue.string("hello").toMixpanelType()
        #expect((value as? String) == "hello")
    }

    @Test func intMapsToInt() {
        let value = AnalyticsValue.int(42).toMixpanelType()
        #expect((value as? Int) == 42)
    }

    @Test func doubleMapsToDouble() {
        let value = AnalyticsValue.double(3.14).toMixpanelType()
        #expect((value as? Double) == 3.14)
    }

    @Test func boolMapsToBool() {
        let value = AnalyticsValue.bool(true).toMixpanelType()
        #expect((value as? Bool) == true)
    }

    @Test func dateRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let value = AnalyticsValue.date(date).toMixpanelType()
        #expect((value as? Date) == date)
    }

    @Test func nullMapsToNSNull() {
        let value = AnalyticsValue.null.toMixpanelType()
        #expect(value is NSNull)
    }

    @Test func arrayPreservesElementTypes() {
        let value = AnalyticsValue.array([.string("a"), .int(1), .bool(true)]).toMixpanelType()
        let array = try? #require(value as? [MixpanelType])
        #expect((array?[0] as? String) == "a")
        #expect((array?[1] as? Int) == 1)
        #expect((array?[2] as? Bool) == true)
    }

    @Test func dictPreservesKeysAndTypes() {
        let value = AnalyticsValue.dict([
            "name": .string("widget"),
            "count": .int(7),
        ]).toMixpanelType()
        let dict = try? #require(value as? [String: MixpanelType])
        #expect((dict?["name"] as? String) == "widget")
        #expect((dict?["count"] as? Int) == 7)
    }

    @Test func nestedStructuresFlatten() {
        let nested: AnalyticsValue = .dict([
            "tags": .array([.string("a"), .string("b")]),
            "meta": .dict(["active": .bool(true)]),
        ])
        let result = nested.toMixpanelType() as? [String: MixpanelType]
        let tags = result?["tags"] as? [MixpanelType]
        #expect((tags?[0] as? String) == "a")
        let meta = result?["meta"] as? [String: MixpanelType]
        #expect((meta?["active"] as? Bool) == true)
    }

    @Test func intAndDoubleAreNotConflated() {
        let intResult = AnalyticsValue.int(5).toMixpanelType()
        let doubleResult = AnalyticsValue.double(5).toMixpanelType()
        #expect(intResult is Int)
        #expect(doubleResult is Double)
    }

    @Test func dictionaryExtensionMapsAllKeys() {
        let input: [String: AnalyticsValue] = [
            "amount": .int(10),
            "label": .string("hi"),
            "missing": .null,
        ]
        let props = input.toMixpanelProperties()
        #expect(props.count == 3)
        #expect((props["amount"] as? Int) == 10)
        #expect((props["label"] as? String) == "hi")
        #expect(props["missing"] is NSNull)
    }

    @Test func emptyDictionaryRoundTrips() {
        let props: [String: AnalyticsValue] = [:]
        #expect(props.toMixpanelProperties().isEmpty)
    }
}
