import AppKit

/// The gesture that opens the panel: tap a modifier twice quickly (default) or hold it for a second.
///
/// Left and right modifiers share one flag (`.option`), so the side is told apart by the
/// device-dependent bits in the low byte of the flags (the `NX_DEVICEL…KEYMASK` values).
enum TriggerKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case doubleLeftOption, doubleRightOption, holdLeftOption, holdRightOption
    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleLeftOption: "Double-tap left ⌥ Option (recommended)"
        case .doubleRightOption: "Double-tap right ⌥ Option"
        case .holdLeftOption: "Hold left ⌥ Option for 1 second"
        case .holdRightOption: "Hold right ⌥ Option for 1 second"
        }
    }

    /// Short form for help text: "Press left ⌥ twice, quickly".
    var short: String {
        switch self {
        case .doubleLeftOption: "left ⌥ twice, quickly"
        case .doubleRightOption: "right ⌥ twice, quickly"
        case .holdLeftOption: "left ⌥ for 1 second"
        case .holdRightOption: "right ⌥ for 1 second"
        }
    }

    var isDoubleTap: Bool { self == .doubleLeftOption || self == .doubleRightOption }

    var flag: NSEvent.ModifierFlags { .option }

    /// Device bit of this key (0x20 = left ⌥, 0x40 = right ⌥).
    var deviceBit: UInt {
        switch self {
        case .doubleLeftOption, .holdLeftOption: 0x20
        case .doubleRightOption, .holdRightOption: 0x40
        }
    }

    /// Device bit of the same modifier on the other side.
    var otherSideBit: UInt { deviceBit == 0x20 ? 0x40 : 0x20 }

    /// What the current modifier flags mean for this trigger.
    func state(of flags: NSEvent.ModifierFlags) -> KeyState {
        let mods = flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if mods.isEmpty { return .released }
        if mods == flag, flags.rawValue & deviceBit != 0, flags.rawValue & otherSideBit == 0 { return .onlyTrigger }
        return .other
    }
}

/// Modifier state as seen by the detectors, so they stay free of AppKit and easy to test.
enum KeyState: Equatable, Sendable {
    /// No modifier is held.
    case released
    /// Only the trigger key is held (no other modifier, not the other side).
    case onlyTrigger
    /// Some other modifier, or a combination: a shortcut, not a tap.
    case other
}
