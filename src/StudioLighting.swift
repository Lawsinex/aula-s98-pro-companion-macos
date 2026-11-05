import SwiftUI
import AppKit

/// The narrow destination rail is shared by every editor screen. Its mark is the
/// project's own app icon, not AULA's logo: this is an unofficial app.
struct StudioNavigationRail: View {
    @ObservedObject var model: AppModel
    private static let logo: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: Self.logo)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: 46, height: 46)
                .padding(.top, 14).padding(.bottom, 8)
                .accessibilityLabel("Aula S98 Pro Companion")
                .help("Aula S98 Pro Companion (unofficial)")
            ForEach(EditorTab.sidebarOrder) { tab in
                destination(tab)
            }
            Spacer(minLength: 24)
            Menu {
                Button("Open Lighting") { model.selectedTab = EditorTab.lighting.rawValue }
                Button("Sync keyboard clock") { model.clock.syncNow() }
                Divider()
                Button("Quit Aula S98 Pro Companion") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18))
                    .foregroundStyle(Ink.textSecond).frame(width: 44, height: 40)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 44).padding(.bottom, 14)
            .accessibilityLabel("Application actions")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.ground)
    }

    private func destination(_ tab: EditorTab) -> some View {
        let selected = model.selectedTab == tab.rawValue
        return Button { model.selectedTab = tab.rawValue } label: {
            Image(systemName: tab == .lighting ? "sun.max" : tab.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(selected ? Ink.accent : Ink.textSecond)
                .frame(width: 72, height: 56)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Ink.well : .clear))
                .overlay(alignment: .leading) {
                    if selected {
                        Capsule().fill(Ink.accent).frame(width: 3, height: 28)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if needsAttention(tab) {
                        Circle().fill(Ink.accent).frame(width: 4, height: 4).padding(7)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(needsAttention(tab) ? "Has changes or an issue to review" : "")
    }

    private func needsAttention(_ tab: EditorTab) -> Bool {
        switch tab {
        case .lighting: return model.lightHasUnappliedChanges || model.keysHaveUnappliedChanges
        case .clock: return false
        case .presets: return model.presets.lastError != nil
        case .settings: return model.configHasUnappliedChanges
        case .apps: return model.appProfiles.hasUnresolvedBinding(in: model.presets.presets)
        }
    }
}

enum StudioEffectSymbols {
    static func symbol(for id: Int) -> String {
        switch id {
        case 0: return "power"
        case 1: return "sun.max"
        case 2: return "circle.fill"
        case 3: return "circle.dotted"
        case 4: return "sparkles"
        case 5, 16: return "water.waves"
        case 6: return "camera.macro"
        case 7, 11: return "waveform.path"
        case 8: return "arrow.triangle.2.circlepath"
        case 9: return "waveform"
        case 10: return "rainbow"
        case 12: return "circle.dotted.circle"
        case 13, 14: return "circle.grid.2x2"
        case 15: return "target"
        case 17: return "mountain.2"
        case 18: return "cloud.drizzle"
        default: return "arrow.left.arrow.right"
        }
    }
}

struct StudioLightingView: View {
    @ObservedObject var model: AppModel
    @State private var erasing = false
    @State private var savePresented = false
    @State private var presetName = ""
    @State private var keyControlsPresented = false
    private var perKey: Bool { model.lightingSource == .perKey }

    var body: some View {
        HStack(spacing: 0) {
            library.frame(width: Ink.libraryWidth)
            InkRule(.vertical)
            VScroll {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    keyboard
                    outputControls
                    InkRule().padding(.top, 20)
                    colourWorkspace.padding(.top, 28)
                    if perKey { gradientControls.padding(.top, 24) }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $savePresented) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save preset").font(Ink.sectionTitle)
                Text(perKey ? "Keep this per-key layout." : "Keep this effect and its settings.")
                    .font(Ink.body()).foregroundStyle(Ink.textSecond)
                TextField("Preset name", text: $presetName)
                    .textFieldStyle(.roundedBorder).frame(width: 300)
                    .onSubmit(savePreset)
                HStack {
                    Button("Cancel") { savePresented = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    InkButton("Save preset", tone: .accent, action: savePreset)
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
                if let error = model.presets.lastError {
                    Text(error).font(Ink.caption()).foregroundStyle(Ink.bad)
                }
            }
            .padding(24).foregroundStyle(Ink.text).background(Ink.surface)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lighting").font(.system(size: 24, weight: .semibold))
                .padding(.top, 22).padding(.bottom, 18)
            HStack(spacing: 2) {
                ForEach(LightingSource.allCases) { source in
                    Button { model.lightingSource = source } label: {
                        Text(source.title).font(Ink.body(.medium))
                            .foregroundStyle(model.lightingSource == source ? Ink.onAccent : Ink.textSecond)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(model.lightingSource == source ? Ink.accent : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.lightingSource == source ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(2).background(RoundedRectangle(cornerRadius: 9).fill(Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.stroke, lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityLabel("Lighting source")
            .padding(.bottom, 22)
            if perKey {
                paintTools
            } else {
                Text("Effects · \(kModes.count)").font(Ink.body(.medium))
                    .foregroundStyle(Ink.textSecond).padding(.bottom, 12)
                ScrollViewReader { proxy in
                    VScroll {
                        VStack(spacing: 2) {
                            ForEach(kModes.filter { $0.id != 0 }) { mode in
                                if mode.id == 11 { InkRule().padding(.vertical, 12) }
                                effectRow(mode).id(mode.id)
                            }
                            InkRule().padding(.vertical, 12)
                            if let off = kModes.first(where: { $0.id == 0 }) { effectRow(off).id(0) }
                        }
                    }
                    .onChange(of: model.light.mode) { next in proxy.scrollTo(next, anchor: .center) }
                }
            }
            Spacer(minLength: 12)
            InkRule().padding(.top, 12)
            StudioDeviceStatus(device: model.device).padding(.vertical, 20)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.ground)
    }

    private func effectRow(_ mode: LightMode) -> some View {
        let selected = mode.id == model.light.mode
        return Button { model.selectMode(mode.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: StudioEffectSymbols.symbol(for: mode.id))
                    .font(.system(size: mode.id == 2 ? 9 : 18)).frame(width: 24)
                    .foregroundStyle(selected ? Ink.accent : Ink.textSecond)
                Text(model.modeName(mode)).font(Ink.body())
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 17))
                        .foregroundStyle(Ink.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 11)
            .frame(minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Ink.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Ink.text)
        .help(model.modeName(mode))
        .accessibilityLabel(model.modeName(mode))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AULA S98 Pro").font(.system(size: 32, weight: .semibold))
                Text(perKey ? "Per-key lighting" : model.modeName(model.currentMode))
                    .font(.system(size: 15)).foregroundStyle(Ink.textSecond)
            }
            Spacer(minLength: 12)
            Menu {
                Button("Save as new preset…") { presetName = ""; savePresented = true }
                if !model.presets.userPresets.isEmpty {
                    Section("Replace with current lighting") {
                        ForEach(model.presets.userPresets) { preset in
                            Button(preset.name) { _ = model.replace(preset) }
                        }
                    }
                }
                Divider()
                Button("Manage presets") { model.selectedTab = EditorTab.presets.rawValue }
            } label: {
                Text("Save to Preset").font(Ink.body())
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 14)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(width: 192, height: 40)
            .tint(Ink.text)
            .background(RoundedRectangle(cornerRadius: 8).fill(Ink.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.stroke, lineWidth: 1))
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.down").font(.system(size: 10))
                    .foregroundStyle(Ink.textSecond).padding(.trailing, 14).allowsHitTesting(false)
            }
        }
        .padding(.bottom, 16)
    }

    private var keyboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyboardView(colors: perKey ? model.displayColors(model.keys) : model.effectPreview,
                         highlight: perKey ? model.strokeKeys : [],
                         effectName: perKey ? "Per-key" : model.modeName(model.currentMode),
                         onPaint: paintAction,
                         onPaintEnded: paintEndedAction)
                .aspectRatio(kPreviewDisplayAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
            HStack {
                Text(perKey ? "Click or drag to paint"
                            : "Preview · the animation plays on the keyboard itself")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                if perKey {
                    Spacer()
                    Button("Paint a key…") { keyControlsPresented = true }
                        .font(Ink.caption()).buttonStyle(.plain).foregroundStyle(Ink.accent)
                        .accessibilityHint("Open individual key controls for keyboard and VoiceOver painting")
                        .popover(isPresented: $keyControlsPresented, arrowEdge: .bottom) {
                            nativeKeyControls
                        }
                }
            }
        }
        .padding(.bottom, 24)
    }

    private var nativeKeyControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(erasing ? "Erase a key" : "Paint a key").font(Ink.sectionTitle)
                Spacer()
                Button("Done") { keyControlsPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            Text("Use these native key buttons with the pointer, keyboard navigation or VoiceOver. Each activation finishes one paint stroke.")
                .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(KeyboardPaintAccessibility.keys) { cap in
                        Button {
                            KeyboardPaintAccessibility.activate(id: cap.id,
                                onPaint: { model.paintKey($0, erase: erasing) },
                                onPaintEnded: model.endPainting)
                        } label: {
                            Text(KeyboardPaintAccessibility.label(for: cap)
                                .replacingOccurrences(of: " key", with: ""))
                                .font(Ink.caption()).lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .accessibilityLabel(KeyboardPaintAccessibility.label(for: cap))
                        .accessibilityValue((model.keys[cap.id] ?? .black).accessibleLabel)
                    }
                }
            }.frame(height: 340)
        }
        .padding(20).frame(width: 640)
        .foregroundStyle(Ink.text).background(Ink.surface).tint(Ink.accent)
    }

    private var paintAction: ((Int) -> Void)? {
        guard perKey else { return nil }
        return { id in model.paintKey(id, erase: erasing) }
    }

    private var paintEndedAction: (() -> Void)? {
        guard perKey else { return nil }
        return { model.endPainting() }
    }

    private var outputControls: some View {
        VStack(spacing: 18) {
            InkRule()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    colourReadout
                    InkRule(.vertical).frame(height: 46)
                    StudioOutputSlider(title: "Brightness", symbol: "sun.max",
                                       value: model.light.brightness,
                                       enabled: perKey || model.light.mode != 0) {
                        model.updateBrightness($0, preview: $1, forPerKey: perKey)
                    }.frame(minWidth: 150)
                    if !perKey {
                        InkRule(.vertical).frame(height: 46)
                        StudioOutputSlider(title: "Speed", symbol: "clock",
                                           value: model.light.speed,
                                           enabled: model.currentMode.animated,
                                           onChange: model.updateSpeed).frame(minWidth: 150)
                        Toggle("Reverse", isOn: Binding(get: { model.light.reverse }, set: model.setReverse))
                            .toggleStyle(.switch).controlSize(.small)
                            .disabled(!model.currentMode.animated).fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    colourReadout
                    StudioOutputSlider(title: "Brightness", symbol: "sun.max",
                                       value: model.light.brightness,
                                       enabled: perKey || model.light.mode != 0) {
                        model.updateBrightness($0, preview: $1, forPerKey: perKey)
                    }
                    if !perKey {
                        StudioOutputSlider(title: "Speed", symbol: "clock",
                                           value: model.light.speed, enabled: model.currentMode.animated,
                                           onChange: model.updateSpeed)
                        Toggle("Reverse", isOn: Binding(get: { model.light.reverse }, set: model.setReverse))
                            .toggleStyle(.switch).controlSize(.small).disabled(!model.currentMode.animated)
                    }
                }
            }
        }
        .font(Ink.body())
    }

    private var colourReadout: some View {
        HStack(spacing: 12) {
            Circle().fill(Color(model.displayColor(perKey ? model.brush : model.light.color)))
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(perKey ? "Brush" : "Colour").font(Ink.body())
                Text((perKey ? model.brush : model.light.color).hex)
                    .font(Ink.mono(12)).foregroundStyle(Ink.textSecond)
                    .textSelection(.enabled)
            }
        }
        .frame(minWidth: 130, alignment: .leading)
    }

    private var colourWorkspace: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                inlineColour.frame(minWidth: 460)
                InkRule(.vertical).frame(height: 232)
                StudioApplyStatus(model: model).frame(width: 232)
            }
            VStack(alignment: .leading, spacing: 24) {
                inlineColour
                InkRule()
                StudioApplyStatus(model: model)
            }
        }
    }

    private var inlineColour: some View {
        StudioColourEditor(
            color: perKey ? $model.brush : Binding(get: { model.light.color }, set: { model.light.color = $0 }),
            swatches: model.recentColors,
            calibration: $model.calibration,
            calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
            enabled: perKey || model.currentMode.usesColor,
            onPreview: perKey ? {} : model.previewMode,
            onCommit: perKey ? {} : model.commitMode,
            onSave: { _ = model.saveColor($0) },
            onRemove: model.removeSavedColor,
            onRawPreview: model.previewRawColor,
            onCalibrationCommit: perKey ? model.applyKeys : model.commitMode)
    }

    private var paintTools: some View {
        VScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paint tools").font(Ink.body(.medium)).foregroundStyle(Ink.textSecond)
                Toggle("Erase", isOn: $erasing).toggleStyle(.switch).controlSize(.small)
                HStack {
                    InkButton("Undo", icon: "arrow.uturn.backward", action: model.undoKeys)
                        .disabled(!model.canUndoKeys)
                    InkButton("Redo", icon: "arrow.uturn.forward", action: model.redoKeys)
                        .disabled(!model.canRedoKeys)
                }
                InkRule()
                tool("Fill all keys", symbol: "paintbrush.fill") { model.replaceKeys(with: Paint.solid(model.brush)) }
                tool("Rainbow", symbol: "rainbow") { model.replaceKeys(with: Paint.rainbowHorizontal()) }
                tool("Random colours", symbol: "shuffle") { model.replaceKeys(with: Paint.random()) }
                tool("Clear", symbol: "eraser") { model.replaceKeys(with: [:]) }
                InkRule()
                Text("Choose a brush colour below the keyboard, then click or drag across the keys.")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tool(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(Ink.body())
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var gradientControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkRule()
            Text("Gradient").font(Ink.body(.medium))
            HStack {
                gradientColour("From", color: $model.gradientStart)
                gradientColour("To", color: $model.gradientEnd)
                InkButton("Apply gradient") {
                    model.replaceKeys(with: Paint.gradient(model.gradientStart, model.gradientEnd))
                }
            }
        }
    }

    private func gradientColour(_ label: String, color: Binding<RGB8>) -> some View {
        ColorPopoverButton(label: label, color: color, swatches: model.recentColors,
                           onSaveSwatch: { _ = model.saveColor($0) },
                           onRemoveSwatch: model.removeSavedColor,
                           calibration: $model.calibration,
                           calibrationPreviewEnabled: $model.calibrationPreviewEnabled,
                           onCalibrationPreview: model.previewRawColor,
                           onCalibrationCommit: model.applyKeys)
    }

    private func savePreset() {
        if model.savePreset(named: presetName, perKey: perKey) {
            presetName = ""; savePresented = false
        }
    }
}

private struct StudioDeviceStatus: View {
    @ObservedObject var device: AulaDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("AULA S98 Pro").font(Ink.body(.semibold))
            HStack(spacing: 7) {
                Circle().fill(device.connected ? Ink.ok : Ink.textDisabled).frame(width: 7, height: 7)
                Text(device.connected ? "USB connected" : "Offline · Connect with USB-C")
                    .font(Ink.caption()).foregroundStyle(Ink.textSecond)
            }
            if !device.connected {
                Button("Retry connection") { device.retryConnection() }
                    .buttonStyle(.plain).font(Ink.caption()).foregroundStyle(Ink.accent)
            }
        }
    }
}

private struct StudioApplyStatus: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var device: AulaDevice
    init(model: AppModel) { self.model = model; _device = ObservedObject(wrappedValue: model.device) }
    private var perKey: Bool { model.lightingSource == .perKey }
    private var unapplied: Bool { perKey ? model.keysHaveUnappliedChanges : model.lightHasUnappliedChanges }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(device.busy ? "Applying…" : (!device.connected ? "Preview only" : (unapplied ? "Ready to apply" : "Applied to keyboard")))
                .font(.system(size: 16, weight: .semibold))
            Text(!device.connected ? "Connect your keyboard with USB-C to apply changes."
                 : (unapplied ? "This preview has not been confirmed on the keyboard."
                    : "The keyboard confirmed the last lighting change."))
                .font(Ink.body()).foregroundStyle(Ink.textSecond)
                .fixedSize(horizontal: false, vertical: true)
            if device.phase == .failed {
                Text(device.status).font(Ink.caption()).foregroundStyle(Ink.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: perKey ? model.applyKeys : model.commitMode) {
                Text(unapplied ? "Apply again" : "Apply lighting").font(Ink.body(.medium))
                    .foregroundStyle(Ink.onAccent).frame(maxWidth: .infinity)
                    .frame(height: 40).background(RoundedRectangle(cornerRadius: 8).fill(Ink.accent))
            }
            .buttonStyle(.plain).disabled(device.busy).padding(.top, 16)
            if !perKey {
                Toggle("Cycle colours", isOn: Binding(get: { model.light.colorful }, set: model.setColorful))
                    .toggleStyle(.switch).controlSize(.small).font(Ink.caption())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StudioOutputSlider: View {
    let title: String
    let symbol: String
    let value: Int
    let enabled: Bool
    let onChange: (Int, Bool) -> Void
    @State private var pending: Int?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Ink.caption()).foregroundStyle(Ink.textSecond)
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Ink.textSecond)
                Slider(value: Binding(get: { Double(pending ?? value) }, set: {
                    let next = Int($0.rounded()); pending = next; onChange(next, true)
                }), in: 0...5, step: 1) { editing in
                    if !editing { onChange(pending ?? value, false); pending = nil }
                }
                .tint(Ink.accent).accessibilityLabel(title)
                Text("\(pending ?? value)/5").font(Ink.mono()).foregroundStyle(Ink.textSecond)
            }
        }
        .disabled(!enabled)
        .onDisappear {
            if let pending { onChange(pending, false); self.pending = nil }
        }
    }
}
