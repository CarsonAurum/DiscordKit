#if canImport(AVFoundation) && canImport(os)
import AVFoundation
import Foundation
#if os(macOS)
import AudioToolbox
import CoreAudio
#endif

/// Direction of an Apple audio endpoint; a duplex CoreAudio device appears once per direction.
public enum AppleAudioDirection: Sendable, Equatable { case input, output }

/// Explicitly queried native endpoint metadata; identifiers can identify hardware and are never logged.
///
/// macOS enumerates selectable CoreAudio UIDs. Other Apple platforms expose available input ports
/// and current output routes only: output metadata does not imply arbitrary output UID selection.
/// watchOS inputs are metadata only because its public API cannot set a preferred input.
/// A snapshot can become stale immediately; an explicit start resolves the requested UID again.
public struct AppleAudioEndpoint: Sendable, Equatable {
    public let uid: String
    public let name: String
    public let direction: AppleAudioDirection
    public let isDefault: Bool
    public let isSelectable: Bool

    /// Validates owned endpoint strings without querying devices or retaining native port objects.
    /// - Parameters:
    ///   - uid: Nonempty native UID, at most 1,024 UTF-8 bytes, without embedded NUL.
    ///   - name: Human-readable name, at most 1,024 UTF-8 bytes; may be empty.
    ///   - direction: The single direction described by this entry.
    ///   - isDefault: Whether this endpoint is the observed system default/current route.
    ///   - isSelectable: Whether an explicit configuration UID can select this direction.
    /// - Throws: `AppleAudioError.invalidConfiguration` for invalid or excessive metadata.
    public init(uid: String, name: String, direction: AppleAudioDirection,
                isDefault: Bool, isSelectable: Bool) throws {
        guard AppleAudioRouting.validUID(uid), name.utf8.count <= 1_024, !name.contains("\0") else {
            throw AppleAudioError.invalidConfiguration
        }
        self.uid = uid
        self.name = name
        self.direction = direction
        self.isDefault = isDefault
        self.isSelectable = isSelectable
    }
}

/// Shared bounded metadata/selection rules, exercised independently of device access.
enum AppleAudioRouting {
    /// Validates an opaque UID without normalizing, trimming or revealing its hardware identity.
    /// - Parameter uid: Candidate native identifier; identifiers remain local to this machine.
    /// - Returns: Whether the identifier is nonempty, NUL-free and within the 1,024-byte limit.
    static func validUID(_ uid: String) -> Bool {
        !uid.isEmpty && uid.utf8.count <= 1_024 && !uid.contains("\0")
    }

    /// Resolves one exact explicit UID/direction and rejects unsupported or ambiguous selection.
    /// - Parameters:
    ///   - uid: Explicit identifier; nil preserves the system route and returns nil.
    ///   - direction: Required direction, never inferred from a matching name.
    ///   - endpoints: At most 512 queried entries, with at most one entry per UID/direction.
    /// - Returns: The matching selectable endpoint, or nil for system routing.
    /// - Throws: `invalidConfiguration` for invalid UID, `nativeFailure` for excessive/duplicate
    ///   metadata, `deviceUnavailable` for a missing direction, or `unsupportedDeviceSelection`.
    static func resolve(uid: String?, direction: AppleAudioDirection,
                        endpoints: [AppleAudioEndpoint]) throws -> AppleAudioEndpoint? {
        guard let uid else { return nil }
        guard validUID(uid) else { throw AppleAudioError.invalidConfiguration }
        guard endpoints.count <= 512 else { throw AppleAudioError.nativeFailure }
        let matches = endpoints.filter { $0.uid == uid && $0.direction == direction }
        guard matches.count <= 1 else { throw AppleAudioError.nativeFailure }
        guard let endpoint = matches.first else { throw AppleAudioError.deviceUnavailable }
        guard endpoint.isSelectable else { throw AppleAudioError.unsupportedDeviceSelection }
        return endpoint
    }
}

#if os(macOS)
/// Injectable current-device readback for the two AVAudioEngine I/O directions.
/// This seam verifies paired selection/startup without opening hardware in deterministic tests.
@MainActor protocol AppleAudioBoundDeviceProperties {
    /// Reads the actual device currently bound to one engine I/O node.
    /// - Parameter direction: Input or output node to inspect, without changing its binding.
    /// - Returns: Current native device ID, not a global system default.
    /// - Throws: `nativeFailure` for unavailable AudioUnit, invalid property size or native failure.
    func currentDevice(direction: AppleAudioDirection) throws -> AudioDeviceID
}

/// Exact paired binding verification before graph setup and again after native engine startup.
@MainActor enum AppleAudioHardwareBinding {
    /// Rejects silent coupling/rebinding of either explicitly selected engine I/O direction.
    /// - Parameters:
    ///   - input: Expected selected input ID, nil when system input routing was requested.
    ///   - output: Expected selected output ID, nil when system output routing was requested.
    ///   - properties: Native or deterministic current-device reader, queried input then output.
    /// - Throws: `deviceUnavailable` for any mismatch or unknown expected ID; native property
    ///   errors propagate. No setters, retries, fallback or retained device state are involved.
    /// - Complexity: At most two synchronous property reads and two bounded tuple entries;
    ///   no suspension, retries or device mutation occur.
    static func verify(input: AudioDeviceID?, output: AudioDeviceID?,
                       using properties: any AppleAudioBoundDeviceProperties) throws {
        for (direction, expected) in [(AppleAudioDirection.input, input), (.output, output)] {
            if let expected {
                guard expected != AudioDeviceID(kAudioObjectUnknown),
                      try properties.currentDevice(direction: direction) == expected else {
                    throw AppleAudioError.deviceUnavailable
                }
            }
        }
    }
}

/// Native scoped AudioUnit property reader; constructing it does not query or create I/O nodes.
@MainActor struct NativeAppleAudioBoundDeviceProperties: AppleAudioBoundDeviceProperties {
    private let engine: AVAudioEngine

    /// Retains an already explicitly constructed engine for bounded current-device readback.
    /// - Parameter engine: Engine owned by the active backend; no native operations run here.
    init(engine: AVAudioEngine) { self.engine = engine }

    /// Reads the requested node's actual device using the SDK's scoped API when available.
    /// - Parameter direction: Exact input/output node selected by the backend configuration.
    /// - Returns: The native currently bound device ID, including unknown when the unit reports it.
    /// - Throws: `nativeFailure` for an absent unit, native query failure or unexpected byte length.
    func currentDevice(direction: AppleAudioDirection) throws -> AudioDeviceID {
        let node: AVAudioIONode = direction == .input ? engine.inputNode : engine.outputNode
        if #available(macOS 27, *) {
            return try node.withAudioUnit { unit in try Self.read(unit) }
        } else {
            return try Self.read(node.audioUnit)
        }
    }

    /// Copies one exact-sized CurrentDevice property without changing global or engine routing.
    /// - Parameter unit: Callback-scoped I/O AudioUnit; nil means the native binding is unavailable.
    /// - Returns: Native device ID for this unit.
    /// - Throws: `nativeFailure` for nil unit, native error or a non-ID-sized property value.
    private static func read(_ unit: AudioUnit?) throws -> AudioDeviceID {
        guard let unit else { throw AppleAudioError.nativeFailure }
        var identifier = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                   0, &identifier, &size) == noErr,
              size == MemoryLayout<AudioDeviceID>.size else { throw AppleAudioError.nativeFailure }
        return identifier
    }
}

/// Injectable CoreAudio property boundary; all calls are explicit and serialized on MainActor.
@MainActor protocol AppleAudioHardwareProperties {
    /// Reads at most 256 current native device IDs; never opens an audio stream.
    /// - Returns: Native device IDs in system order, including devices with no audio streams.
    /// - Throws: `nativeFailure` for malformed/excessive data or a native query failure.
    func deviceIDs() throws -> [AudioDeviceID]

    /// Copies a bounded UID or display name, releasing the CoreAudio-owned returned CF object.
    /// - Parameters:
    ///   - device: Native ID from the current device-list snapshot.
    ///   - selector: Device UID or human-readable name property.
    /// - Returns: Owned Swift string with at most 1,024 UTF-8 bytes.
    /// - Throws: `nativeFailure` for missing/malformed metadata or a disconnected device.
    func string(device: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String

    /// Tests stream availability for one device direction without opening the device.
    /// - Parameters:
    ///   - device: Native ID from a current snapshot.
    ///   - direction: Input or output streams to inspect.
    /// - Returns: Whether at least one stream exists in this direction.
    /// - Throws: `nativeFailure` for malformed/excessive stream metadata or query failure.
    func hasStreams(device: AudioDeviceID, direction: AppleAudioDirection) throws -> Bool

    /// Reads the system's default device for one direction without changing global routing.
    /// - Parameter direction: Input/output default to inspect.
    /// - Returns: Native default ID, or kAudioObjectUnknown if no default exists.
    /// - Throws: `nativeFailure` for invalid native property data.
    func defaultDevice(direction: AppleAudioDirection) throws -> AudioDeviceID
}

/// Bounded UID catalog and native-ID lookup, independent of an AVAudioEngine instance.
@MainActor enum AppleAudioHardwareCatalog {
    /// Enumerates selectable input/output UIDs; a concurrent unplug fails the whole snapshot closed.
    /// - Parameter properties: Native or deterministic property reader; never retained.
    /// - Returns: At most 512 immutable entries, preserving system device and input/output order.
    /// - Throws: `nativeFailure` for duplicate IDs/UIDs, excessive data or native query failures.
    static func endpoints(using properties: any AppleAudioHardwareProperties) throws -> [AppleAudioEndpoint] {
        let devices = try properties.deviceIDs()
        guard devices.count <= 256, !devices.contains(AudioDeviceID(kAudioObjectUnknown)),
              Set(devices).count == devices.count else { throw AppleAudioError.nativeFailure }
        let input = try properties.defaultDevice(direction: .input)
        let output = try properties.defaultDevice(direction: .output)
        var result: [AppleAudioEndpoint] = []
        var seen: Set<String> = []
        for device in devices {
            let uid = try properties.string(device: device, selector: kAudioDevicePropertyDeviceUID)
            guard seen.insert(uid).inserted else { throw AppleAudioError.nativeFailure }
            let name = try properties.string(device: device, selector: kAudioObjectPropertyName)
            guard AppleAudioRouting.validUID(uid), name.utf8.count <= 1_024, !name.contains("\0") else {
                throw AppleAudioError.nativeFailure
            }
            for direction in [AppleAudioDirection.input, .output] where try properties.hasStreams(device: device, direction: direction) {
                result.append(try AppleAudioEndpoint(uid: uid, name: name, direction: direction,
                    isDefault: device == (direction == .input ? input : output), isSelectable: true))
            }
        }
        return result
    }

    /// Resolves a requested UID again at start, rejecting disappeared or direction-ineligible devices.
    /// - Parameters:
    ///   - uid: Nonempty caller-selected identifier, previously validated by configuration.
    ///   - direction: Direction that the native I/O node must support.
    ///   - properties: Current native property view, queried synchronously without retries.
    /// - Returns: Exact matching native ID, never an unrelated default fallback.
    /// - Throws: `deviceUnavailable` for a missing UID/direction; `nativeFailure` for malformed data.
    static func deviceID(uid: String, direction: AppleAudioDirection,
                         using properties: any AppleAudioHardwareProperties) throws -> AudioDeviceID {
        guard AppleAudioRouting.validUID(uid) else { throw AppleAudioError.invalidConfiguration }
        let devices = try properties.deviceIDs()
        guard devices.count <= 256, !devices.contains(AudioDeviceID(kAudioObjectUnknown)),
              Set(devices).count == devices.count else { throw AppleAudioError.nativeFailure }
        var match: AudioDeviceID?
        for device in devices where try properties.string(device: device, selector: kAudioDevicePropertyDeviceUID) == uid {
            guard match == nil else { throw AppleAudioError.nativeFailure }
            match = device
        }
        guard let match, try properties.hasStreams(device: match, direction: direction) else {
            throw AppleAudioError.deviceUnavailable
        }
        return match
    }
}

/// Real CoreAudio property reads; construction is inert and every native allocation has a fixed cap.
@MainActor struct NativeAppleAudioHardwareProperties: AppleAudioHardwareProperties {
    /// Reads device IDs into at most 1,024 bytes and validates native returned length.
    /// - Returns: Current system device IDs, possibly empty.
    /// - Throws: `nativeFailure` for query failures, invalid lengths or more than 256 IDs.
    func deviceIDs() throws -> [AudioDeviceID] {
        try identifiers(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices,
                        scope: kAudioObjectPropertyScopeGlobal)
    }

    /// Takes ownership of a CoreAudio CFString and copies only bounded metadata to Swift storage.
    /// - Parameters:
    ///   - device: Device to inspect, without opening its stream.
    ///   - selector: CFString property selector, ordinarily UID/name.
    /// - Returns: Bounded owned Swift string.
    /// - Throws: `nativeFailure` for absent/oversize strings, bad lengths or native query errors.
    func string(device: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard let owned = value else { throw AppleAudioError.nativeFailure }
        let string = owned.takeRetainedValue()
        guard status == noErr, size == MemoryLayout<Unmanaged<CFString>?>.size,
              CFStringGetLength(string) <= 1_024 else { throw AppleAudioError.nativeFailure }
        let result = string as String
        guard result.utf8.count <= 1_024, !result.contains("\0") else { throw AppleAudioError.nativeFailure }
        return result
    }

    /// Inspects at most 256 stream IDs in one direction; no audio buffers or engines are created.
    /// - Parameters:
    ///   - device: Native device ID, potentially invalidated by hot-unplug.
    ///   - direction: Stream scope to inspect.
    /// - Returns: Whether at least one native stream exists.
    /// - Throws: `nativeFailure` for query/length/capacity failures.
    func hasStreams(device: AudioDeviceID, direction: AppleAudioDirection) throws -> Bool {
        try !identifiers(object: device, selector: kAudioDevicePropertyStreams,
                         scope: direction == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput).isEmpty
    }

    /// Copies one exact-sized system default ID, preserving kAudioObjectUnknown when no route exists.
    /// - Parameter direction: Required system-default scope.
    /// - Returns: Current default ID without changing machine-wide preferences.
    /// - Throws: `nativeFailure` for a native query failure or unexpected returned byte length.
    func defaultDevice(direction: AppleAudioDirection) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: direction == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<AudioDeviceID>.size else { throw AppleAudioError.nativeFailure }
        return value
    }

    /// Reads a capped native ID array with one allocation and rejects any racing size change.
    /// - Parameters:
    ///   - object: System or device ID exposing an array property.
    ///   - selector: Device-list or stream-list property selector.
    ///   - scope: Exact global/input/output scope.
    /// - Returns: At most 256 IDs; an empty property returns an empty array without a second query.
    /// - Throws: `nativeFailure` for native failure, fractional/excessive length or racing growth.
    private func identifiers(object: AudioObjectID, selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size <= 256 * MemoryLayout<AudioObjectID>.size,
              size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { throw AppleAudioError.nativeFailure }
        guard size > 0 else { return [] }
        let expectedSize = size
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = result.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
        }
        guard status == noErr, size == expectedSize else { throw AppleAudioError.nativeFailure }
        return result
    }
}
#endif
#endif
