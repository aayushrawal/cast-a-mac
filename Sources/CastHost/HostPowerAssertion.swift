#if os(macOS)
import Foundation
import IOKit.pwr_mgt

final class HostPowerAssertion {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

    init() throws {
        let result = IOPMAssertionCreateWithName(
            "PreventUserIdleSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Cast-a-mac is serving a remote session" as CFString,
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
