//
//  MixpanelCapturePipelineTests.swift
//  SwiduxMixpanelAnalyticsTests
//

import Foundation
import Synchronization
import SwiduxAnalytics
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
///   assertions filter captured requests by this test's token, so the suite is
///   parallel-safe without `.serialized`.
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
@Suite("MixpanelCapturePipeline")
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
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            )!
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
        excludeProperties: Set<String> = [],
        optOutTrackingByDefault: Bool = false
    ) -> MixpanelAnalyticsService {
        _ = MixpanelCaptureURLProtocol.registerOnce
        return MixpanelAnalyticsService(
            token: token,
            trackAutomaticEvents: false,
            flushInterval: 3600,
            instanceName: "capture-\(UUID().uuidString)",
            optOutTrackingByDefault: optOutTrackingByDefault,
            serverURL: "https://\(MixpanelCaptureURLProtocol.host)",
            useGzipCompression: false,
            excludeProperties: excludeProperties
        )
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

        await service.optInTracking()
        // `optInTracking()` clears the opt-out flag asynchronously on the SDK's
        // serial tracking queue, but `flush()` reads that flag *synchronously*
        // on the calling thread and no-ops while it is still set. Wait for the
        // flip to be observable before tracking/flushing — a deterministic,
        // one-way barrier (the flag never flips back here), not a timed sleep.
        while await service.hasOptedOutTracking() {
            await Task.yield()
        }
        await service.track(AnalyticsEvent("delivered"))
        await service.flush()

        let names = MixpanelCaptureURLProtocol.trackEvents(token: token)
            .compactMap { $0["event"] as? String }
        // Not `count == 1`: opt-in itself emits an `$opt_in` event.
        #expect(names.contains("delivered"))
        #expect(!names.contains("dropped"))
    }
}
