import Foundation
import Testing
@testable import AeroRouteCore

@Test func bundledAirportDatabaseIsSQLite() throws {
    let url = AirportDatabaseResource.url
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])

    #expect(url.lastPathComponent == "airports.sqlite")
    #expect(data.count > 100_000)
    #expect(data.starts(with: Data("SQLite format 3\0".utf8)))
}
