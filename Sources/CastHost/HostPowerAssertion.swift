#if os(macOS)
import Foundation
import IOKit.pwr_mgt

final class HostPowerAssertion {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

    init() throws {
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleDisplaySleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Cast-a-mac is capturing the active display" as CFString,
            &assertionID
        )
        guard result == kIOReturnSuccess else {
            throw HostPowerAssertionError.creationFailed(result)
        }
    }

    deinit {
        if assertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(assertionID)
        }
    }
}

enum HostPowerAssertionError: Error {
    case creationFailed(IOReturn)
}
#endif
