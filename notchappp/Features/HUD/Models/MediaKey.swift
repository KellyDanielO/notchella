import Foundation

/// Hardware media keys, keyed by their `NX_KEYTYPE_*` codes from `<IOKit/hidsystem/ev_keymap.h>`.
nonisolated enum MediaKey: Int, Sendable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7

    var kind: HUDKind {
        switch self {
        case .volumeUp, .volumeDown, .mute: .volume
        case .brightnessUp, .brightnessDown: .brightness
        }
    }
}

nonisolated enum HUDKind: Sendable {
    case volume
    case brightness
}
