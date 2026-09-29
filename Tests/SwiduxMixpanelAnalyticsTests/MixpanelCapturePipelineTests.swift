//
//  MixpanelCapturePipelineTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import Foundation
import Mixpanel
import SwiduxAnalytics
import Synchronization
import Testing

@testable import SwiduxMixpanelAnalytics

/// End-to-end privacy verification for the Mixpanel adapter.
///
/// The sibling `MixpanelAnalyticsServiceTests` treats `excludeProperties`
/// filtering and opt-out as "unobservable" — but they *are* observable. The
/// Mixpanel SDK sends flushes through `URLSession.shared`, which honors
/// `URLProtocol.registerClass`, so an in-process `URLProtocol` can intercept
/// every outbound request and inspect the exact bytes on the wire without a
/// socket, a port, or any teardown.
///
/// Determinism levers (all mandatory, applied in ``makeService``):
/// - `token: UUID().uuidString` per test — the global recorder is shared, but
///   assertions filter captured requests by this test's token to isolate results.
/// - `instanceName: "capture-\(UUID())"` — the SDK persists per-instance event
///   queues on disk; a UUID name guarantees a fresh queue and identity each run
///   (the same trick `deviceIdProviderSeedsDistinctID` relies on).
/// - `serverURL: "https://mixpanel-capture.invalid"` — RFC 2606 reserves the
///   `.invalid` TLD, so if interception ever silently broke, the request would
///   fail DNS resolution rather than leak to Mixpanel, and the positive-control
///   assertions below would fail loudly. There is no path to an accidental
///   green.
/// - `useGzipCompression: false` — the SDK only gzips `/track/` when this is
///   `true`, so captured bodies are directly JSON-decodable.
/// - `flushInterval: 3600` — nothing sends until an explicit `flush()`; the
///   stub responds synchronously, so no sleeps or polling are needed.
/// Serialize capture tests to limit concurrent requests through the shared URL session.
@Suite("MixpanelCapturePipeline", .serialized, .timeLimit(.minutes(1)))
struct MixpanelCapturePipelineTests {
    /// A single outbound request captured off the wire.
    struct CapturedRequest: Sendable {
        let path: String  // "/track/" or "/engage/"
        let body: Data  // plain JSON — the suite always disables gzip
    }

    /// In-process interceptor for Mixpanel's flush traffic. Registered exactly
    /// once (`registerOnce`) and records every request whose host matches the
    /// suite's reserved `.invalid` server URL.
    final class MixpanelCaptureURLProtocol: URLProtocol {
        static let host = "mixpanel-capture.invalid"
        private static let captured = Mutex<[CapturedRequest]>([])

        /// Idempotent registration — reading this static once from `makeService`
        /// installs the protocol a single time for the whole test process.
        static let registerOnce: Void = {
            URLProtocol.registerClass(MixpanelCaptureURLProtocol.self)
        }()

        override class func canInit(with request: URLRequest) -> Bool {
            request.url?.host == host
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            // A `URLProtocol` sees the body only as `httpBodyStream`; by the
            // time a request reaches here `httpBody` is already nil.
            let body = Self.drain(request.httpBodyStream)
            Self.captured.withLock {
                $0.append(CapturedRequest(path: request.url?.path ?? "", body: body))
            }
            // `canInit` already matched on the request's host, so both unwraps
            // below are structurally unreachable. Fail the request rather than
            // force-unwrap: a broken assumption then surfaces as a failed
            // assertion instead of a crashed test process.
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "text/plain"]
                )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            // The SDK's flush parser reads the body as an integer status and
            // treats "1" as accepted. We must always respond, or the SDK waits
            // out its internal ~120 s per-request bound before `flush()` returns.
            client?.urlProtocol(self, didLoad: Data("1".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// Reads an `InputStream` to end. `URLSession` hands the request body to
        /// a `URLProtocol` as a stream, never as `httpBody`.
        private static func drain(_ stream: InputStream?) -> Data {
            guard let stream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            var buffer = [UInt8](repeating: 0, count: size)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        /// All top-level JSON objects captured on `/track/` requests belonging
        /// to `token` — Mixpanel batches events as a plain JSON array per POST
        /// when gzip is off. Each event's `token` lives under its `properties`.
        static func trackEvents(token: String) -> [[String: Any]] {
            objects(onPath: "/track/").filter { event in
                let properties = event["properties"] as? [String: Any]
                return properties?["token"] as? String == token
            }
        }

        /// All `/engage/` (People) payloads whose `$token` matches `token`.
        static func engagePayloads(token: String) -> [[String: Any]] {
            objects(onPath: "/engage/").filter { $0["$token"] as? String == token }
        }

        /// Decodes every captured request on `path` into its top-level JSON
        /// objects. Bodies are JSON arrays of objects; anything else is skipped.
        ///
        /// `path` is passed as the SDK's `FlushType` raw value (e.g. `/track/`),
        /// but `URL.path` normalizes away the trailing slash, so both sides are
        /// compared with trailing slashes trimmed.
        private static func objects(onPath path: String) -> [[String: Any]] {
            func normalized(_ value: String) -> String {
                value.hasSuffix("/") ? String(value.dropLast()) : value
            }
            let target = normalized(path)
            return captured.withLock { $0 }
                .filter { normalized($0.path) == target }
                .flatMap { request -> [[String: Any]] in
                    guard
                        let json = try? JSONSerialization.jsonObject(with: request.body),
                        let array = json as? [[String: Any]]
                    else { return [] }
                    return array
                }
        }
    }

    /// Builds a capture-wired service. Reading `registerOnce` installs the
    /// interceptor before the SDK is constructed; every determinism lever from
    /// the suite doc comment is applied here.
    private static func makeService(
        token: String,
        instanceName: String = "capture-\(UUID().uuidString)",
        excludeProperties: Set<String> = [],
        optOutTrackingByDefault: Bool = false,
        superProperties: [String: AnalyticsValue]? = nil
    ) -> MixpanelAnalyticsService {
        _ = MixpanelCaptureURLProtocol.registerOnce
        return MixpanelAnalyticsService(
            token: token,
            trackAutomaticEvents: false,
            flushInterval: 3600,
            instanceName: instanceName,
            optOutTrackingByDefault: optOutTrackingByDefault,
            superProperties: superProperties,
            serverURL: "https://\(MixpanelCaptureURLProtocol.host)",
            useGzipCompression: false,
            excludeProperties: excludeProperties
        )
    }

    /// Properties of every captured `/track/` event named `name`.
    private static func properties(ofEvent name: String, token: String) -> [[String: Any]] {
        MixpanelCaptureURLProtocol.trackEvents(token: token)
            .filter { $0["event"] as? String == name }
            .compactMap { $0["properties"] as? [String: Any] }
    }

    /// Names of every captured `/track/` event, in capture order.
    private static func eventNames(token: String) -> [String] {
        MixpanelCaptureURLProtocol.trackEvents(token: token).compactMap { $0["event"] as? String }
    }

    /// Excluded keys must never appear in `/track/` bodies. The surviving
    /// `amount` property doubles as a smoke test that capture and decoding work
    /// — if interception were broken this presence check would fail.
    @Test func excludedPropertiesNeverReachTheWire() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(
            token: token,
            excludeProperties: ["email", "full_name"]
        )
        await service.track(
            AnalyticsEvent(
                "purchase",
                [
                    "email": .string("a@b.c"),
                    "full_name": .string("Ada Lovelace"),
                    "amount": .int(9),
                ]
            ))
        await service.flush()

        let purchases = MixpanelCaptureURLProtocol.trackEvents(token: token)
            .filter { $0["event"] as? String == "purchase" }
        let event = try #require(purchases.first)
        #expect(purchases.count == 1)
        let properties = try #require(event["properties"] as? [String: Any])
        #expect(properties["amount"] != nil)
        #expect(properties["email"] == nil)
        #expect(properties["full_name"] == nil)
    }

    /// Excluded keys must also be stripped from People `$set` updates that ride
    /// out on `/engage/`.
    @Test func excludedPropertiesStrippedFromPeopleSet() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token, excludeProperties: ["email"])
        await service.identify(
            userID: "u-\(UUID().uuidString)",
            properties: [
                "email": .string("a@b.c"),
                "tier": .string("pro"),
            ])
        await service.flush()

        let payloads = MixpanelCaptureURLProtocol.engagePayloads(token: token)
        let setPayload = try #require(
            payloads.first { $0["$set"] != nil }
        )
        let set = try #require(setPayload["$set"] as? [String: Any])
        #expect(set["tier"] != nil)
        #expect(set["email"] == nil)
    }

    /// Opt-out drops events before they reach the wire; the subsequent opt-in
    /// phase is the positive control proving phase one was real filtering, not
    /// broken capture.
    @Test func optOutDropsEventsEndToEnd() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token, optOutTrackingByDefault: true)

        await service.track(AnalyticsEvent("dropped"))
        await service.flush()
        #expect(MixpanelCaptureURLProtocol.trackEvents(token: token).isEmpty)

        // No wait here: `optInTracking()` returns only once the SDK's flag has
        // actually flipped, so the `flush()` below is not silently skipped.
        await service.optInTracking()
        await service.track(AnalyticsEvent("delivered"))
        await service.flush()

        let names = MixpanelCaptureURLProtocol.trackEvents(token: token)
            .compactMap { $0["event"] as? String }
        // Not `count == 1`: opt-in itself emits an `$opt_in` event.
        #expect(names.contains("delivered"))
        #expect(!names.contains("dropped"))
    }

    // MARK: - Queue draining

    /// `flush()` is the plugin's shutdown drain, so it must send the whole
    /// queue — not one 50-record batch (the SDK's default partial flush).
    @Test func flushDrainsTheWholeQueue() async {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        for index in 0..<120 {
            await service.track(AnalyticsEvent("bulk", ["index": .int(index)]))
        }
        await service.flush()

        #expect(Self.properties(ofEvent: "bulk", token: token).count == 120)
    }

    /// The SDK's `reset()` flushes one partial batch and then deletes every
    /// queued row. Events recorded before a logout must still be delivered.
    @Test func resetDoesNotDiscardQueuedEvents() async {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        for index in 0..<120 {
            await service.track(AnalyticsEvent("before-logout", ["index": .int(index)]))
        }
        await service.reset()
        await service.flush()

        #expect(Self.properties(ofEvent: "before-logout", token: token).count == 120)
    }

    // MARK: - Consent

    /// The SDK applies opt-in on its own queue while `identify` checks the
    /// flag on the caller's thread, so an identify issued straight after an
    /// opt-in used to be dropped silently.
    @Test func identifyStraightAfterOptInIsHonored() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token, optOutTrackingByDefault: true)
        let userID = "u-\(UUID().uuidString)"

        await service.optInTracking()
        await service.identify(userID: userID, properties: [:])
        await service.track(AnalyticsEvent("after-consent"))
        await service.flush()

        let event = try #require(Self.properties(ofEvent: "after-consent", token: token).first)
        #expect(event["distinct_id"] as? String == userID)
    }

    /// The mirror image: an identify straight after an opt-out must not
    /// re-identify the device or queue a profile update that ships later.
    @Test func identifyStraightAfterOptOutIsDropped() async {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        let userID = "carol-\(UUID().uuidString)"

        await service.optOutTracking()
        await service.identify(userID: userID, properties: ["email": .string("c@d.e")])
        await service.optInTracking()
        await service.track(AnalyticsEvent("after-consent"))
        await service.flush()

        let engage = MixpanelCaptureURLProtocol.engagePayloads(token: token)
        #expect(!engage.contains { $0["$distinct_id"] as? String == userID })
        let events = Self.properties(ofEvent: "after-consent", token: token)
        #expect(!events.isEmpty)
        #expect(!events.contains { $0["distinct_id"] as? String == userID })
    }

    /// `hasOptedOutTracking()` must reflect `optOutTrackingByDefault` from the
    /// first call, not after the SDK's queue gets round to applying it.
    @Test func optOutByDefaultIsVisibleImmediately() async {
        let service = Self.makeService(token: UUID().uuidString, optOutTrackingByDefault: true)
        #expect(await service.hasOptedOutTracking())
    }

    /// The SDK's opt-out queues a `$delete` for the current user, but stores it
    /// unattributed; the next identify adopted it and deleted *that* user's
    /// profile. No `$delete` may ever reach the wire for someone else.
    @Test func optOutNeverDeletesTheNextUsersProfile() async {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        await service.identify(userID: "alice-\(UUID().uuidString)", properties: [:])
        await service.flush()

        await service.optOutTracking()
        await service.optInTracking(distinctID: "bob-\(UUID().uuidString)")
        await service.track(AnalyticsEvent("after-consent"))
        await service.flush()

        // Positive control: the flush really ran after opting back in.
        #expect(!Self.properties(ofEvent: "after-consent", token: token).isEmpty)
        let engage = MixpanelCaptureURLProtocol.engagePayloads(token: token)
        #expect(!engage.contains { $0["$delete"] != nil })
    }

    /// An opt-out the SDK performed itself — `optOutTrackingByDefault` on an
    /// install that was already identified, or an app calling the SDK
    /// directly — still leaves an unattributed `$delete` in the queue. Opting
    /// back in must not let the next user adopt it.
    @Test func sdkLevelOptOutNeverDeletesTheNextUsersProfile() async {
        _ = MixpanelCaptureURLProtocol.registerOnce
        let token = UUID().uuidString
        let instance = Mixpanel.initialize(
            options: MixpanelOptions(
                token: token,
                flushInterval: 3600,
                instanceName: "capture-\(UUID().uuidString)",
                trackAutomaticEvents: false,
                serverURL: "https://\(MixpanelCaptureURLProtocol.host)",
                useGzipCompression: false
            ))
        let service = MixpanelAnalyticsService(instance: instance)
        await service.identify(userID: "alice-\(UUID().uuidString)", properties: [:])
        await service.flush()
        instance.optOutTracking()
        while !instance.hasOptedOutTracking() {
            await Task.yield()
        }

        await service.optInTracking(distinctID: "bob-\(UUID().uuidString)")
        await service.track(AnalyticsEvent("after-consent"))
        await service.flush()

        #expect(!Self.properties(ofEvent: "after-consent", token: token).isEmpty)
        let engage = MixpanelCaptureURLProtocol.engagePayloads(token: token)
        #expect(!engage.contains { $0["$delete"] != nil })
    }

    /// The launch barrier relies on the SDK's persisted opt-out key: present
    /// once a choice is made, absent before.
    @Test func consentChoiceDetectionTracksTheSDKsStorage() async {
        let name = "capture-\(UUID().uuidString)"
        #expect(!MixpanelAnalyticsService.hasPersistedConsentChoice(instanceName: name))
        let service = Self.makeService(token: UUID().uuidString, instanceName: name)
        await service.optOutTracking()
        #expect(MixpanelAnalyticsService.hasPersistedConsentChoice(instanceName: name))
    }

    /// Consent hooks fire on every `.setOptedOut` dispatch, so opting in a user
    /// who is already opted in must not emit another `$opt_in` event.
    @Test func optInIsIdempotent() async {
        let token = UUID().uuidString
        let optedIn = Self.makeService(token: token)
        await optedIn.optInTracking()
        await optedIn.optInTracking()
        await optedIn.track(AnalyticsEvent("marker"))
        await optedIn.flush()
        #expect(Self.eventNames(token: token) == ["marker"])

        let secondToken = UUID().uuidString
        let optedOut = Self.makeService(token: secondToken, optOutTrackingByDefault: true)
        await optedOut.optInTracking()
        await optedOut.optInTracking()
        // The SDK queues `$opt_in` just after flipping the flag the adapter
        // waits on; the first flush's completion proves it is queued.
        await optedOut.flush()
        await optedOut.flush()
        #expect(Self.eventNames(token: secondToken).filter { $0 == "$opt_in" }.count == 1)
    }

    /// The SDK's `reset()` erases the persisted opt-out flag, and the Swidux
    /// plugin calls `reset()` on every opt-out — so a withdrawn user was
    /// tracked again after the next cold launch.
    @Test func optOutSurvivesResetAndRelaunch() async {
        let token = UUID().uuidString
        let name = "capture-\(UUID().uuidString)"
        let firstLaunch = Self.makeService(token: token, instanceName: name)
        await firstLaunch.optOutTracking()
        await firstLaunch.reset()
        await firstLaunch.flush()

        Mixpanel.removeInstance(name: name)
        let secondLaunch = Self.makeService(token: token, instanceName: name)
        #expect(await secondLaunch.hasOptedOutTracking())
    }

    // MARK: - Identity

    /// Init-time super properties were dropped when the service started opted
    /// out, and wiped for the rest of the session by `reset()`.
    @Test func superPropertiesSurviveConsentAndReset() async {
        let token = UUID().uuidString
        let service = Self.makeService(
            token: token,
            optOutTrackingByDefault: true,
            superProperties: ["flavor": .string("pro")]
        )
        await service.optInTracking()
        await service.track(AnalyticsEvent("before-reset"))
        await service.reset()
        await service.track(AnalyticsEvent("after-reset"))
        await service.flush()

        for name in ["before-reset", "after-reset"] {
            let events = Self.properties(ofEvent: name, token: token)
            #expect(events.count == 1, "\(name)")
            #expect(events.first?["flavor"] as? String == "pro", "\(name)")
        }
    }

    /// The Swidux sign-in recipe identifies first and aliases second. With the
    /// SDK's `andIdentify: true` default that re-identified the device back to
    /// its anonymous ID, so every later event lost the user. The alias must
    /// point at the ID the anonymous events were actually sent under.
    @Test func aliasAfterIdentifyKeepsTheUser() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        let userID = "u-\(UUID().uuidString)"

        await service.track(AnalyticsEvent("anonymous"))
        await service.identify(userID: userID, properties: [:])
        await service.alias(newID: userID, previousID: nil)
        await service.track(AnalyticsEvent("after-alias"))
        await service.flush()

        let anonymous = try #require(Self.properties(ofEvent: "anonymous", token: token).first)
        let anonymousID = try #require(anonymous["distinct_id"] as? String)
        let event = try #require(Self.properties(ofEvent: "after-alias", token: token).first)
        #expect(event["distinct_id"] as? String == userID)
        let alias = try #require(Self.properties(ofEvent: "$create_alias", token: token).first)
        #expect(alias["alias"] as? String == userID)
        #expect(alias["distinct_id"] as? String == anonymousID)
    }

    /// Aliasing before any identify links the anonymous device ID as sent.
    @Test func aliasBeforeIdentifyUsesTheAnonymousID() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        let userID = "u-\(UUID().uuidString)"

        await service.track(AnalyticsEvent("anonymous"))
        await service.alias(newID: userID, previousID: nil)
        await service.flush()

        let anonymous = try #require(Self.properties(ofEvent: "anonymous", token: token).first)
        let alias = try #require(Self.properties(ofEvent: "$create_alias", token: token).first)
        #expect(alias["distinct_id"] as? String == anonymous["distinct_id"] as? String)
    }

    /// The SDK stamps queued People updates with whoever is identified at
    /// flush time, so switching users without a flush sent A's `$set` as B's.
    /// Nothing may be sent twice either: the SDK sets no `$insert_id`, so
    /// Mixpanel keeps duplicates.
    @Test func profileUpdatesStayWithTheirOwnUser() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        let userA = "a-\(UUID().uuidString)"
        let userB = "b-\(UUID().uuidString)"

        await service.identify(userID: userA, properties: ["plan": .string("a")])
        await service.track(AnalyticsEvent("as-a"))
        await service.identify(userID: userB, properties: ["plan": .string("b")])
        await service.alias(newID: "alias-\(UUID().uuidString)", previousID: nil)
        await service.flush()

        let sets = MixpanelCaptureURLProtocol.engagePayloads(token: token)
            .compactMap { payload -> String? in
                guard let plan = (payload["$set"] as? [String: Any])?["plan"] as? String else { return nil }
                return "\(plan)->\(payload["$distinct_id"] as? String ?? "?")"
            }
        #expect(sets.sorted() == ["a->\(userA)", "b->\(userB)"])
        let asA = Self.properties(ofEvent: "as-a", token: token)
        #expect(asA.count == 1)
        #expect(asA.first?["distinct_id"] as? String == userA)
    }

    // MARK: - Values on the wire

    /// The SDK sends every `NSNull` as the string `"<null>"` and non-finite
    /// doubles as `"nan"` / `"inf"` (or crashes a Debug build), so none of
    /// them may reach it.
    @Test func nullAndNonFiniteValuesAreOmitted() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        await service.track(
            AnalyticsEvent(
                "values",
                [
                    "top_null": .null,
                    "top_nan": .double(.nan),
                    "list": .array([.null, .double(.infinity), .int(1)]),
                    "object": .dict(["gone": .null, "nan": .double(-.infinity), "kept": .int(2)]),
                ]
            ))
        await service.flush()

        let event = try #require(Self.properties(ofEvent: "values", token: token).first)
        #expect(event["top_null"] == nil)
        #expect(event["top_nan"] == nil)
        let list = try #require(event["list"] as? [Any])
        #expect(list.count == 1)
        #expect(list.first as? Int == 1)
        let object = try #require(event["object"] as? [String: Any])
        #expect(object.keys.sorted() == ["kept"])
    }

    /// A profile property that translates to null is unset rather than set to
    /// the string `"<null>"`.
    @Test func nullProfilePropertiesAreUnset() async throws {
        let token = UUID().uuidString
        let service = Self.makeService(token: token)
        await service.identify(
            userID: "u-\(UUID().uuidString)",
            properties: ["plan": .string("pro"), "coupon": .null]
        )
        await service.flush()

        let engage = MixpanelCaptureURLProtocol.engagePayloads(token: token)
        let set = try #require(engage.compactMap { $0["$set"] as? [String: Any] }.first)
        #expect(set["plan"] as? String == "pro")
        #expect(set["coupon"] == nil)
        let unset = try #require(engage.compactMap { $0["$unset"] as? [String] }.first)
        #expect(unset == ["coupon"])
    }
}
