import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

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

nonisolated func rasterizedPNGFile(from svg: String, filename: String) throws -> URL {
    let svgData = Data(svg.utf8)
    let cgImage: CGImage

#if os(macOS)
    cgImage = try autoreleasepool {
        guard let image = NSImage(data: svgData) else {
            throw PhotoExportError.invalidSVG
        }
        guard image.size.width.isFinite,
              image.size.height.isFinite,
              image.size.width >= 1,
              image.size.height >= 1,
              image.size.width <= CGFloat(Int.max),
              image.size.height <= CGFloat(Int.max) else {
            throw PhotoExportError.invalidSVG
        }
        let pixelWidth = Int(image.size.width.rounded())
        let pixelHeight = Int(image.size.height.rounded())
        guard pixelWidth > 0,
              pixelHeight > 0,
              let representation = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: pixelWidth,
                  pixelsHigh: pixelHeight,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ),
              let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw PhotoExportError.invalidSVG
        }

        representation.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = representation.cgImage else {
            throw PhotoExportError.pngEncodingFailed
        }
        return cgImage
    }
#else
    guard let image = UIImage(data: svgData), image.size.width > 0, image.size.height > 0 else {
        throw PhotoExportError.invalidSVG
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    let renderedImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
    guard let renderedCGImage = renderedImage.cgImage else {
        throw PhotoExportError.pngEncodingFailed
    }
    cgImage = renderedCGImage
#endif

    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(filename)-\(UUID().uuidString)")
        .appendingPathExtension("png")
    guard let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw PhotoExportError.pngEncodingFailed
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        try? FileManager.default.removeItem(at: temporaryURL)
        throw PhotoExportError.pngEncodingFailed
    }
    return temporaryURL
}

enum PhotoLibraryExporter {
    static func save(pngAt fileURL: URL, filename: String) async throws {
        let authorization = await authorizationStatus()
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoExportError.accessDenied
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "\(filename).png"
                options.shouldMoveFile = true
                request.addResource(with: .photo, fileURL: fileURL, options: options)
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
