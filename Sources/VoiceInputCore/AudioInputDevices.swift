import CoreAudio
import Foundation

/// A Core Audio input that `AudioCapture` can bind to.
public struct AudioInputDevice: Equatable, Identifiable, Sendable {
    public var id: String { uid }
    public let uid: String
    public let name: String
    public let deviceID: AudioDeviceID
    public let isDefault: Bool
    public let transport: Transport

    public enum Transport: Sendable, Equatable {
        case builtIn
        case bluetooth
        case usb
        case aggregate
        case virtual
        case other

        public var label: String? {
            switch self {
            case .builtIn: return "内置"
            case .bluetooth: return "蓝牙"
            case .usb: return "USB"
            case .aggregate: return "聚合"
            case .virtual: return "虚拟"
            case .other: return nil
            }
        }
    }

    public var menuLabel: String {
        var parts: [String] = []
        if let transport = transport.label { parts.append(transport) }
        if isDefault { parts.append("系统默认") }
        if parts.isEmpty { return name }
        return "\(name)（\(parts.joined(separator: "，"))）"
    }
}

public enum AudioInputs {
    /// Empty / nil UID means “follow the system default input”.
    public static func resolve(uid: String?) -> AudioInputDevice? {
        let devices = list()
        if let uid, !uid.isEmpty {
            return devices.first { $0.uid == uid }
        }
        return devices.first(where: \.isDefault) ?? devices.first
    }

    public static func list() -> [AudioInputDevice] {
        let ids = allDeviceIDs()
        let defaultID = defaultInputDeviceID()
        var seen = Set<String>()
        var devices: [AudioInputDevice] = []
        for id in ids {
            guard inputChannelCount(id) > 0 else { continue }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID), seen.insert(uid).inserted else {
                continue
            }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? "麦克风"
            devices.append(
                AudioInputDevice(
                    uid: uid,
                    name: name,
                    deviceID: id,
                    isDefault: defaultID.map { $0 == id } ?? false,
                    transport: transport(of: id)
                )
            )
        }
        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        var channels = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    private static func transport(of id: AudioDeviceID) -> AudioInputDevice.Transport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else {
            return .other
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        case kAudioDeviceTransportTypeVirtual: return .virtual
        default: return .other
        }
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else {
            return nil
        }
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        let string = value.takeUnretainedValue() as String
        return string.isEmpty ? nil : string
    }
}

/// Observes Core Audio device plug/unplug and default-input changes.
/// Bluetooth mics (AirPods) often appear before their input stream is ready,
/// so each burst is re-emitted a few times after a short delay.
public final class AudioInputWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "voice.input.devices")
    private var generation = 0
    private var onChange: (() -> Void)?
    private var started = false
    private var devicesBlock: AudioObjectPropertyListenerBlock?
    private var defaultBlock: AudioObjectPropertyListenerBlock?
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    public init() {}

    deinit { stop() }

    public func start(onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        let devicesBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.schedule()
        }
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.schedule()
        }
        self.devicesBlock = devicesBlock
        self.defaultBlock = defaultBlock
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, queue, devicesBlock)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, queue, defaultBlock)
        started = true
    }

    public func stop() {
        generation += 1
        guard started else {
            onChange = nil
            return
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let devicesBlock {
            AudioObjectRemovePropertyListenerBlock(system, &devicesAddress, queue, devicesBlock)
        }
        if let defaultBlock {
            AudioObjectRemovePropertyListenerBlock(system, &defaultAddress, queue, defaultBlock)
        }
        devicesBlock = nil
        defaultBlock = nil
        onChange = nil
        started = false
    }

    private func schedule() {
        generation += 1
        let gen = generation
        for delay in [0.12, 0.7, 2.2] {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.generation == gen else { return }
                self.onChange?()
            }
        }
    }
}
