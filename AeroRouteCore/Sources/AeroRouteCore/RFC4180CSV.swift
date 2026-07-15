import Foundation

struct CSVDocument: Sendable, Equatable {
    let rows: [[String]]

    init(data: Data) throws {
        guard var contents = String(data: data, encoding: .utf8) else {
            throw TrackDataError("CSV is not valid UTF-8")
        }
        if contents.unicodeScalars.first == "\u{FEFF}" {
            contents.removeFirst()
        }
        rows = Self.parse(contents)
    }

    private static func parse(_ contents: String) -> [[String]] {
        let scalars = Array(contents.unicodeScalars)
        let quote: Unicode.Scalar = "\""
        let comma: Unicode.Scalar = ","
        let carriageReturn: Unicode.Scalar = "\r"
        let lineFeed: Unicode.Scalar = "\n"

        var parsed: [[String]] = []
        var row: [String] = []
        var field = ""
        var isQuoted = false
        var rowHasToken = false
        var index = 0

        func finishField() {
            row.append(field)
            field.removeAll(keepingCapacity: true)
        }

        func finishRow() {
            if rowHasToken || !row.isEmpty || !field.isEmpty {
                finishField()
                parsed.append(row)
            } else {
                // csv.reader represents a physically blank line as an empty row.
                parsed.append([])
            }
            row.removeAll(keepingCapacity: true)
            rowHasToken = false
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == quote {
                rowHasToken = true
                if isQuoted {
                    if index + 1 < scalars.count, scalars[index + 1] == quote {
                        field.unicodeScalars.append(quote)
                        index += 1
                    } else {
                        isQuoted = false
                    }
                } else if field.isEmpty {
                    isQuoted = true
                } else {
                    field.unicodeScalars.append(quote)
                }
            } else if scalar == comma, !isQuoted {
                rowHasToken = true
                finishField()
            } else if (scalar == carriageReturn || scalar == lineFeed), !isQuoted {
                if scalar == carriageReturn,
                   index + 1 < scalars.count,
                   scalars[index + 1] == lineFeed {
                    index += 1
                }
                finishRow()
            } else {
                rowHasToken = true
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }

        if rowHasToken || !row.isEmpty || !field.isEmpty {
            finishField()
            parsed.append(row)
        }
        return parsed
    }
}

struct CSVRecord: Sendable, Equatable {
    let headers: [String]
    let fields: [String]

    subscript(_ name: String) -> String? {
        var value: String?
        for (header, field) in zip(headers, fields) where header == name {
            value = field
        }
        return value
    }
}
