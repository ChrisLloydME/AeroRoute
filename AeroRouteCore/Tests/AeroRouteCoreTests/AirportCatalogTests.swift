import XCTest
@testable import AeroRouteCore

final class AirportCatalogTests: XCTestCase {
    func testCatalogReturnsIATAAirportsInNameOrder() throws {
        let airports = try AirportCatalog.airportsAlphabetically()

        XCTAssertGreaterThan(airports.count, 1_000)
        XCTAssertTrue(airports.allSatisfy { $0.iataCode.count == 3 })
        XCTAssertNotNil(airports.first { $0.iataCode == "PVG" })
        XCTAssertEqual(airports.first?.name, "28 de Noviembre Airport")
    }
}
