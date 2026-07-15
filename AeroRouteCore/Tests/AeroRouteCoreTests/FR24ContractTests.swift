import Foundation
import Testing
@testable import AeroRouteCore

@Suite(.serialized)
struct FR24ContractTests {
    private let header = "Timestamp,UTC,Callsign,Position,Altitude,Speed,Direction\r\n"

    @Test func bomRFC4180QuotesOptionalBlanksAndUTCFallback() throws {
        let imported = try loadFixture(
            name: "lx188_download.csv",
            contents: "\u{FEFF}" + header
                + "20,,\"CALL,ONE\",\"10.5,20.25\",,\"\",   \r\n"
                + "10,2026-07-13T11:08:08Z,CALL\"\"2,\"11.5,21.25\",100,200,90\r\n"
        )

        #expect(imported.track.points.map(\.timestamp) == [10, 20])
        #expect(imported.track.points[0].callsign == "CALL\"\"2")
        #expect(imported.track.points[1].callsign == "CALL,ONE")
        #expect(imported.track.points[1].altitude == nil)
        #expect(imported.track.points[1].speed == nil)
        #expect(imported.track.points[1].direction == nil)
        #expect(imported.track.points[1].utc == Date(timeIntervalSince1970: 20))
        #expect(imported.metadata.flightNumber == "LX188")
        #expect(imported.metadata.callsign == "CALL\"\"2")
        #expect(imported.metadata.rowCount == 2)
    }

    @Test func escapedQuoteAndEmbeddedNewlineAreParsedAsRFC4180() throws {
        let imported = try loadFixture(
            name: "quotes.csv",
            contents: header
                + "1,,\"CALL\"\"ONE\",\"1,2\",,,\r\n"
                + "2,,\"LINE\r\nTWO\",\"3,4\",,,\r\n"
        )

        #expect(imported.track.points[0].callsign == "CALL\"ONE")
        #expect(imported.track.points[1].callsign == "LINE\r\nTWO")
    }

    @Test func optionalColumnsMayBeAbsent() throws {
        let imported = try loadFixture(
            name: "minimal.csv",
            contents: "Timestamp,UTC,Callsign,Position\n"
                + "1,,ONE,\"10,20\"\n"
                + "2,,TWO,\"11,21\"\n"
        )

        #expect(imported.track.points.allSatisfy {
            $0.altitude == nil && $0.speed == nil && $0.direction == nil
        })
    }

    @Test func timestampSortIsStableAndRepeatedCoordinatesRemain() throws {
        let imported = try loadFixture(
            name: "stable.csv",
            contents: header
                + "2,,LATE,\"0,0\",,,\n"
                + "1,,FIRST,\"1,1\",,,\n"
                + "1,,SECOND,\"1,1\",,,\n"
        )

        #expect(imported.track.points.map(\.callsign) == ["FIRST", "SECOND", "LATE"])
        #expect(
            imported.track.points.prefix(2).map { [$0.latitude, $0.longitude] }
                == [[1, 1], [1, 1]]
        )
    }

    @Test func filenameMetadataMatchesFR24Convention() {
        #expect(flightNumberFromFilename("LX188_40a4c777.csv") == "LX188")
        #expect(flightNumberFromFilename("sq22.csv") == "SQ22")
        #expect(flightNumberFromFilename("not-a-flight.csv") == "not-a-flight")
    }

    @Test func invalidInputsKeepExactUserFacingMessages() throws {
        let cases: [(String, String, String)] = [
            (
                "missing.csv",
                "Timestamp,Callsign\n1,A\n",
                "not a standard Flightradar24 CSV; missing columns: Position, UTC"
            ),
            (
                "timestamp.csv",
                header + "bad,,A,\"1,2\",,,\n2,,B,\"1,2\",,,\n",
                "row 2: invalid Timestamp: 'bad'"
            ),
            (
                "position-shape.csv",
                header + "1,,A,12,,,\n2,,B,\"1,2\",,,\n",
                "row 2: Position must be 'latitude,longitude'"
            ),
            (
                "position-value.csv",
                header + "1,,A,\"north,2\",,,\n2,,B,\"1,2\",,,\n",
                "row 2: invalid Position: 'north,2'"
            ),
            (
                "latitude.csv",
                header + "1,,A,\"91,2\",,,\n2,,B,\"1,2\",,,\n",
                "row 2: latitude out of range"
            ),
            (
                "longitude.csv",
                header + "1,,A,\"1,181\",,,\n2,,B,\"1,2\",,,\n",
                "row 2: longitude out of range"
            ),
            (
                "optional.csv",
                header + "1,,A,\"1,2\",high,,\n2,,B,\"1,2\",,,\n",
                "row 2: invalid Altitude: 'high'"
            ),
            (
                "utc.csv",
                header + "1,yesterday,A,\"1,2\",,,\n2,,B,\"1,2\",,,\n",
                "row 2: invalid UTC: 'yesterday'"
            ),
            (
                "short.csv",
                header + "1,,A,\"1,2\",,,\n",
                "at least two FR24 positions are required"
            ),
        ]

        for (name, contents, expected) in cases {
            do {
                _ = try loadFixture(name: name, contents: contents)
                Issue.record("Expected \(name) to fail")
            } catch let error as TrackDataError {
                #expect(error.description == expected)
                #expect(error.localizedDescription == expected)
            }
        }
    }

    @Test func blankPhysicalRowsDoNotAdvanceDictReaderRecordNumber() throws {
        do {
            _ = try loadFixture(
                name: "blank-lines.csv",
                contents: header + "\n\r\ninvalid,,A,\"1,2\",,,\n"
            )
            Issue.record("The invalid timestamp must fail")
        } catch let error as TrackDataError {
            #expect(error.description == "row 2: invalid Timestamp: 'invalid'")
        }
    }

    @Test func exampleFileLoadsEverySourceRow() throws {
        let imported = try loadFR24(exampleData.appending(path: "lx188.csv"))

        #expect(imported.track.points.count == 2_697)
        #expect(imported.metadata.flightNumber == "LX188")
        #expect(imported.metadata.callsign == "SWR188")
        #expect(imported.metadata.rowCount == 2_697)
        #expect(imported.track.waypointIndices == [0, 2_696])
    }

    private func loadFixture(name: String, contents: String) throws -> ImportedLeg {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: name)
        try Data(contents.utf8).write(to: file)
        return try loadFR24(file)
    }
}

@Suite(.serialized)
struct RouteContractTests {
    @Test func default50KMMultiLegContractAndNoCrossLegResort() throws {
        let paths = ["lh727.csv", "lh2440.csv", "fi217.csv"].map {
            exampleData.appending(path: $0)
        }
        let tracks = try paths.map(loadTrack)
        let distances = try validateLegOrder(tracks)

        #expect(distances.count == 2)
        #expect(distances.allSatisfy { $0 < 50 })

        let combined = try combineTracks(paths: paths, validateContinuity: true)
        #expect(combined.points.count == tracks.reduce(0) { $0 + $1.points.count })
        #expect(combined.waypoints.count == 4)
        #expect(combined.waypointIndices == [
            0,
            tracks[0].points.count - 1,
            tracks[0].points.count + tracks[1].points.count - 1,
            combined.points.count - 1,
        ])

        let late = makeTrack(timestamps: [100, 200], longitudes: [0, 0])
        let early = makeTrack(timestamps: [1, 2], longitudes: [0, 0])
        let unsorted = try combineTracks(tracks: [late, early])
        #expect(unsorted.points.map(\.timestamp) == [100, 200, 1, 2])
        #expect(unsorted.waypointIndices == [0, 1, 3])
        #expect(unsorted.points.count == 4)
    }

    @Test func thresholdEqualityPassesButSmallerToleranceFails() throws {
        let first = makeTrack(timestamps: [1, 2], longitudes: [0, 0])
        let second = makeTrack(timestamps: [3, 4], longitudes: [0.45, 0.45])
        let distance = endpointDistanceKM(first, second)

        #expect(try validateLegOrder([first, second], toleranceKM: distance) == [distance])
        do {
            _ = try validateLegOrder([first, second], toleranceKM: distance.nextDown)
            Issue.record("A tolerance below the measured distance must fail")
        } catch let error as TrackDataError {
            let formatted = String(
                format: "%.1f",
                locale: Locale(identifier: "en_US_POSIX"),
                distance
            )
            #expect(
                error.description
                    == "leg 1 does not connect to leg 2: end-to-start distance is "
                    + "\(formatted) km"
            )
        }
    }

    @Test func toleranceAndEmptyItineraryErrorsAreExact() throws {
        let track = makeTrack(timestamps: [1, 2], longitudes: [0, 0])
        do {
            _ = try validateLegOrder([track], toleranceKM: 0)
            Issue.record("Zero tolerance must fail")
        } catch let error as TrackDataError {
            #expect(error.description == "continuity tolerance must be greater than zero")
        }

        do {
            _ = try combineTracks(paths: [URL]())
            Issue.record("An empty itinerary must fail")
        } catch let error as TrackDataError {
            #expect(error.description == "at least one ADS-B CSV file is required")
        }
    }

    private func makeTrack(timestamps: [Double], longitudes: [Double]) -> Track {
        Track(
            source: URL(fileURLWithPath: "fixture.csv"),
            points: zip(timestamps, longitudes).map { timestamp, longitude in
                TrackPoint(
                    timestamp: timestamp,
                    utc: Date(timeIntervalSince1970: timestamp),
                    callsign: "TEST",
                    latitude: 0,
                    longitude: longitude,
                    altitude: nil,
                    speed: nil,
                    direction: nil
                )
            },
            waypointIndices: [0, timestamps.count - 1]
        )
    }
}

private let exampleData: URL = {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "examples/data", directoryHint: .isDirectory)
}()
