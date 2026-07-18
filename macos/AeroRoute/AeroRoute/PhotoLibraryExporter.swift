import Foundation
import Photos

#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PhotoExportError: LocalizedError {
    case invalidSVG
    case pngEncodingFailed
    case accessDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidSVG:
            "The exported SVG could not be rendered as an image."
        case .pngEncodingFailed:
            "The rendered image could not be encoded as PNG."
        case .accessDenied:
            "AeroRoute does not have permission to add images to Photos."
        case .saveFailed:
            "Photos could not save the exported PNG."
        }
    }
}

nonisolated func rasterizedPNGData(from svg: String) throws -> Data {
    let svgData = Data(svg.utf8)

#if os(macOS)
    guard let image = NSImage(data: svgData) else {
        throw PhotoExportError.invalidSVG
    }
    var proposedRect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(
        forProposedRect: &proposedRect,
        context: nil,
        hints: nil
    ) else {
        throw PhotoExportError.invalidSVG
    }
    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw PhotoExportError.pngEncodingFailed
    }
    return data
#else
    guard let image = UIImage(data: svgData), image.size.width > 0, image.size.height > 0 else {
        throw PhotoExportError.invalidSVG
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.pngData { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
#endif
}

enum PhotoLibraryExporter {
    static func save(pngData: Data, filename: String) async throws {
        let authorization = await authorizationStatus()
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoExportError.accessDenied
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename)-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try pngData.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                guard PHAssetChangeRequest.creationRequestForAssetFromImage(
                    atFileURL: temporaryURL
                ) != nil else {
                    return
                }
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoExportError.saveFailed)
                }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
