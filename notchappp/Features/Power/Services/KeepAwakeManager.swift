import Foundation
import IOKit.pwr_mgt
import Observation

/// Holds a power assertion that stops the Mac from idle-sleeping, like `caffeinate`.
///
/// It prevents *idle* sleep only. Closing a MacBook's lid still sleeps it unless it's on power
/// with an external display attached; macOS doesn't let apps override that.
@Observable
final class KeepAwakeManager {
    enum Mode: String, CaseIterable, Identifiable {
        case off
        case whileAgentsWork
        case always

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .whileAgentsWork: "While agents work"
            case .always: "Always"
            }
        }
    }

    private(set) var isHoldingAssertion = false

    @ObservationIgnored private var systemAssertion: IOPMAssertionID = 0
    @ObservationIgnored private var displayAssertion: IOPMAssertionID = 0
    @ObservationIgnored private var holdsDisplay = false

    /// Takes or releases the assertions to match the wanted state.
    func update(keepAwake: Bool, includeDisplay: Bool, reason: String) {
        if keepAwake && !isHoldingAssertion {
            systemAssertion = Self.create("PreventUserIdleSystemSleep", reason: reason)
            isHoldingAssertion = systemAssertion != 0
        } else if !keepAwake && isHoldingAssertion {
            IOPMAssertionRelease(systemAssertion)
            systemAssertion = 0
            isHoldingAssertion = false
        }

        let wantsDisplay = keepAwake && includeDisplay
        if wantsDisplay && !holdsDisplay {
            displayAssertion = Self.create("PreventUserIdleDisplaySleep", reason: reason)
            holdsDisplay = displayAssertion != 0
        } else if !wantsDisplay && holdsDisplay {
            IOPMAssertionRelease(displayAssertion)
            displayAssertion = 0
            holdsDisplay = false
        }
    }

    private static func create(_ type: String, reason: String) -> IOPMAssertionID {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : 0
    }
}
