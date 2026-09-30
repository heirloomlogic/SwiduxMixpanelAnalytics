//
//  AnalyticsValue+Mixpanel.swift
//  SwiduxMixpanelAnalytics
//

import Foundation
import Mixpanel
import SwiduxAnalytics

extension AnalyticsValue {
    /// Translates an `AnalyticsValue` into a Mixpanel property value.
    ///
    /// | `AnalyticsValue` | `MixpanelType` |
    /// |---|---|
    /// | `.string` | `String` |
    /// | `.int`    | `Int` |
    /// | `.double` | `Double`; `NSNull()` if NaN or infinite |
    /// | `.bool`   | `Bool` |
    /// | `.date`   | `Date` |
    /// | `.array`  | `[MixpanelType]`, without null elements |
    /// | `.dict`   | `[String: MixpanelType]`, without null entries |
    /// | `.null`   | `NSNull()` |
    ///
    /// The SDK cannot send a JSON `null`: it re-serializes queued data at
    /// flush time and turns every `NSNull` into the string `"<null>"`. So
    /// nulls are omitted wherever they can be — inside arrays and
    /// dictionaries here, and at the top level in `toMixpanelProperties()`.
    /// Non-finite doubles count as null, because the SDK asserts on them (a
    /// crash in Debug builds) and otherwise sends the strings `"nan"` /
    /// `"inf"`.
    func toMixpanelType() -> any MixpanelType {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value.isFinite ? value : NSNull()
        case .bool(let value): return value
        case .date(let value): return value
        case .array(let values): return values.compactMap(\.nonNullMixpanelValue)
        case .dict(let entries): return entries.compactMapValues(\.nonNullMixpanelValue)
        case .null: return NSNull()
        }
    }

    /// The translated value, or `nil` for anything that translates to null.
    var nonNullMixpanelValue: (any MixpanelType)? {
        let value = toMixpanelType()
        return value is NSNull ? nil : value
    }
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    /// Builds a Mixpanel `Properties` dictionary from a typed
    /// `[String: AnalyticsValue]` map, omitting entries that translate to
    /// null — the SDK would send them as the string `"<null>"`.
    func toMixpanelProperties() -> Properties {
        compactMapValues(\.nonNullMixpanelValue)
    }
}
