#if os(macOS)
import Foundation
import IOKit.pwr_mgt

final class HostPowerAssertion {
    private var assertionIDs: [IOPMAssertionID] = []

    init() throws {
        for assertionType in [
            "PreventUserIdleDisplaySleep",
            "PreventUserIdleSystemSleep"
        ] {
            var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
            let result = IOPMAssertionCreateWithName(
                assertionType as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Cast-a-mac is streaming the active display" as CFString,
                &assertionID
            )
            guard result == kIOReturnSuccess else {
                assertionIDs.forEach { assertionID in
                    _ = IOPMAssertionRelease(assertionID)
                }
                throw HostPowerAssertionError.creationFailed(result)
            }
            assertionIDs.append(assertionID)
        }
    }

    deinit {
        assertionIDs.forEach { assertionID in
            _ = IOPMAssertionRelease(assertionID)
        }
    }
}

enum HostPowerAssertionError: Error {
    case creationFailed(IOReturn)
}
#endif
