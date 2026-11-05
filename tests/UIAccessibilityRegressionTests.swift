import Foundation
import AppKit
import WebKit

enum UIAccessibilityRegressionTests {
    @MainActor
    static func run(expect: (Bool, String) -> Void) {
        let controls = KeyboardPaintAccessibility.keys
        expect(controls.count == 96 && Set(controls.map(\.id)) == Set(kLedIndices),
               "accessible paint controls cover exactly the hardware's 96 key addresses")
        expect(Set(controls.map { KeyboardPaintAccessibility.label(for: $0) }).count == 96,
               "accessible key labels distinguish numpad and left/right modifier keys")
        var painted: [Int] = []
        var ended = 0
        for key in controls {
            KeyboardPaintAccessibility.activate(id: key.id, onPaint: { painted.append($0) },
                                                onPaintEnded: { ended += 1 })
        }
        expect(painted == controls.map(\.id) && ended == 96,
               "every accessible paint activation finishes exactly one undoable stroke")
        for invalid in [-1, 0, Proto.maxLED + 1, Int.max] {
            KeyboardPaintAccessibility.activate(id: invalid, onPaint: { painted.append($0) },
                                                onPaintEnded: { ended += 1 })
        }
        expect(painted.count == 96 && ended == 96,
               "invalid accessible key addresses never trigger paint or stroke completion")

        var recovery = KeyboardPreviewRecoveryPolicy()
        expect(recovery.shouldReload(at: 0) && recovery.shouldReload(at: 1),
               "preview recovery permits two bounded attempts")
        expect(!recovery.shouldReload(at: 2) && !recovery.shouldReload(at: 29),
               "a repeatedly crashing preview cannot become an automatic reload loop")
        expect(recovery.shouldReload(at: 30), "preview recovery budget renews after thirty seconds")
        expect(!recovery.shouldReload(at: .nan), "preview recovery rejects nonfinite times")

        // Drive the real navigation-delegate entry, not merely the policy helper.
        // This was red before the recovery handler: isReady stayed true forever.
        _ = NSApplication.shared
        let controller = KeyboardWebController()
        controller.apply(colors: [1: RGB8(r: 2, g: 3, b: 4)], highlight: [1], label: "Fixture")
        controller.markReady()
        controller.webView.navigationDelegate?.webViewWebContentProcessDidTerminate?(controller.webView)
        expect(!controller.isReady && controller.automaticReloadCount == 1,
               "WebContent termination clears stale readiness and initiates one recovery")
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        expect(controller.automaticReloadCount == 2,
               "the actual WebKit delegate honors the bounded recovery policy")
    }
}
