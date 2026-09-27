//
//  MixpanelAnalyticsService.swift
//  SwiduxMixpanelAnalytics
//

import Foundation
import Mixpanel
import SwiduxAnalytics
import Synchronization

/// `AnalyticsService` conformer that owns and forwards to a Mixpanel SDK
/// instance.
///
/// The adapter is the configuration boundary: pass the token and any other
/// Mixpanel knobs to ``init(token:trackAutomaticEvents:flushInterval:instanceName:optOutTrackingByDefault:useUniqueDistinctId:deviceIdProvider:superProperties:serverURL:useGzipCompression:excludeProperties:)``
/// and the app never needs to `import Mixpanel`. The initializer is the same
/// on every platform; it builds a `MixpanelOptions` and calls
/// `Mixpanel.initialize(options:)`.
///
/// ```swift
/// let service = MixpanelAnalyticsService(
///     token: Secrets.mixpanelAPIKey,
///     optOutTrackingByDefault: true
/// )
/// ```
///
/// The SDK applies most calls later, on its own serial queue, while checking
/// the opt-out flag on the caller's thread. The adapter papers over the gaps
/// that leaves: consent changes take effect before their `async` call
/// returns, `flush()` drains the whole queue, and `reset()` keeps both queued
/// events and a withdrawn consent.
///
/// The struct is `@unchecked Sendable`: `MixpanelInstance` serializes its
/// tracking work on internal queues, and every copy of the service shares one
/// SDK instance. The exceptions are the diagnostic setters, which write
/// unsynchronized SDK properties — set those once, at launch.
public struct MixpanelAnalyticsService: AnalyticsService, @unchecked Sendable {
    private let instance: MixpanelInstance
    /// Init-time super properties, re-registered whenever the SDK drops them
    /// (it clears them on `reset()` and opt-out, and ignores them when the
    /// instance starts opted out).
    private let superProperties: Properties?
    private let session = Session()
    /// Resolves once the SDK has applied `optOutTrackingByDefault`; `nil` when
    /// there is nothing pending. See `awaitDefaultOptOut(of:)`.
    private let defaultOptOut: Task<Void, Never>?

    /// Initializes Mixpanel with the given token and wraps the resulting
    /// instance.
    ///
    /// Parameters mirror `MixpanelOptions`; the `superProperties` map is typed
    /// as `[String: AnalyticsValue]` so the app does not need to reference
    /// `MixpanelType`.
    ///
    /// > Important: The Mixpanel SDK keys instances by `instanceName` (falling
    /// > back to `token`). Constructing a second service with the same name
    /// > returns the *existing* SDK instance and silently ignores the new
    /// > options — construct the service once, where the store is configured,
    /// > rather than per view or per preview.
    ///
    /// - Parameters:
    ///   - token: The Mixpanel project token.
    ///   - trackAutomaticEvents: See the Mixpanel SDK docs for the list of
    ///     automatic events. Defaults to `false`.
    ///   - flushInterval: Seconds between automatic flushes; `0` disables the
    ///     timer. Defaults to `60`.
    ///   - instanceName: A name for this Mixpanel instance, allowing the app
    ///     to run multiple Mixpanel projects. Defaults to `nil` (main instance).
    ///   - optOutTrackingByDefault: If `true`, the SDK starts opted out until
    ///     the user has opted in once; the choice then persists across
    ///     launches. Flip with ``setOptedOut(_:)``. Defaults to `false`.
    ///   - useUniqueDistinctId: If `true`, the default anonymous ID is the
    ///     device's own identifier — the IDFV on iOS, the **hardware serial
    ///     number** on macOS — instead of a random UUID. Leave it `false`
    ///     unless you need an ID that survives reinstalls. Defaults to `false`.
    ///   - deviceIdProvider: Supplies a custom device ID instead of the SDK
    ///     default. The SDK calls it synchronously on every launch, on
    ///     `reset()`, and on opt-out — some of those calls hold the SDK's
    ///     internal lock — so it must return a value cached at app launch
    ///     (e.g. a Keychain-minted UUID), never do I/O inline, and never call
    ///     back into this service or Mixpanel, which would deadlock. Return
    ///     `nil` or a blank string to fall back to the SDK default. Defaults
    ///     to `nil`.
    ///   - superProperties: Properties attached to every event. They are
    ///     re-applied after `reset()` and after opting back in. Defaults to
    ///     `nil`.
    ///   - serverURL: Override the Mixpanel API base URL (e.g. EU residency).
    ///     Must be an absolute URL — the SDK silently sends nothing to a
    ///     malformed one. Defaults to `nil`.
    ///   - useGzipCompression: Compress outbound requests with gzip. Defaults
    ///     to `true`, matching `MixpanelOptions`.
    ///   - excludeProperties: Property keys stripped from outgoing events and
    ///     People `$set` / `$set_once` updates before they are stored or sent
    ///     — e.g. keys that may carry PII. Other People operators pass through
    ///     unfiltered, and keys Mixpanel requires for ingestion
    ///     (`distinct_id`, `token`, …) are never stripped. Defaults to empty.
    public init(
        token: String,
        trackAutomaticEvents: Bool = false,
        flushInterval: Double = 60,
        instanceName: String? = nil,
        optOutTrackingByDefault: Bool = false,
        useUniqueDistinctId: Bool = false,
        deviceIdProvider: (@Sendable () -> String?)? = nil,
        superProperties: [String: AnalyticsValue]? = nil,
        serverURL: String? = nil,
        useGzipCompression: Bool = true,
        excludeProperties: Set<String> = []
    ) {
        assert(
            serverURL.map { URL(string: $0)?.host?.isEmpty == false } ?? true,
            "serverURL must be an absolute URL such as https://api-eu.mixpanel.com"
        )
        let superProperties = Self.nonEmptyProperties(superProperties)
        let initialized = Mixpanel.initialize(
            options: MixpanelOptions(
                token: token,
                flushInterval: flushInterval,
                instanceName: instanceName,
                trackAutomaticEvents: trackAutomaticEvents,
                optOutTrackingByDefault: optOutTrackingByDefault,
                useUniqueDistinctId: useUniqueDistinctId,
                superProperties: superProperties,
                serverURL: serverURL,
                useGzipCompression: useGzipCompression,
                deviceIdProvider: deviceIdProvider,
                excludeProperties: excludeProperties
            )
        )
        // `initialize` returns the SDK's shared "main instance" after leaving
        // its lock, so a service built concurrently with another could get
        // the other project's instance. The by-name lookup is locked.
        let instance = Mixpanel.getInstance(name: instanceName ?? token) ?? initialized
        self.instance = instance
        self.superProperties = superProperties
        // When the flag already reads `true` the SDK's queued opt-out changes
        // nothing observable, so only the `false` reading needs resolving.
        self.defaultOptOut =
            optOutTrackingByDefault && !instance.hasOptedOutTracking()
            ? Self.awaitDefaultOptOut(of: UncheckedInstance(instance))
            : nil
    }

    /// Escape hatch for apps that need to construct their own `MixpanelInstance`
    /// (for example, to use `ProxyServerConfig`). Most apps should prefer the
    /// token-based initializer above and never `import Mixpanel`.
    ///
    /// Super properties registered on `instance` directly are the app's to
    /// manage: they are not re-applied after `reset()` or opt-in.
    public init(instance: MixpanelInstance) {
        self.instance = instance
        self.superProperties = nil
        self.defaultOptOut = nil
    }

    // MARK: - AnalyticsService

    /// Forwards an event to `MixpanelInstance.track(event:properties:)`. Empty
    /// `event.properties` are passed as `nil`.
    public func track(_ event: AnalyticsEvent) async {
        instance.track(event: event.name, properties: Self.nonEmptyProperties(event.properties))
    }

    /// Sets the active Mixpanel distinct ID and updates the user's profile:
    /// `properties` are set via `instance.people.set`, except those that
    /// translate to null (`.null`, NaN, infinity), which are unset.
    ///
    /// Empty `userID`s are dropped entirely: the SDK rejects blank distinct
    /// IDs, and forwarding the people update anyway would attribute it to the
    /// previous identity. Calls made while opted out are dropped too.
    ///
    /// When the user changes, the previous user's queued People updates are
    /// handed to the network first — the SDK attributes queued updates to
    /// whoever is identified when they are sent, not when they were made.
    public func identify(userID: String, properties: [String: AnalyticsValue]) async {
        guard !userID.isEmpty else { return }
        await defaultOptOut?.value
        guard !instance.hasOptedOutTracking() else { return }
        if session.identify(userID) {
            instance.flush(performFullFlush: true)
        }
        instance.identify(distinctId: userID)
        let set = properties.toMixpanelProperties()
        if !set.isEmpty {
            instance.people.set(properties: set)
        }
        let unset = properties.keys.filter { set[$0] == nil }
        if !unset.isEmpty {
            instance.people.unset(properties: unset.sorted())
        }
    }

    /// Records `newID` as an alias of `previousID` via
    /// `MixpanelInstance.createAlias(_:distinctId:usePeople:andIdentify:)`.
    ///
    /// When `previousID` is `nil`, the device's anonymous ID is used. The
    /// alias never changes who is identified locally — identity is
    /// ``identify(userID:properties:)``'s job — so the common "identify, then
    /// alias" sign-in sequence keeps attributing events to the user. Empty
    /// `newID`s are dropped, mirroring the SDK's blank-alias rejection.
    ///
    /// > Important: Projects on Mixpanel's Simplified ID Merge ignore aliases
    /// > entirely; `identify` alone links the anonymous and known IDs there.
    /// > Only dispatch `.alias` for projects on Original ID Merge.
    public func alias(newID: String, previousID: String?) async {
        guard !newID.isEmpty else { return }
        await defaultOptOut?.value
        let source = previousID ?? instance.anonymousId ?? instance.distinctId
        instance.createAlias(newID, distinctId: source, andIdentify: false)
    }

    /// Clears the local identity, super properties, and timed events via
    /// `MixpanelInstance.reset(completion:)`, and returns once that is done.
    /// Init-time super properties are then re-applied.
    ///
    /// Everything still queued is sent first, and this waits for it: the
    /// SDK's own `reset()` sends one 50-record batch and deletes the rest.
    /// Anything the network then fails to take is discarded, as the SDK does.
    ///
    /// While opted out this only forgets the adapter's record of the user.
    /// Opting out has already cleared the SDK's identity and queue, and the
    /// SDK's `reset()` would also erase the persisted opt-out — the user
    /// would be tracked again from the next launch.
    public func reset() async {
        await defaultOptOut?.value
        guard !instance.hasOptedOutTracking() else {
            session.forgetUser()
            return
        }
        await clearIdentity()
        registerSuperProperties()
    }

    /// Sends every queued event and People update via
    /// `MixpanelInstance.flush(performFullFlush:completion:)`, and returns once
    /// the SDK reports completion — not just the first 50-record batch the
    /// SDK's default flush sends.
    ///
    /// Each of the SDK's three queues (events, People, groups) is one request
    /// the SDK bounds at 120 s, so a hung server can hold this for several
    /// minutes; prefer the plugin's `flush(timeout:)` on shutdown paths. The
    /// completion is delivered on the main queue, so never block the main
    /// thread waiting for it.
    public func flush() async {
        await withCheckedContinuation { continuation in
            instance.flush(performFullFlush: true) { continuation.resume() }
        }
    }

    // MARK: - Consent

    /// Applies a consent change: `true` calls ``optOutTracking()``, `false`
    /// calls ``optInTracking(distinctID:properties:)``.
    ///
    /// Shaped for the `AnalyticsPlugin`'s `onConsentChange` hook, so the SDK's
    /// own switch follows the plugin's gate:
    ///
    /// ```swift
    /// AnalyticsPlugin(
    ///     state: \.analytics,
    ///     action: AppAction.analytics,
    ///     extractAction: { if case .analytics(let a) = $0 { a } else { nil } },
    ///     service: mixpanel,
    ///     onConsentChange: { await mixpanel.setOptedOut($0) }
    /// )
    /// ```
    public func setOptedOut(_ optedOut: Bool) async {
        if optedOut {
            await optOutTracking()
        } else {
            await optInTracking()
        }
    }

    /// Opts the user out of all tracking, and returns once the SDK has
    /// applied it: from then on `track`, `identify`, and `alias` are dropped
    /// until ``optInTracking(distinctID:properties:)``. Does nothing if the
    /// user is already opted out. The choice persists across launches.
    ///
    /// Everything recorded before the opt-out is sent first, and the local
    /// identity is reset, as ``reset()`` does.
    ///
    /// > Important: This does not delete the user's Mixpanel profile or data.
    /// > The SDK's own opt-out queues a profile deletion but never sends it —
    /// > the leftover request would later delete the *next* identified user's
    /// > profile instead — so the adapter resets the identity before opting
    /// > out, and none is queued. To erase a user's data, use Mixpanel's GDPR
    /// > deletion API from your server.
    public func optOutTracking() async {
        await defaultOptOut?.value
        guard !instance.hasOptedOutTracking() else { return }
        await clearIdentity()
        instance.optOutTracking()
        await awaitOptOutFlag(true)
    }

    /// Opts the user back into tracking and returns once the SDK has applied
    /// it, so an `identify` issued straight afterwards is honored.
    ///
    /// The SDK records a `$opt_in` event, carrying `properties` if any (they
    /// are event properties, not profile properties); if `distinctID` is
    /// non-empty the user is identified first. The SDK queues that event a
    /// moment after the opt-in takes effect, so a `flush()` issued straight
    /// away may leave it for the next one. Init-time super properties are
    /// re-applied. When the user is already opted in, no `$opt_in` event is
    /// sent and only the `distinctID` identify happens.
    public func optInTracking(
        distinctID: String? = nil,
        properties: [String: AnalyticsValue]? = nil
    ) async {
        await defaultOptOut?.value
        let distinctID = distinctID.flatMap { $0.isEmpty ? nil : $0 }
        guard instance.hasOptedOutTracking() else {
            if let distinctID {
                await identify(userID: distinctID, properties: [:])
            }
            return
        }
        if let distinctID {
            // Opted out means nothing is queued for a previous user to flush.
            _ = session.identify(distinctID)
        }
        instance.optInTracking(
            distinctId: distinctID,
            properties: Self.nonEmptyProperties(properties)
        )
        await awaitOptOutFlag(false)
        registerSuperProperties()
    }

    /// `true` if the user has opted out, including an
    /// `optOutTrackingByDefault` that has not yet been lifted.
    public func hasOptedOutTracking() async -> Bool {
        await defaultOptOut?.value
        return instance.hasOptedOutTracking()
    }

    // MARK: - Diagnostics

    /// Toggles the Mixpanel SDK's internal logging. Set it once at launch:
    /// the SDK does not synchronize this property.
    public func setLoggingEnabled(_ enabled: Bool) async {
        instance.loggingEnabled = enabled
    }

    /// Toggles whether Mixpanel uses the request's IP address for geo
    /// resolution. Set it once at launch: the SDK does not synchronize this
    /// property.
    public func setUseIPAddressForGeoLocation(_ enabled: Bool) async {
        instance.useIPAddressForGeoLocation = enabled
    }

    // MARK: - Helpers

    private static func nonEmptyProperties(
        _ properties: [String: AnalyticsValue]?
    ) -> Properties? {
        guard let properties, !properties.isEmpty else { return nil }
        return properties.toMixpanelProperties()
    }

    /// Sends everything queued, then resets the SDK's identity. The full flush
    /// must finish first: the SDK's `reset()` flushes a partial batch of its
    /// own, which would otherwise send the same records a second time.
    private func clearIdentity() async {
        await flush()
        await withCheckedContinuation { continuation in
            instance.reset { continuation.resume() }
        }
        session.forgetUser()
    }

    private func registerSuperProperties() {
        guard let superProperties else { return }
        instance.registerSuperProperties(superProperties)
    }

    /// Suspends until the SDK's opt-out flag reads `optedOut`.
    ///
    /// The SDK flips the flag on its serial tracking queue but checks it on
    /// the caller's thread in `identify`, `flush`, and People calls, and it
    /// offers no completion for either transition — so the adapter watches
    /// the flag. The queue normally applies it within a millisecond; the
    /// bound only stops a pathological backlog from holding consent forever.
    private func awaitOptOutFlag(_ optedOut: Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while instance.hasOptedOutTracking() != optedOut, clock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(1))
            } catch {
                return
            }
        }
    }

    /// With `optOutTrackingByDefault`, the SDK queues its opt-out during
    /// `Mixpanel.initialize` unless the user opted in on an earlier launch —
    /// and until that queued opt-out runs, both cases read as opted in. A
    /// `flush` queued behind it is the barrier: its completion fires only
    /// after the queue has reached it, and it sends nothing while opted out.
    private static func awaitDefaultOptOut(of instance: UncheckedInstance) -> Task<Void, Never> {
        Task {
            await withCheckedContinuation { continuation in
                instance.value.flush { continuation.resume() }
            }
        }
    }
}

extension MixpanelAnalyticsService {
    /// Adapter-side state shared by every copy of the service.
    final class Session: Sendable {
        private let identifiedUserID = Mutex<String?>(nil)

        /// Records `userID` as identified; `true` when that is a change from
        /// the user identified before (or nobody known).
        func identify(_ userID: String) -> Bool {
            identifiedUserID.withLock { current in
                defer { current = userID }
                return current != userID
            }
        }

        func forgetUser() {
            identifiedUserID.withLock { $0 = nil }
        }
    }

    /// Carries the SDK instance into the `Task` created during `init`, before
    /// `self` exists to capture — the same guarantee the struct's own
    /// `@unchecked Sendable` rests on.
    private struct UncheckedInstance: @unchecked Sendable {
        let value: MixpanelInstance

        init(_ value: MixpanelInstance) {
            self.value = value
        }
    }
}
