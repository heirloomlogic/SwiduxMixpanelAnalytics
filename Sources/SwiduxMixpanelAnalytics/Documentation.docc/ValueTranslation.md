# Value Translation

How `AnalyticsValue` cases map onto Mixpanel's `MixpanelType` and `Properties`.

## Overview

`SwiduxAnalytics.AnalyticsValue` is a closed enum so service adapters can translate deterministically into native SDK types without runtime `Any` surprises. This page documents the mapping `MixpanelAnalyticsService` uses.

Mixpanel's `MixpanelType` accepts `String`, `Int`, `UInt`, `Double`, `Float`, `Bool`, `Date`, `URL`, `NSNull`, `[MixpanelType]`, and `[String: MixpanelType]`.

## Mapping table

| `AnalyticsValue` case | Mixpanel value |
|---|---|
| `.string(s)` | `s` (as `String`) |
| `.int(n)` | `n` (as `Int`) |
| `.double(d)` | `d` (as `Double`), or `NSNull()` if `d` is not finite (`NaN`, `+infinity`, `-infinity`) |
| `.bool(b)` | `b` (as `Bool`) |
| `.date(d)` | `d` (as `Date`) |
| `.array(values)` | `[MixpanelType]` (each element recursively mapped) |
| `.dict(entries)` | `[String: MixpanelType]` (each value recursively mapped) |
| `.null` | `NSNull()` |

## Behavior notes

- **`Int` vs `Double` are preserved.** `AnalyticsValue.int(5)` becomes `Int`; `.double(5)` becomes `Double`. Mixpanel's UI may render them similarly, but the wire types differ.
- **Non-finite doubles become `NSNull()`.** `.double(.nan)`, `.double(.infinity)`, and `.double(-.infinity)` all map to `NSNull()` rather than the raw `Double`. The Mixpanel SDK's own type-validity assertion traps on a non-finite `Double` in Debug builds (and silently stringifies it to `"nan"` in Release), so a computed ratio that happens to divide by zero can crash a Debug build the moment it's tracked. Map away from `Double` before it reaches the SDK instead of relying on the caller to guard every computed value.
- **`.null` becomes `NSNull()`.** Mixpanel treats `NSNull` as an explicit "null" value on the property. To omit a property entirely, don't include the key in your event's `properties` dict.
- **Empty event properties** (no keys) are forwarded as `nil` rather than an empty dictionary, mirroring Mixpanel's `track(event:properties:)` convention.
- **Nested structures** flatten correctly: `.dict([.array([.int(1), .int(2)])])` translates to `[String: [MixpanelType]]` with primitive elements intact.

## Public API

```swift
extension AnalyticsValue {
    public func toMixpanelType() -> MixpanelType
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    public func toMixpanelProperties() -> Properties
}
```

You typically don't call these directly — `MixpanelAnalyticsService` invokes them on every `track` and `identify`. They are exposed for tests, debugging, or for callers who construct Mixpanel events outside the plugin.

## See Also

- <doc:ServiceReference>
- <doc:HowToImplementService>
