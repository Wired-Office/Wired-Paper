import SwiftUI

/// Size, crop, corrections, effects, border/shadow, transparency, compression
/// and alt text for a picture, with a live preview.
struct PictureFormatSheet: View {
    let original: NSImage
    @State var altText: String
    let maxWidth: CGFloat
    /// (edited image or nil when unchanged, alt text, JPEG quality when compressing)
    let onApply: (NSImage?, String, CGFloat?) -> Void
    let onCancel: () -> Void

    @State private var scale: Double = 100
    @State private var cropTop: Double = 0
    @State private var cropBottom: Double = 0
    @State private var cropLeft: Double = 0
    @State private var cropRight: Double = 0
    @State private var cropShape = CropShape.none
    @State private var brightness: Double = 0
    @State private var contrast: Double = 1
    @State private var saturation: Double = 1
    @State private var sharpness: Double = 0
    @State private var effect: ImageProcessing.ArtisticEffect?
    @State private var opacity: Double = 1
    @State private var border = false
    @State private var borderColor = Color(nsColor: NSColor(hex: "#13787F")!)
    @State private var borderWidth: Double = 3
    @State private var shadow = false
    @State private var compress = CompressionLevel.none

    enum CropShape: String, CaseIterable, Identifiable {
        case none, rounded, circle
        var id: String { rawValue }
    }

    enum CompressionLevel: String, CaseIterable, Identifiable {
        case none = "Don't compress", print = "Print (220 ppi)", screen = "Screen (150 ppi)", email = "E-mail (96 ppi)"
        var id: String { rawValue }
        var ppi: CGFloat? {
            switch self {
            case .none: nil
            case .print: 220
            case .screen: 150
            case .email: 96
            }
        }
    }

    init(original: NSImage, altText: String, maxWidth: CGFloat, onApply: @escaping (NSImage?, String, CGFloat?) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        _altText = State(initialValue: altText)
        self.maxWidth = maxWidth
        self.onApply = onApply
        self.onCancel = onCancel
    }

    private var isUnchanged: Bool {
        scale == 100 && cropTop == 0 && cropBottom == 0 && cropLeft == 0 && cropRight == 0 && cropShape == .none && brightness == 0
            && contrast == 1 && saturation == 1 && sharpness == 0 && effect == nil && opacity == 1 && !border && !shadow && compress == .none
    }

    private func processed() -> NSImage {
        var image = original
        if cropTop + cropBottom + cropLeft + cropRight > 0 {
            image = ImageProcessing.crop(image, top: cropTop / 100, left: cropLeft / 100, bottom: cropBottom / 100, right: cropRight / 100)
        }
        if brightness != 0 || contrast != 1 || saturation != 1 || sharpness != 0 {
            image = ImageProcessing.adjust(image, brightness: brightness, contrast: contrast, saturation: saturation, sharpness: sharpness) ?? image
        }
        if let effect { image = ImageProcessing.apply(effect, to: image) ?? image }
        if scale != 100 {
            image = ImageProcessing.resize(image, to: CGSize(width: image.size.width * scale / 100, height: image.size.height * scale / 100))
        }
        if cropShape != .none { image = ImageProcessing.mask(image, circle: cropShape == .circle) }
        if opacity < 1 { image = ImageProcessing.setTransparency(image, opacity: opacity) }
        if border { image = ImageProcessing.addBorder(image, color: NSColor(borderColor), width: borderWidth) }
        if shadow { image = ImageProcessing.addShadow(image) }
        if let ppi = compress.ppi { image = ImageProcessing.compress(image, ppi: ppi) }
        return image
    }

    var body: some View {
        SheetScaffold(title: "Format Picture", primaryTitle: "Apply", width: 760, onPrimary: {
            onApply(isUnchanged ? nil : processed(), altText, compress == .none ? nil : 0.8)
        }, onCancel: onCancel) {
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    Form {
                        Section("Size") {
                            HStack {
                                Slider(value: $scale, in: 10...200, step: 5)
                                Text("\(Int(scale))%").monospacedDigit().frame(width: 44)
                            }
                            Text("\(Int(original.size.width * scale / 100)) × \(Int(original.size.height * scale / 100)) pt (text column is \(Int(maxWidth)) pt wide)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Crop") {
                            percentSlider("Top", $cropTop)
                            percentSlider("Bottom", $cropBottom)
                            percentSlider("Left", $cropLeft)
                            percentSlider("Right", $cropRight)
                            Picker("Shape", selection: $cropShape) {
                                ForEach(CropShape.allCases) { Text($0.rawValue.capitalized).tag($0) }
                            }
                        }
                        Section("Corrections") {
                            LabeledContent("Brightness") { Slider(value: $brightness, in: -0.5...0.5) }
                            LabeledContent("Contrast") { Slider(value: $contrast, in: 0.5...1.5) }
                            LabeledContent("Saturation") { Slider(value: $saturation, in: 0...2) }
                            LabeledContent("Sharpness") { Slider(value: $sharpness, in: 0...2) }
                            Picker("Effect", selection: $effect) {
                                Text("None").tag(ImageProcessing.ArtisticEffect?.none)
                                ForEach(ImageProcessing.ArtisticEffect.allCases) { Text($0.displayName).tag(Optional($0)) }
                            }
                            LabeledContent("Transparency") { Slider(value: Binding(get: { 1 - opacity }, set: { opacity = 1 - $0 }), in: 0...0.9) }
                            Button("Reset Corrections") {
                                brightness = 0; contrast = 1; saturation = 1; sharpness = 0; effect = nil; opacity = 1
                            }
                        }
                        Section("Border & Shadow") {
                            Toggle("Border", isOn: $border)
                            if border {
                                ColorPicker("Color", selection: $borderColor, supportsOpacity: false)
                                Stepper("Width \(Int(borderWidth)) pt", value: $borderWidth, in: 1...20)
                            }
                            Toggle("Drop shadow", isOn: $shadow)
                        }
                        Section("Compression") {
                            Picker("Resolution", selection: $compress) {
                                ForEach(CompressionLevel.allCases) { Text($0.rawValue).tag($0) }
                            }
                        }
                        Section("Alt Text") {
                            TextField("Describe this picture", text: $altText, axis: .vertical).lineLimit(2...4)
                        }
                    }
                    .formStyle(.grouped)
                }
                .frame(width: 360, height: 460)
                VStack {
                    let preview = processed()
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: min(preview.size.width, 340), maxHeight: min(preview.size.height, 440))
                }
                .frame(width: 350, height: 460)
                .background(Color(white: 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private func percentSlider(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: 0...45, step: 1)
                Text("\(Int(value.wrappedValue))%").monospacedDigit().frame(width: 36)
            }
        }
    }
}
