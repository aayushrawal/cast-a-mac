import Foundation
import Testing
@testable import CastTransport

@Test
func linkResponseDecodesISO8601Date() throws {
    let data = Data(
        """
        {
          "host": {
            "id": "D2699C60-F8F0-49DF-9A03-BD2ED9B5ACB5",
            "name": "Studio Mac",
            "isOnline": true,
            "lastSeenAt": "2026-06-13T03:50:51.008Z"
          },
          "accessToken": "test-token"
        }
        """.utf8
    )

    let response = try RelayCoordinationClient.decodeLinkResponse(data)

    #expect(response.host.name == "Studio Mac")
    #expect(response.host.isOnline)
    #expect(response.accessToken == "test-token")
}
