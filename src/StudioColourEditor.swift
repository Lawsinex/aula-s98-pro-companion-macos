import SwiftUI
import AppKit

/// An inline version of the menu panel's colour workflow. RGB remains canonical;
/// calibration affects only the displayed artwork, just as it does in the popover.
struct StudioColourEditor: View {
    @Binding var color: RGB8
    let swatches: [RGB8]
    @Binding var calibration: ColorCalibration
    @Binding var calibrationPreviewEnabled: Bool
    let enabled: Bool
    let onPreview: () -> Void
    let onCommit: () -> Void
    let onSave: (RGB8) -> Void
    let onRemove: (RGB8) -> Void
    let onRawPreview: (RGB8) -> Void
    let onCalibrationCommit: () -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var value: Double
    @State private var hex: String
    @State private var invalidHex = false
    @State private var pendingCommit = false
    @State private var calibrating = false

    init(color: Binding<RGB8>, swatches: [RGB8], calibration: Binding<ColorCalibration>,
         calibrationPreviewEnabled: Binding<Bool>, enabled: Bool,
         onPreview: @escaping () -> Void, onCommit: @escaping () -> Void,
         onSave: @escaping (RGB8) -> Void, onRemove: @escaping (RGB8) -> Void,
         onRawPreview: @escaping (RGB8) -> Void, onCalibrationCommit: @escaping () -> Void) {
        _color = color; self.swatches = swatches; _calibration = calibration
        _calibrationPreviewEnabled = calibrationPreviewEnabled; self.enabled = enabled
        self.onPreview = onPreview; self.onCommit = onCommit; self.onSave = onSave
        self.onRemove = onRemove; self.onRawPreview = onRawPreview
        self.onCalibrationCommit = onCalibrationCommit
        let hsv = HSVColorMath.hsv(color.wrappedValue)
        _hue = State(initialValue: hsv.h); _saturation = State(initialValue: hsv.s)
        _value = State(initialValue: hsv.v); _hex = State(initialValue: color.wrappedValue.hex)
    }

    private var wheelCalibration: ColorCalibration? {
        calibrationPreviewEnabled ? calibration : nil
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                wheel
                fields.frame(minWidth: 200, maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 20) {
                wheel
                fields
            }
        }
        .onChange(of: color) { next in sync(next) }
        .onDisappear {
            if pendingCommit { pendingCommit = false; onCommit() }
        }
        .popover(isPresented: $calibrating, arrowEdge: .bottom) {
            ColorEditor(color: $color, swatches: swatches,
                        onSaveSwatch: onSave, onRemoveSwatch: onRemove,
                        onPreview: onPreview, onCommit: onCommit,
                        calibration: $calibration,
                        calibrationPreviewEnabled: $calibrationPreviewEnabled,
                        onCalibrationPreview: onRawPreview,
                        onCalibrationCommit: onCalibrationCommit,
                        startCalibrating: true)
                .foregroundStyle(Ink.text).tint(Ink.accent)
        }
    }

    private var wheel: some View {
        CircularColorWheel(hue: $hue, saturation: $saturation,
                           calibration: wheelCalibration) { editing in publish(commit: !editing) }
            .frame(width: 232, height: 232)
            .allowsHitTesting(enabled).disabled(!enabled)
            .accessibilityHint(enabled ? "Choose a colour" : "This effect generates its own colours")
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved colours").font(Ink.body()).foregroundStyle(Ink.textSecond)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 26, maximum: 30), spacing: 10)], spacing: 10) {
                    Button { onSave(color) } label: {
                        Image(systemName: "plus").font(.system(size: 14))
                            .foregroundStyle(Ink.textSecond).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Ink.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(swatches.contains(color) || swatches.count >= 12)
                    .accessibilityLabel("Save current colour")
                    ForEach(swatches, id: \.self) { swatch in
                        Button { set(swatch) } label: {
                            Circle().fill(Color(displayed(swatch)))
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                                .overlay(Circle().strokeBorder(Ink.accent, lineWidth: 1.5)
                                    .padding(-3).opacity(swatch == color ? 1 : 0))
                        }
                        .buttonStyle(.plain).help(swatch.hex)
                        .accessibilityLabel("Use \(swatch.hex)")
                        .accessibilityAddTraits(swatch == color ? [.isButton, .isSelected] : .isButton)
                        .contextMenu {
                            Button("Remove saved colour", role: .destructive) { onRemove(swatch) }
                        }
                    }
                }
                .disabled(!enabled)
                if swatches.isEmpty {
                    Text("Press + to keep a colour.").font(Ink.caption()).foregroundStyle(Ink.textSecond)
                }
            }

            HStack(spacing: 10) {
                Text("HEX").font(Ink.caption()).foregroundStyle(Ink.textSecond)
                TextField("#RRGGBB", text: $hex).font(Ink.mono(12))
                    .textFieldStyle(.plain).padding(.horizontal, 10).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Ink.surface))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(invalidHex ? Ink.bad : Ink.stroke, lineWidth: 1))
                    .onSubmit(applyHex).accessibilityLabel("Hex colour")
                Button(action: applyHex) { Image(systemName: "return") }
                    .buttonStyle(.plain).accessibilityLabel("Apply hex colour")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(color.hex, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).accessibilityLabel("Copy hex colour")
            }
            .disabled(!enabled)
            if invalidHex {
                Text("Enter six hex digits, for example #FFC799.")
                    .font(Ink.caption()).foregroundStyle(Ink.bad)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Colour brightness").font(Ink.body()).foregroundStyle(Ink.textSecond)
                HStack(spacing: 8) {
                    Slider(value: Binding(get: { value }, set: { value = $0; publish(commit: false) }), in: 0...1) {
                        editing in if !editing { publish(commit: true) }
                    }
                    .tint(Ink.accent).accessibilityLabel("Colour brightness")
                    Text("\(Int(value * 100))%")
                        .font(Ink.mono()).foregroundStyle(Ink.textSecond).frame(width: 38, alignment: .trailing)
                }
            }.disabled(!enabled)

            Button { calibrating = true } label: {
                Label("Calibrate colour…", systemImage: "target")
                    .font(Ink.body()).foregroundStyle(Ink.accent)
            }.buttonStyle(.plain)

            if !calibration.samples.isEmpty {
                Toggle("Show calibrated colours", isOn: $calibrationPreviewEnabled)
                    .font(Ink.caption()).toggleStyle(.switch).controlSize(.mini)
            }
            if !enabled {
                Text("This effect generates its own colours.")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
            }
        }
    }

    private func displayed(_ rgb: RGB8) -> RGB8 {
        wheelCalibration?.predictedAppearance(of: rgb) ?? rgb
    }

    private func publish(commit: Bool) {
        let rgb = HSVColorMath.rgb(h: hue, s: saturation, v: value)
        color = rgb; hex = rgb.hex; invalidHex = false; pendingCommit = !commit
        commit ? onCommit() : onPreview()
    }

    private func sync(_ next: RGB8) {
        let hsv = HSVColorMath.hsv(next)
        if hsv.s > 0 { hue = hsv.h }
        saturation = hsv.s; value = hsv.v; hex = next.hex; invalidHex = false
    }

    private func set(_ next: RGB8) {
        sync(next); color = next; pendingCommit = false; onCommit()
    }

    private func applyHex() {
        guard let next = RGB8(hex: hex) else { invalidHex = true; return }
        set(next)
    }
}
