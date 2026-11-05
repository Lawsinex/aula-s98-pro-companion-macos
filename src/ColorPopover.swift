import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ColorPopoverButton: View {
    let label: String
    @Binding var color: RGB8
    var swatches: [RGB8] = []
    var onSaveSwatch: ((RGB8) -> Void)?
    var onRemoveSwatch: ((RGB8) -> Void)?
    var onClearSwatches: (() -> Void)?
    var enabled = true
    var onPreview: () -> Void = {}
    var onCommit: () -> Void = {}
    var calibration: Binding<ColorCalibration>?
    var calibrationPreviewEnabled: Binding<Bool>?
    var onCalibrationPreview: (RGB8) -> Void = { _ in }
    var onCalibrationCommit: () -> Void = {}

    @State private var isPresented = false

    /// Swatches show how the keys will really look, so they agree with the keyboard
    /// preview instead of contradicting it. The hex stays the value being sent.
    private var displayedColor: RGB8 {
        guard calibrationPreviewEnabled?.wrappedValue == true,
              let calibration = calibration?.wrappedValue,
              !calibration.samples.isEmpty else { return color }
        return calibration.predictedAppearance(of: color)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(displayedColor))
                    .frame(width: 28, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.primary.opacity(0.22), lineWidth: 1))
                Text(label)
                Spacer(minLength: 8)
                Text(color.hex)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.065)))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityValue(color.hex)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ColorEditor(color: $color, swatches: swatches,
                        onSaveSwatch: onSaveSwatch, onRemoveSwatch: onRemoveSwatch,
                        onClearSwatches: onClearSwatches,
                        onPreview: onPreview, onCommit: onCommit,
                        calibration: calibration,
                        calibrationPreviewEnabled: calibrationPreviewEnabled,
                        onCalibrationPreview: onCalibrationPreview,
                        onCalibrationCommit: onCalibrationCommit)
        }
    }
}

struct ColorEditor: View {
    @Binding var color: RGB8
    let swatches: [RGB8]
    let onSaveSwatch: ((RGB8) -> Void)?
    let onRemoveSwatch: ((RGB8) -> Void)?
    let onClearSwatches: (() -> Void)?
    let onPreview: () -> Void
    let onCommit: () -> Void
    let calibration: Binding<ColorCalibration>?
    let calibrationPreviewEnabled: Binding<Bool>?
    let onCalibrationPreview: (RGB8) -> Void
    let onCalibrationCommit: () -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    @State private var hexText: String
    @State private var hexIsInvalid = false
    @State private var hasUncommittedColorChange = false
    @State private var calibrationMode: Bool

    init(color: Binding<RGB8>, swatches: [RGB8],
         onSaveSwatch: ((RGB8) -> Void)? = nil,
         onRemoveSwatch: ((RGB8) -> Void)? = nil,
         onClearSwatches: (() -> Void)? = nil,
         onPreview: @escaping () -> Void, onCommit: @escaping () -> Void,
         calibration: Binding<ColorCalibration>?,
         calibrationPreviewEnabled: Binding<Bool>? = nil,
         onCalibrationPreview: @escaping (RGB8) -> Void,
         onCalibrationCommit: @escaping () -> Void,
         startCalibrating: Bool = false) {
        _calibrationMode = State(initialValue: startCalibrating)
        self.calibrationPreviewEnabled = calibrationPreviewEnabled
        _color = color
        self.swatches = swatches
        self.onSaveSwatch = onSaveSwatch
        self.onRemoveSwatch = onRemoveSwatch
        self.onClearSwatches = onClearSwatches
        self.onPreview = onPreview
        self.onCommit = onCommit
        self.calibration = calibration
        self.onCalibrationPreview = onCalibrationPreview
        self.onCalibrationCommit = onCalibrationCommit
        let components = Self.hsv(color.wrappedValue)
        _hue = State(initialValue: components.h)
        _saturation = State(initialValue: components.s)
        _brightness = State(initialValue: components.v)
        _hexText = State(initialValue: color.wrappedValue.hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Colour")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if calibration != nil {
                    Button(calibrationMode ? "Done" : "Calibrate") {
                        if calibrationMode { onCalibrationCommit() }
                        calibrationMode.toggle()
                    }
                    .controlSize(.small)
                }
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(displayed(color)))
                    .frame(width: 42, height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1))
                    .accessibilityHidden(true)
            }

            if calibrationMode, let calibration {
                DualWheelCalibrationView(
                    logicalColor: color,
                    logicalHue: hue,
                    logicalSaturation: saturation,
                    calibration: calibration,
                    onRawPreview: onCalibrationPreview,
                    onCommit: onCalibrationCommit)
            } else {
                CircularColorWheel(hue: $hue, saturation: $saturation,
                                   calibration: wheelCalibration) { editing in
                    publish(commit: !editing)
                }
                .frame(width: 244, height: 244)
                .frame(maxWidth: .infinity)

                if let enabled = calibrationPreviewEnabled,
                   let calibration, !calibration.wrappedValue.samples.isEmpty {
                    Toggle(isOn: enabled) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Show the keyboard's real colours")
                                .font(.system(size: 11))
                            Text(enabled.wrappedValue
                                 ? "Wheel corrected from \(calibration.wrappedValue.samples.count) data point(s)"
                                 : "Showing true colours — use this while adding data points")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                VStack(spacing: 8) {
                    HStack {
                        Text("Hue \(Int(hue * 360))°")
                        Spacer()
                        Text("Saturation \(Int(saturation * 100))%")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    componentSlider("Colour brightness", value: $brightness)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Saved colours")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let onRemoveSwatch, alreadySaved {
                            Button("Remove") { onRemoveSwatch(color) }
                                .controlSize(.mini)
                                .help("Remove \(color.hex) from your colours")
                        }
                        if let onClearSwatches, !swatches.isEmpty {
                            Button("Clear", action: onClearSwatches)
                                .controlSize(.mini)
                        }
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7),
                                             count: 12), spacing: 7) {
                        ForEach(Array(swatches.prefix(12).enumerated()), id: \.offset) { _, swatch in
                            Button {
                                set(swatch, commit: true)
                            } label: {
                                Circle().fill(Color(displayed(swatch)))
                                    .frame(height: 20)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(swatch.hex)
                            .accessibilityLabel("Use \(swatch.hex)")
                            .contextMenu {
                                if let onRemoveSwatch {
                                    Button("Remove \(swatch.hex)", role: .destructive) {
                                        onRemoveSwatch(swatch)
                                    }
                                }
                            }
                        }

                        // The add control is itself swatch-shaped, so the row reads as
                        // "these colours, and room for one more".
                        if let onSaveSwatch, swatches.count < 12 {
                            Button {
                                onSaveSwatch(color)
                            } label: {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(alreadySaved ? 0.15 : 0.45),
                                                  style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                                    .frame(height: 20)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.primary.opacity(alreadySaved ? 0.2 : 0.6))
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(alreadySaved)
                            .help(alreadySaved ? "\(color.hex) is already saved" : "Save \(color.hex)")
                            .accessibilityLabel(alreadySaved
                                                ? "Colour already saved"
                                                : "Save \(color.hex) to your colours")
                        }
                    }

                    if swatches.isEmpty {
                        Text("Pick a colour, then press + to keep it.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text("Hex")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("#RRGGBB", text: $hexText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(applyHex)
                    if hexIsInvalid {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Enter a six-digit hex colour")
                    }
                    Button("Apply", action: applyHex)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .onDisappear {
            if hasUncommittedColorChange {
                hasUncommittedColorChange = false
                onCommit()
            }
            if calibrationMode { onCalibrationCommit() }
        }
    }

    private func componentSlider(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).frame(width: 96, alignment: .leading)
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { next in value.wrappedValue = next; publish(commit: false) }),
                in: 0...1,
                onEditingChanged: { editing in if !editing { publish(commit: true) } })
                .accessibilityLabel(label)
            Text("\(Int(value.wrappedValue * 100))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    private var alreadySaved: Bool { swatches.contains(color) }

    /// How a colour will actually appear on the keys, when the correction is switched on.
    private func displayed(_ value: RGB8) -> RGB8 {
        guard let calibration = wheelCalibration, !calibration.samples.isEmpty else { return value }
        return calibration.predictedAppearance(of: value)
    }

    /// Only tint the wheel when the user has asked to see the keyboard's real colours.
    private var wheelCalibration: ColorCalibration? {
        guard calibrationPreviewEnabled?.wrappedValue == true else { return nil }
        return calibration?.wrappedValue
    }

    private func publish(commit: Bool) {
        let next = Self.rgb(h: hue, s: saturation, v: brightness)
        color = next
        hexText = next.hex
        hexIsInvalid = false
        hasUncommittedColorChange = !commit
        commit ? onCommit() : onPreview()
    }

    private func set(_ next: RGB8, commit: Bool) {
        let components = Self.hsv(next)
        hue = components.h; saturation = components.s; brightness = components.v
        color = next; hexText = next.hex; hexIsInvalid = false
        hasUncommittedColorChange = !commit
        commit ? onCommit() : onPreview()
    }

    private func applyHex() {
        guard let next = RGB8(hex: hexText) else { hexIsInvalid = true; return }
        set(next, commit: true)
    }

    private static func hsv(_ rgb: RGB8) -> (h: Double, s: Double, v: Double) {
        HSVColorMath.hsv(rgb)
    }

    private static func rgb(h: Double, s: Double, v: Double) -> RGB8 {
        HSVColorMath.rgb(h: h, s: s, v: v)
    }
}

enum HSVColorMath {
    static func hsv(_ color: RGB8) -> (h: Double, s: Double, v: Double) {
        let r = Double(color.r) / 255, g = Double(color.g) / 255, b = Double(color.b) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b), delta = maximum - minimum
        guard delta > 0 else { return (0, 0, maximum) }
        let base: Double
        if maximum == r { base = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if maximum == g { base = (b - r) / delta + 2 }
        else { base = (r - g) / delta + 4 }
        var hue = base / 6
        hue = hue - floor(hue)
        return (hue, maximum == 0 ? 0 : delta / maximum, maximum)
    }

    static func rgb(h: Double, s: Double, v: Double) -> RGB8 {
        let hue = h - floor(h)
        let saturation = max(0, min(1, s))
        let value = max(0, min(1, v))
        let c = value * saturation
        let sector = hue * 6
        let x = c * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let values: (Double, Double, Double)
        switch Int(floor(sector)) % 6 {
        case 0: values = (c, x, 0)
        case 1: values = (x, c, 0)
        case 2: values = (0, c, x)
        case 3: values = (0, x, c)
        case 4: values = (x, 0, c)
        default: values = (c, 0, x)
        }
        let m = value - c
        func byte(_ component: Double) -> UInt8 {
            UInt8(max(0, min(255, (component + m) * 255)).rounded())
        }
        return RGB8(r: byte(values.0), g: byte(values.1), b: byte(values.2))
    }
}

enum ColorWheelMath {
    static func components(at point: CGPoint, side: CGFloat,
                           currentHue: Double) -> (hue: Double, saturation: Double) {
        let radius = max(0.5, side / 2)
        let dx = point.x - radius
        let dy = point.y - radius
        let distance = hypot(dx, dy)
        guard distance >= 0.5 else { return (currentHue, 0) }
        var hue = -atan2(dy, dx) / (2 * Double.pi)
        hue = hue - floor(hue)
        return (hue, min(1, distance / radius))
    }

    static func point(hue: Double, saturation: Double, side: CGFloat) -> CGPoint {
        let radius = side / 2
        let angle = 2 * Double.pi * (hue - floor(hue))
        let amount = max(0, min(1, saturation))
        return CGPoint(x: radius + cos(angle) * amount * radius,
                       y: radius - sin(angle) * amount * radius)
    }
}

enum ColorWheelArtwork {
    static let image: NSImage = {
        let pixelDiameter: CGFloat = 512
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return NSImage(size: NSSize(width: 256, height: 256))
        }
        let filter = CIFilter.hueSaturationValueGradient()
        filter.value = 1
        filter.radius = Float(pixelDiameter / 2)
        filter.softness = 1
        filter.dither = 1
        filter.colorSpace = colorSpace
        let bounds = CGRect(x: 0, y: 0, width: pixelDiameter, height: pixelDiameter)
        let context = CIContext(options: [.workingColorSpace: colorSpace,
                                          .outputColorSpace: colorSpace])
        guard let output = filter.outputImage?.cropped(to: bounds),
              let cgImage = context.createCGImage(output, from: bounds,
                                                  format: .RGBA8,
                                                  colorSpace: colorSpace) else {
            return NSImage(size: NSSize(width: 256, height: 256))
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 256, height: 256))
    }()

    // Keyed by the whole calibration value, and every add/remove makes a new key, so an
    // unbounded dictionary would accumulate ~1MB bitmaps for the life of the process.
    private static var calibratedCache: [ColorCalibration: NSImage] = [:]
    private static var calibratedCacheOrder: [ColorCalibration] = []
    private static let calibratedCacheLimit = 3

    /// The wheel repainted the way this keyboard actually renders colour, so the
    /// swatch under the cursor is what the keys will really show. Cached, because
    /// remapping a quarter of a million pixels on every drag would be absurd.
    static func image(for calibration: ColorCalibration?) -> NSImage {
        guard let calibration, !calibration.samples.isEmpty else { return image }
        if let cached = calibratedCache[calibration] { return cached }
        guard let base = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        let width = base.width, height = base.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let remapped: NSImage? = pixels.withUnsafeMutableBytes { raw -> NSImage? in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = raw.bindMemory(to: UInt8.self)
            var lut: [RGB8: RGB8] = [:]
            for index in stride(from: 0, to: bytes.count, by: 4) {
                guard bytes[index + 3] == 255 else { continue }   // skip the soft edge
                let source = RGB8(r: bytes[index], g: bytes[index + 1], b: bytes[index + 2])
                let mapped: RGB8
                if let hit = lut[source] { mapped = hit }
                else { mapped = calibration.transform(source); lut[source] = mapped }
                bytes[index] = mapped.r; bytes[index + 1] = mapped.g; bytes[index + 2] = mapped.b
            }
            guard let output = context.makeImage() else { return nil }
            return NSImage(cgImage: output, size: NSSize(width: 256, height: 256))
        }
        guard let result = remapped else { return image }
        calibratedCache[calibration] = result
        calibratedCacheOrder.append(calibration)
        while calibratedCacheOrder.count > calibratedCacheLimit {
            calibratedCache.removeValue(forKey: calibratedCacheOrder.removeFirst())
        }
        return result
    }
}

struct CircularColorWheel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    var calibration: ColorCalibration?
    let onEditingChanged: (Bool) -> Void
    @StateObject private var discreteCommitter = DiscreteColourCommitter()

    /// The knob sits on the wheel, so it has to be tinted the same way the wheel is.
    private var knobColor: RGB8 {
        let raw = HSVColorMath.rgb(h: hue, s: saturation, v: 1)
        guard let calibration, !calibration.samples.isEmpty else { return raw }
        return calibration.transform(raw)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = max(1, min(proxy.size.width, proxy.size.height))
            let marker = ColorWheelMath.point(hue: hue, saturation: saturation, side: side)
            ZStack(alignment: .topLeading) {
                Image(nsImage: ColorWheelArtwork.image(for: calibration))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))

                Circle()
                    .fill(Color(knobColor))
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 3).padding(-1))
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .frame(width: 18, height: 18)
                    .offset(x: marker.x - 9, y: marker.y - 9)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    discreteCommitter.cancel()
                    let next = ColorWheelMath.components(at: drag.location, side: side,
                                                         currentHue: hue)
                    hue = next.hue; saturation = next.saturation
                    onEditingChanged(true)
                }
                .onEnded { _ in onEditingChanged(false) })
            .focusable()
            .onMoveCommand { direction in
                var point = marker
                let step = max(3, side / 40)
                switch direction {
                case .left: point.x -= step
                case .right: point.x += step
                case .up: point.y -= step
                case .down: point.y += step
                default: return
                }
                let next = ColorWheelMath.components(at: point, side: side, currentHue: hue)
                hue = next.hue; saturation = next.saturation
                discreteCommitter.update(onEditingChanged)
            }
            .onDisappear { discreteCommitter.cancel() }
            .accessibilityRepresentation {
                VStack {
                    Slider(value: Binding(
                        get: { hue },
                        set: { hue = $0; discreteCommitter.update(onEditingChanged) }), in: 0...1)
                        .accessibilityLabel("Hue")
                        .accessibilityValue("\(Int(hue * 360)) degrees")
                    Slider(value: Binding(
                        get: { saturation },
                        set: { saturation = $0; discreteCommitter.update(onEditingChanged) }), in: 0...1)
                        .accessibilityLabel("Saturation")
                        .accessibilityValue("\(Int(saturation * 100)) percent")
                }
            }
        }
    }
}

private struct DualWheelCalibrationView: View {
    let logicalColor: RGB8
    let logicalHue: Double
    let logicalSaturation: Double
    @Binding var calibration: ColorCalibration
    let onRawPreview: (RGB8) -> Void
    let onCommit: () -> Void

    @State private var targetHue: Double
    @State private var targetSaturation: Double
    @State private var targetValue: Double
    @State private var seenHue: Double
    @State private var seenSaturation: Double
    @State private var seenValue: Double
    @State private var notice = ""

    init(logicalColor: RGB8, logicalHue: Double, logicalSaturation: Double,
         calibration: Binding<ColorCalibration>,
         onRawPreview: @escaping (RGB8) -> Void,
         onCommit: @escaping () -> Void) {
        self.logicalColor = logicalColor
        self.logicalHue = logicalHue
        self.logicalSaturation = logicalSaturation
        _calibration = calibration
        self.onRawPreview = onRawPreview
        self.onCommit = onCommit
        let components = HSVColorMath.hsv(logicalColor)
        _targetHue = State(initialValue: components.h)
        _targetSaturation = State(initialValue: components.s)
        _targetValue = State(initialValue: components.v)
        _seenHue = State(initialValue: components.h)
        _seenSaturation = State(initialValue: components.s)
        _seenValue = State(initialValue: components.v)
    }

    private var targetColor: RGB8 {
        HSVColorMath.rgb(h: targetHue, s: targetSaturation, v: targetValue)
    }
    private var seenColor: RGB8 {
        HSVColorMath.rgb(h: seenHue, s: seenSaturation, v: seenValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Teach the wheel what your keyboard really does")
                    .font(.system(size: 12, weight: .semibold))
                Text("Pick a target, show it on the keyboard, then set the right wheel to the colour you actually saw. Each pair you add corrects the main colour wheel.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                wheel(title: "Target", subtitle: "what you asked for",
                      hue: $targetHue, saturation: $targetSaturation,
                      value: $targetValue, swatch: targetColor) {
                    onRawPreview(targetColor)
                    notice = "Showing target on the keyboard"
                }
                wheel(title: "What actually happened", subtitle: "what you saw",
                      hue: $seenHue, saturation: $seenSaturation,
                      value: $seenValue, swatch: seenColor, onChange: nil)
            }

            HStack(spacing: 7) {
                Button("Show on keyboard") {
                    onRawPreview(targetColor)
                    notice = "Showing target — now match the right wheel to it"
                }
                .fixedSize()
                Button("Add data point") {
                    guard calibration.addSample(target: targetColor, observed: seenColor) else {
                        notice = "Limit reached — delete a data point first"
                        return
                    }
                    notice = "Added — \(calibration.samples.count) point(s)"
                    onCommit()
                }
                .disabled(calibration.samples.count >= ColorCalibration.maximumSamples)
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }

            Text(notice.isEmpty ? correctionSummary : notice)
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if calibration.samples.isEmpty {
                Text("No data points yet — the wheel is uncorrected.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Data points").font(.system(size: 10, weight: .semibold))
                        Spacer()
                        Text(correctionSummary)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Button("Clear all") {
                            calibration.samples.removeAll()
                            calibration.recomputeFromSamples()
                            notice = "Cleared every data point"
                            onCommit()
                        }
                        .controlSize(.mini)
                    }
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(calibration.samples) { sample in
                                sampleRow(sample)
                            }
                        }
                    }
                    .frame(maxHeight: 118)
                }
            }
        }
    }

    @ViewBuilder
    private func wheel(title: String, subtitle: String,
                       hue: Binding<Double>, saturation: Binding<Double>,
                       value: Binding<Double>, swatch: RGB8,
                       onChange: (() -> Void)?) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 10, weight: .medium))
            Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            CircularColorWheel(hue: hue, saturation: saturation) { editing in
                if !editing { onChange?() }
            }
            .frame(width: 128, height: 128)
            Slider(value: value, in: 0...1) { editing in if !editing { onChange?() } }
                .controlSize(.mini)
                .accessibilityLabel("\(title) brightness")
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(swatch))
                .frame(width: 128, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1))
                .accessibilityLabel("\(title) preview, \(swatch.hex)")
            Text(swatch.hex)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func sampleRow(_ sample: CalibrationSample) -> some View {
        HStack(spacing: 6) {
            swatchChip(sample.target)
            Image(systemName: "arrow.right")
                .font(.system(size: 8)).foregroundStyle(.secondary)
            swatchChip(sample.observed)
            Text("\(sample.target.hex) → \(sample.observed.hex)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                calibration.removeSample(id: sample.id)
                notice = "Removed a data point"
                onCommit()
            } label: {
                Image(systemName: "trash").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .help("Delete this data point")
            .accessibilityLabel("Delete data point \(sample.target.hex) to \(sample.observed.hex)")
        }
        .padding(.vertical, 1)
    }

    private func swatchChip(_ color: RGB8) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(color))
            .frame(width: 18, height: 12)
            .overlay(RoundedRectangle(cornerRadius: 3)
                .stroke(Color.primary.opacity(0.2), lineWidth: 0.5))
    }

    private var correctionSummary: String {
        if calibration.samples.isEmpty { return "Identity" }
        let hue = Int(calibration.hueShiftDegrees.rounded())
        let sat = String(format: "%.2f", calibration.saturationScale)
        let val = String(format: "%.2f", calibration.valueScale)
        return "\(calibration.samples.count) pts · hue \(hue > 0 ? "+" : "")\(hue)° · sat ×\(sat) · bright ×\(val)"
    }
}

// MARK: - Snapshot target

/// A popover is never laid out by `ImageRenderer`, so the colour editor — and the
/// two-wheel calibrator inside it — would be invisible to the render smokes.
/// This wrapper renders the same editor offscreen so both can be reviewed.
struct ColorEditorSnapshot: View {
    let startCalibrating: Bool
    @State private var color = RGB8(r: 0, g: 210, b: 255)
    @State private var calibration = ColorCalibration.identity
    @State private var saved: [RGB8] = [RGB8(r: 255, g: 0, b: 0), RGB8(r: 255, g: 160, b: 0),
                                        RGB8(r: 0, g: 255, b: 0), RGB8(r: 0, g: 210, b: 255),
                                        RGB8(r: 0, g: 80, b: 255)]
    @State private var previewEnabled = true

    var body: some View {
        ColorEditor(color: $color,
                    swatches: saved,
                    onSaveSwatch: { value in if !saved.contains(value) { saved.append(value) } },
                    onRemoveSwatch: { value in saved.removeAll { $0 == value } },
                    onClearSwatches: { saved.removeAll() },
                    onPreview: {}, onCommit: {},
                    calibration: $calibration,
                    calibrationPreviewEnabled: $previewEnabled,
                    onCalibrationPreview: { _ in }, onCalibrationCommit: {},
                    startCalibrating: startCalibrating)
            .padding(18)
            .frame(width: 400)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
