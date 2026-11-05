// The shared building blocks both surfaces are made of: rules, the preview stage,
// cards, pages, rows, buttons, notices and section bars. The tokens they draw with
// live in InkTheme.swift.

import SwiftUI

// MARK: - Shared chrome
//
// Matte planes, restrained borders and typography keep working controls readable
// without competing with the keyboard photograph.

/// Replaces every `Divider()`, which at its default opacity is invisible on black.
struct InkRule: View {
    enum Axis { case horizontal, vertical }
    @Environment(\.colorSchemeContrast) private var contrast
    var axis: Axis = .horizontal
    init(_ axis: Axis = .horizontal) { self.axis = axis }

    var body: some View {
        Rectangle()
            .fill(contrast == .increased ? Ink.hairlineHi : Ink.hairline)
            .frame(width: axis == .vertical ? Ink.hairlineWidth : nil,
                   height: axis == .horizontal ? Ink.hairlineWidth : nil)
    }
}

/// The preview region: pitch-black ground, no plate, no radius, no inset, a bottom
/// fade into the ground, and up to two captions floating on the fade.
///
/// The fade is an OVERLAY, not a `.mask()`. A layer mask over an
/// NSViewRepresentable-hosted WKWebView is unreliable across compositing paths; an
/// overlay fading to an opaque literal black is pixel-identical here and touches
/// nothing about the web view.
struct InkStage<Content: View>: View {
    var caption: String = ""
    var trailing: String?
    var detail: String?
    var scrim: CGFloat = 28
    @ViewBuilder let content: Content

    private var captionHeight: CGFloat {
        (caption.isEmpty && detail == nil && trailing == nil) ? 0 : 30
    }

    var body: some View {
        content
            // Space is RESERVED for the captions rather than borrowed from the
            // board: the snapshot path substitutes a flat view that fills its box,
            // so a pure overlay would sit on the bottom key row.
            .padding(.bottom, captionHeight)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [Ink.ground.opacity(0), Ink.ground],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: scrim + captionHeight)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: Ink.s8) {
                    VStack(alignment: .leading, spacing: 1) {
                        if !caption.isEmpty {
                            Text(caption).font(Ink.caption(.medium))
                                .foregroundStyle(Ink.text)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        if let detail {
                            Text(detail).font(Ink.caption())
                                .foregroundStyle(Ink.textSecond)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: Ink.s8)
                    if let trailing {
                        Text(trailing).font(Ink.mono()).foregroundStyle(Ink.textSecond)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Ink.panelGutter)
                .padding(.bottom, Ink.s8)
                .allowsHitTesting(false)
                // The board itself is already labelled by KeyboardView.
                .accessibilityHidden(true)
            }
            .background(Ink.ground)
    }
}

/// Replaces `ControlSurface` and `SectionTitle`, which were always used together.
struct InkCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var title: String?
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Ink.s8) {
            if title != nil || detail != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title).font(Ink.sectionTitle).foregroundStyle(Ink.text)
                    }
                    if let detail {
                        Text(detail).font(Ink.caption()).foregroundStyle(Ink.textSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, Ink.s4)
            }
            content
        }
        .padding(Ink.cardPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Ink.rCard, style: .continuous)
            .fill(Ink.surface))
        // .strokeBorder, never .stroke: .stroke straddles the path and leaves a
        // half-pixel haze on black.
        .overlay(RoundedRectangle(cornerRadius: Ink.rCard, style: .continuous)
            .strokeBorder(contrast == .increased ? Ink.hairlineHi : Ink.hairline,
                          lineWidth: Ink.hairlineWidth))
    }
}

/// One inset and one measure, applied by the component instead of by convention.
/// The four sections used to start at 18/24/20/24 and cap at uncapped/700/820/720,
/// so the body jumped sideways on every tab switch while the chrome stayed put.
struct InkPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        // Fills the detail column rather than capping at a reading measure. This is
        // a control surface, not prose: a 720pt column pinned left inside a 1024pt
        // window stranded 300pt of dead black beside every card, and disagreed with
        // the stage above it, which is full width. Long prose caps its own line
        // length with InkProse instead, which is where a measure actually belongs.
        VStack(alignment: .leading, spacing: Ink.s16) { content }
            .padding(Ink.pagePad)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A reading measure for the few blocks that are genuinely paragraphs. Line length
/// is a typographic constraint on TEXT, so it belongs on the text and not on the
/// page that happens to contain some.
struct InkProse: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Ink.caption())
            .foregroundStyle(Ink.textSecond)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 620, alignment: .leading)
    }
}

/// A fixed leading label column and a flexible control. A plain HStack, not
/// Grid + LabeledContent: LabeledContent renders its own label/content pair inside
/// ONE grid cell, so a Grid's column sizing would not align anything.
struct InkRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(Ink.body())
                .foregroundStyle(Ink.textSecond)
                .frame(width: Ink.labelColumn, alignment: .leading)
            content
        }
        .frame(minHeight: Ink.rowControl)
        .accessibilityElement(children: .contain)
    }
}

/// A View wrapper, deliberately NOT a ButtonStyle: a ButtonStyle is not a view and
/// never receives environment values, so `@Environment(\.isEnabled)` inside one
/// silently returns its default forever.
struct InkButton: View {
    enum Tone { case normal, accent, destructive }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    var icon: String?
    var tone: Tone = .normal
    let action: () -> Void

    init(_ title: String, icon: String? = nil, tone: Tone = .normal,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.tone = tone
        self.action = action
    }

    private var fill: Color {
        guard isEnabled else { return Ink.well }
        return tone == .accent ? Ink.accent : Ink.well
    }

    // Disabled is an explicit colour, never .opacity() on the whole control: an
    // 0.35 multiplier is what put the colour button's hex readout at 2.8:1 for the
    // eleven modes that do not use colour.
    private var ink: Color {
        guard isEnabled else { return Ink.textDisabled }
        switch tone {
        case .accent: return Ink.onAccent
        case .destructive: return Ink.bad
        case .normal: return Ink.text
        }
    }

    private var border: Color {
        guard isEnabled else { return contrast == .increased ? Ink.hairlineHi : Ink.hairline }
        return tone == .accent ? .clear : (contrast == .increased ? Ink.strokeHi : Ink.stroke)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .medium))
                }
                Text(title).font(Ink.caption(tone == .accent ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 10)
            .frame(height: Ink.button)
            .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                .fill(fill))
            .overlay(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
                .strokeBorder(border, lineWidth: Ink.hairlineWidth))
            .contentShape(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One component for what used to be five bespoke advisory Labels. Always mounted
/// OUTSIDE a scroller: the one element that exists to be noticed should never be
/// the first thing pushed below the fold.
struct InkNotice: View {
    let text: String
    var systemImage: String = "exclamationmark.circle"
    var tint: Color = Ink.warn
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ text: String, systemImage: String = "exclamationmark.circle",
         tint: Color = Ink.warn, actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: Ink.s8) {
            Rectangle().fill(tint).frame(width: 2)
            Image(systemName: systemImage).font(.system(size: 11)).foregroundStyle(tint)
            Text(text).font(Ink.caption()).foregroundStyle(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Ink.s8)
            if let actionTitle, let action { InkButton(actionTitle, action: action) }
        }
        .padding(.horizontal, Ink.s12)
        .padding(.vertical, Ink.s8)
        .frame(minHeight: 34)
        // Hug the content. `minHeight` alone is a floor with no ceiling, so in a
        // fixed-height window this row absorbed every point the scroller above it
        // did not claim and grew into a box that covered the content it was
        // commenting on. The offscreen renders size the page to its intrinsic
        // height, so they had no spare space to give away and never showed it.
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: Ink.rControl, style: .continuous)
            .fill(tint.opacity(0.10)))
        .accessibilityElement(children: .combine)
    }
}

struct InkSectionBar<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Ink.s12) {
            Text(title).font(Ink.sectionTitle).foregroundStyle(Ink.text)
            Spacer(minLength: Ink.s12)
            trailing
        }
        .padding(.horizontal, Ink.pagePad)
        .frame(height: 44)
    }
}
