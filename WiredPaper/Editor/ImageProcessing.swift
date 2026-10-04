import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Picture edits. Every operation returns a new image; the document stores the
/// result, so edits survive in every format.
enum ImageProcessing {
    /// Renders `size` points at 2× into a bitmap-backed image.
    static func render(size: CGSize, scale: CGFloat = 2, _ body: () -> Void) -> NSImage {
        let pixelsWide = max(Int((size.width * scale).rounded()), 1), pixelsHigh = max(Int((size.height * scale).rounded()), 1)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSImage(size: size) }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        body()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Native pixel scale of `image` (1 for 72-dpi images).
    static func pixelScale(_ image: NSImage) -> CGFloat {
        guard let rep = image.representations.first, rep.size.width > 0, rep.pixelsWide > 0 else { return 2 }
        return max(1, min(CGFloat(rep.pixelsWide) / rep.size.width, 3))
    }

    static func resize(_ image: NSImage, to size: CGSize) -> NSImage {
        let scale = pixelScale(image) * max(image.size.width / max(size.width, 1), 1)
        return render(size: size, scale: min(scale, 3)) {
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func rotate(_ image: NSImage, clockwise: Bool) -> NSImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        return render(size: size, scale: pixelScale(image)) {
            let transform = NSAffineTransform()
            transform.translateX(by: size.width / 2, yBy: size.height / 2)
            transform.rotate(byDegrees: clockwise ? -90 : 90)
            transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2)
            transform.concat()
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func flip(_ image: NSImage, horizontal: Bool) -> NSImage {
        render(size: image.size, scale: pixelScale(image)) {
            let transform = NSAffineTransform()
            if horizontal {
                transform.translateX(by: image.size.width, yBy: 0)
                transform.scaleX(by: -1, yBy: 1)
            } else {
                transform.translateX(by: 0, yBy: image.size.height)
                transform.scaleX(by: 1, yBy: -1)
            }
            transform.concat()
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Crops by fractions (0…0.45) of each edge.
    static func crop(_ image: NSImage, top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) -> NSImage {
        let size = image.size
        let source = CGRect(x: size.width * left, y: size.height * bottom,
                            width: size.width * (1 - left - right), height: size.height * (1 - top - bottom))
        guard source.width > 1, source.height > 1 else { return image }
        return render(size: source.size, scale: pixelScale(image)) {
            image.draw(in: CGRect(origin: .zero, size: source.size), from: source, operation: .copy, fraction: 1)
        }
    }

    /// Crops to a circle or rounded rectangle.
    static func mask(_ image: NSImage, circle: Bool) -> NSImage {
        render(size: image.size, scale: pixelScale(image)) {
            let rect = CGRect(origin: .zero, size: image.size)
            let path = circle
                ? NSBezierPath(ovalIn: rect)
                : NSBezierPath(roundedRect: rect, xRadius: min(rect.width, rect.height) * 0.08, yRadius: min(rect.width, rect.height) * 0.08)
            path.addClip()
            image.draw(in: rect)
        }
    }

    static func addBorder(_ image: NSImage, color: NSColor, width: CGFloat) -> NSImage {
        let size = CGSize(width: image.size.width + width * 2, height: image.size.height + width * 2)
        return render(size: size, scale: pixelScale(image)) {
            color.setFill()
            CGRect(origin: .zero, size: size).fill()
            image.draw(in: CGRect(x: width, y: width, width: image.size.width, height: image.size.height))
        }
    }

    static func addShadow(_ image: NSImage) -> NSImage {
        let inset: CGFloat = 14
        let size = CGSize(width: image.size.width + inset * 2, height: image.size.height + inset * 2)
        return render(size: size, scale: pixelScale(image)) {
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 3, height: -4)
            shadow.shadowBlurRadius = 9
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.set()
            image.draw(in: CGRect(x: inset, y: inset, width: image.size.width, height: image.size.height))
        }
    }

    static func setTransparency(_ image: NSImage, opacity: CGFloat) -> NSImage {
        render(size: image.size, scale: pixelScale(image)) {
            image.draw(in: CGRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: opacity)
        }
    }

    // MARK: Core Image corrections

    private static let context = CIContext()

    private static func ciImage(_ image: NSImage) -> CIImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CIImage(cgImage: cg)
    }

    private static func nsImage(_ output: CIImage?, like original: NSImage) -> NSImage? {
        guard let output, let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: original.size)
    }

    /// Brightness (-0.5…0.5), contrast (0.5…1.5), saturation (0…2), sharpness (0…2).
    static func adjust(_ image: NSImage, brightness: Double, contrast: Double, saturation: Double, sharpness: Double = 0) -> NSImage? {
        guard let input = ciImage(image) else { return nil }
        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.brightness = Float(brightness)
        controls.contrast = Float(contrast)
        controls.saturation = Float(saturation)
        var output = controls.outputImage
        if sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = output
            sharpen.sharpness = Float(sharpness)
            output = sharpen.outputImage
        }
        return nsImage(output, like: image)
    }

    enum ArtisticEffect: String, CaseIterable, Identifiable {
        case grayscale, sepia, blur, posterize, comic, pixelate, vignette
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
    }

    static func apply(_ effect: ArtisticEffect, to image: NSImage) -> NSImage? {
        guard let input = ciImage(image) else { return nil }
        let output: CIImage?
        switch effect {
        case .grayscale:
            let filter = CIFilter.photoEffectMono(); filter.inputImage = input; output = filter.outputImage
        case .sepia:
            let filter = CIFilter.sepiaTone(); filter.inputImage = input; filter.intensity = 0.85; output = filter.outputImage
        case .blur:
            let filter = CIFilter.gaussianBlur(); filter.inputImage = input.clampedToExtent(); filter.radius = 6
            output = filter.outputImage?.cropped(to: input.extent)
        case .posterize:
            let filter = CIFilter.colorPosterize(); filter.inputImage = input; filter.levels = 5; output = filter.outputImage
        case .comic:
            let filter = CIFilter.comicEffect(); filter.inputImage = input; output = filter.outputImage
        case .pixelate:
            let filter = CIFilter.pixellate(); filter.inputImage = input; filter.scale = Float(max(input.extent.width / 60, 4))
            filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)
            output = filter.outputImage?.cropped(to: input.extent)
        case .vignette:
            let filter = CIFilter.vignette(); filter.inputImage = input; filter.intensity = 1.2; filter.radius = 2; output = filter.outputImage
        }
        return nsImage(output, like: image)
    }

    /// Lifts the foreground subject off its background (Vision).
    static func removeBackground(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
            return nsImage(CIImage(cvPixelBuffer: buffer), like: image)
        } catch {
            return nil
        }
    }

    // MARK: Compression

    static func jpegData(_ image: NSImage, quality: CGFloat) -> Data {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? Data()
    }

    /// Downsamples to at most `ppi` pixels per inch at the displayed size.
    static func compress(_ image: NSImage, ppi: CGFloat) -> NSImage {
        let scale = ppi / 72
        guard pixelScale(image) > scale else { return image }
        return render(size: image.size, scale: scale) {
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
