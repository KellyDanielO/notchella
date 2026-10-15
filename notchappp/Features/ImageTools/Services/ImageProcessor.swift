import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// What to do to each image. Every step is optional; they run in order: resize, cut out, encode.
nonisolated struct ImageEditOptions: Sendable {
    enum Size: Hashable, Sendable, CaseIterable {
        case original
        case half
        case longEdge(Int)

        static let allCases: [Size] = [.original, .half, .longEdge(2048), .longEdge(1080), .longEdge(512)]

        var title: String {
            switch self {
            case .original: "Original"
            case .half: "50%"
            case .longEdge(let pixels): "\(pixels)"
            }
        }
    }

    enum Format: String, Sendable, CaseIterable {
        case same
        case png
        case jpeg
        case heic

        var title: String {
            switch self {
            case .same: "Same"
            case .png: "PNG"
            case .jpeg: "JPEG"
            case .heic: "HEIC"
            }
        }
    }

    var removeBackground: Bool
    var size: Size
    var format: Format
    var quality: Double
}

nonisolated enum ImageToolError: LocalizedError {
    case unreadable
    case noSubject
    case unwritable

    var errorDescription: String? {
        switch self {
        case .unreadable: "Couldn't read this image."
        case .noSubject: "No subject found to cut out."
        case .unwritable: "Couldn't save the result."
        }
    }
}

/// The image work itself. Runs off the main thread; everything here is on-device.
nonisolated enum ImageProcessor {
    /// Renders `source` with `options` into `folder` under a throwaway name, and returns the file.
    /// Results are previewed from there; saving copies them out under a readable name.
    static func process(_ source: URL, options: ImageEditOptions, into folder: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw ImageToolError.unreadable }

        let longEdge = max(width, height)
        let targetEdge = switch options.size {
        case .original: longEdge
        case .half: max(longEdge / 2, 1)
        case .longEdge(let pixels): min(pixels, longEdge)
        }

        // The thumbnail API applies the EXIF orientation and downsamples in one pass,
        // which is faster and lighter than decoding the full image and scaling it afterwards.
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, decodeOptions as CFDictionary) else {
            throw ImageToolError.unreadable
        }

        if options.removeBackground {
            image = try cutOutSubject(image)
        }

        let type = outputType(for: options, source: imageSource)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destinationURL = folder.appending(path: "\(UUID().uuidString).\(type.preferredFilenameExtension ?? "png")")

        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, type.identifier as CFString, 1, nil) else {
            throw ImageToolError.unwritable
        }
        let encodeOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: options.quality]
        CGImageDestinationAddImage(destination, image, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageToolError.unwritable }
        return destinationURL
    }

    /// A small preview for the tray, orientation applied.
    static func thumbnail(of url: URL, maxPixelSize: Int = 240) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Keeps the foreground subjects (people, pets, objects) and makes everything else transparent.
    /// The same on-device model as "Lift subject" in Photos.
    private static func cutOutSubject(_ image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw ImageToolError.noSubject
        }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext().createCGImage(masked, from: masked.extent) else {
            throw ImageToolError.unwritable
        }
        return result
    }

    /// The chosen format. Cutouts default to PNG, the format every app reads transparency from,
    /// and never go to JPEG, which can't hold it.
    private static func outputType(for options: ImageEditOptions, source: CGImageSource) -> UTType {
        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) } ?? .png
        let chosen: UTType = switch options.format {
        case .same: options.removeBackground ? .png : sourceType
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
        if options.removeBackground && !(chosen == .png || chosen == .heic) {
            return .png
        }
        // Formats ImageIO can read but not write (like WebP) fall back to PNG.
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writable.contains(chosen.identifier) ? chosen : .png
    }

    /// "photo.jpg" → "photo-cutout-1080-7F3A9C.png": what was done, plus a short random ID so
    /// saving into Downloads never collides with an earlier export.
    static func savedName(for source: URL, options: ImageEditOptions, fileExtension: String) -> String {
        var name = source.deletingPathExtension().lastPathComponent
        if options.removeBackground { name += "-cutout" }
        switch options.size {
        case .original: break
        case .half: name += "-50"
        case .longEdge(let pixels): name += "-\(pixels)"
        }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)
        return "\(name)-\(id).\(fileExtension)"
    }
}
