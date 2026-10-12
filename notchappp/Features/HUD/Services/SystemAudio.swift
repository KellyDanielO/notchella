import AudioToolbox
import CoreAudio

/// Reads and sets the volume and mute state of the default output device.
nonisolated enum SystemAudio {
    static var canControlVolume: Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static var volume: Float {
        get { read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, default: Float32(0)) }
        set { write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(max(newValue, 0), 1))) }
    }

    static var isMuted: Bool {
        get { read(kAudioDevicePropertyMute, default: UInt32(0)) != 0 }
        set { write(kAudioDevicePropertyMute, UInt32(newValue ? 1 : 0)) }
    }

    // MARK: Private

    private static var defaultOutputDevice: AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, default fallback: T) -> T {
        guard let device = defaultOutputDevice else { return fallback }
        var address = address(selector)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : fallback
    }

    private static func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, _ value: T) {
        guard let device = defaultOutputDevice else { return }
        var address = address(selector)
        var value = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}
