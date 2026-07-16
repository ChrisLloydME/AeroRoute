import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let aeroRouteSVG = UTType(
        filenameExtension: "svg",
        conformingTo: .image
    )!
}

struct SVGFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.aeroRouteSVG] }

    var data: Data

    init(svg: String) {
        data = Data(svg.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
