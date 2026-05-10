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
    /// | `.double` | `Double` |
    /// | `.bool`   | `Bool` |
    /// | `.date`   | `Date` |
    /// | `.array`  | `[MixpanelType]` |
    /// | `.dict`   | `[String: MixpanelType]` |
    /// | `.null`   | `NSNull()` |
    public func toMixpanelType() -> MixpanelType {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .date(let value): return value
        case .array(let values): return values.map { $0.toMixpanelType() }
        case .dict(let entries): return entries.mapValues { $0.toMixpanelType() }
        case .null: return NSNull()
        }
    }
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    /// Builds a Mixpanel `Properties` dictionary from a typed
    /// `[String: AnalyticsValue]` map.
    public func toMixpanelProperties() -> Properties {
        mapValues { $0.toMixpanelType() }
    }
}
