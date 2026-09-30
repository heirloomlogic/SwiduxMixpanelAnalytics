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
| `.double(d)` | `d` (as `Double`); omitted if NaN or infinite |
| `.bool(b)` | `b` (as `Bool`) |
| `.date(d)` | `d` (as `Date`) |
| `.array(values)` | `[MixpanelType]` (each element recursively mapped; nulls omitted) |
| `.dict(entries)` | `[String: MixpanelType]` (each value recursively mapped; nulls omitted) |
| `.null` | omitted |

## Behavior notes

- **`Int` vs `Double` are preserved.** `AnalyticsValue.int(5)` becomes `Int`; `.double(5)` becomes `Double`. Mixpanel's UI may render them similarly, but the wire types differ.
- **Nulls are omitted.** The Mixpanel SDK cannot send a JSON `null`: it re-serializes queued data when flushing and turns every `NSNull` into the string `"<null>"`. So `.null` values — at the top level, in arrays, and in dictionaries — are left out rather than arriving as that string. On a user profile, `identify` *unsets* a top-level property whose value is null; that is the way to delete a saved property. A property left out of `identify` is not touched and keeps its saved value.
- **Non-finite doubles count as null.** NaN and ±infinity make the SDK assert (a crash in Debug builds) and otherwise arrive as the strings `"nan"` / `"inf"`, so they are omitted like `.null`.
- **Empty event properties** (no keys) are forwarded as `nil` rather than an empty dictionary, mirroring Mixpanel's `track(event:properties:)` convention.
- **Nested structures** flatten correctly: `.dict([.array([.int(1), .int(2)])])` translates to `[String: [MixpanelType]]` with primitive elements intact.

## Public API

```swift
extension AnalyticsValue {
    public func toMixpanelType() -> any MixpanelType  // `NSNull()` for null and non-finite values
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    public func toMixpanelProperties() -> Properties  // null entries omitted
}
```

You typically don't call these directly — `MixpanelAnalyticsService` invokes them on every `track` and `identify`. They are exposed for tests, debugging, or for callers who construct Mixpanel events outside the plugin.

## See Also

- <doc:ServiceReference>
- <doc:HowToImplementService>
