// The app's keyboard colour preview: the reference photograph of the board,
// re-tinted per key in one WebGL pass, hosted in a WKWebView.
//
// The page is built by viewer/build.sh into a single self-contained file with
// the decomposed textures spliced in as data URIs, and copied into the app
// bundle as app3d.html. It loads nothing from anywhere, which is what lets it
// work offline and inside a sandbox.
//
// Swift owns the colours; the page owns the pixels. Everything crosses the
// bridge as LED id -> [r,g,b]: the colours that go out over USB, passed through
// the app's display calibration so the preview shows what the keys really do.

import AppKit
import SwiftUI
import WebKit

// MARK: - Bridge

/// WKUserContentController retains its handlers, and the handler needs the
/// web view — so the actual listener is held weakly through this shim.
private final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var target: KeyboardWebController?
    init(_ target: KeyboardWebController) { self.target = target }
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.handle(message)
    }
}

/// A crashed WebContent process may crash again immediately while reloading.
/// Limit automatic recovery to two attempts in a thirty-second burst instead of
/// allowing a resource failure to become a permanent reload/CPU loop.
struct KeyboardPreviewRecoveryPolicy {
    static let burstDuration: TimeInterval = 30
    static let maximumReloads = 2
    private var burstStartedAt: TimeInterval?
    private(set) var reloadsInBurst = 0

    mutating func shouldReload(at now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        if let start = burstStartedAt {
            if now < start || now - start >= Self.burstDuration {
                burstStartedAt = now
                reloadsInBurst = 0
            }
        } else {
            burstStartedAt = now
        }
        guard reloadsInBurst < Self.maximumReloads else { return false }
        reloadsInBurst += 1
        return true
    }
}

final class KeyboardWebController: NSObject, WKNavigationDelegate {
    let webView: WKWebView

    var onPaint: ((Int) -> Void)?
    var onPaintEnded: (() -> Void)?

    private var ready = false
    /// True once the page has answered, whether it told us or we asked it.
    var isReady: Bool { ready }

    /// The most recently updated live preview. The review path uses it to check
    /// the board actually renders inside the real window, not just offscreen —
    /// SwiftUI hosting a WKWebView is the part a headless render cannot prove.
    private(set) static weak var live: KeyboardWebController?
    private var sentColors: String = ""
    private var sentHighlight: String = ""
    private var sentLabel: String = ""
    private var pendingColors: String?
    private var pendingHighlight: String?
    private var pendingLabel: String?
    private var recoveryPolicy = KeyboardPreviewRecoveryPolicy()
    private(set) var automaticReloadCount = 0

    override convenience init() { self.init(pixelRatio: nil) }

    /// `pixelRatio` pins `window.devicePixelRatio` for the page. The review
    /// renders pass 1 so the canvas has exactly as many pixels as the view has
    /// points, whatever display the process happens to run on — on a 2x screen
    /// the page would otherwise draw the photograph upsampled, and no render
    /// could line up texel for texel with the reference frames.
    init(pixelRatio: Double?) {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        if let pixelRatio {
            config.userContentController.addUserScript(WKUserScript(
                source: "Object.defineProperty(window, 'devicePixelRatio', "
                    + "{get: function(){ return \(pixelRatio); }});",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 320),
                            configuration: config)
        super.init()
        // WKWebView copies its configuration at init, so the handler has to go
        // on the copy's controller — registering on the original silently does
        // nothing and every message is dropped.
        webView.configuration.userContentController.add(ScriptProxy(self), name: "kb")
        webView.navigationDelegate = self
        webView.allowsMagnification = false
        // The board floats on whatever surface the app puts behind it.
        if webView.responds(to: Selector(("setDrawsBackground:"))) {
            webView.setValue(false, forKey: "drawsBackground")
        }
        webView.setValue(false, forKey: "allowsLinkPreview")
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "app3d", withExtension: "html") else {
            alog("ERR app3d.html missing from the bundle — preview will be blank")
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    fileprivate func handle(_ message: WKScriptMessage) {
        // Everything arriving here was authored by our own bundled page, but it
        // is still parsed defensively rather than trusted by shape.
        guard let body = message.body as? [String: Any],
              let kind = body["t"] as? String else { return }
        switch kind {
        case "ready":
            markReady()
        case "paint":
            if let led = body["led"] as? Int { onPaint?(led) }
        case "paintEnd":
            onPaintEnded?()
        case "error":
            alog("ERR keyboard preview: \(body["m"] as? String ?? "unknown")")
        default:
            break
        }
    }

    /// Belt and braces: the page posts `ready`, and the navigation callback
    /// confirms it independently, so a dropped message cannot leave the preview
    /// stuck showing an unlit board.
    func markReady() {
        guard !ready else { return }
        ready = true
        flush(force: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("typeof window.kbSetColors === 'function'") { [weak self] v, _ in
            if (v as? NSNumber)?.boolValue == true { self?.markReady() }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The renderer has lost all JavaScript state, even when our values have
        // not changed. Keep the latest pending frame and force it back across
        // the bridge once the new page reports ready.
        ready = false
        sentColors = ""
        sentHighlight = ""
        sentLabel = ""
        guard recoveryPolicy.shouldReload(at: ProcessInfo.processInfo.systemUptime) else {
            alog("ERR keyboard preview repeatedly terminated — automatic recovery paused")
            return
        }
        automaticReloadCount += 1
        alog("keyboard preview renderer terminated — reloading bundled page")
        load()
    }

    // MARK: state in

    func apply(colors: [Int: RGB8], highlight: Set<Int>, label: String) {
        Self.live = self
        pendingColors = Self.encode(colors)
        pendingHighlight = Self.encode(highlight)
        pendingLabel = label
        flush(force: false)
    }

    private func flush(force: Bool) {
        guard ready else { return }
        if let c = pendingColors, force || c != sentColors {
            sentColors = c
            webView.evaluateJavaScript("kbSetColors(\(c))", completionHandler: nil)
        }
        if let h = pendingHighlight, force || h != sentHighlight {
            sentHighlight = h
            webView.evaluateJavaScript("kbSetHighlight(\(h))", completionHandler: nil)
        }
        if let l = pendingLabel, force || l != sentLabel {
            sentLabel = l
            let quoted = String(data: (try? JSONSerialization.data(
                withJSONObject: [l], options: [])) ?? Data(), encoding: .utf8) ?? "[\"\"]"
            webView.evaluateJavaScript("kbSetLabel(\(quoted)[0])", completionHandler: nil)
        }
    }

    /// `{"20":[255,90,31],…}` — sorted so an unchanged frame encodes identically
    /// and can be skipped instead of crossing the bridge again.
    static func encode(_ colors: [Int: RGB8]) -> String {
        var out = "{"
        var first = true
        for id in kLedIndices {
            guard let c = colors[id] else { continue }
            if !first { out += "," }
            first = false
            out += "\"\(id)\":[\(c.r),\(c.g),\(c.b)]"
        }
        return out + "}"
    }

    static func encode(_ ids: Set<Int>) -> String {
        "[" + ids.sorted().map(String.init).joined(separator: ",") + "]"
    }
}

// MARK: - SwiftUI

/// The photograph's own aspect ratio, 1672 x 941. The offscreen review render
/// uses it, so a round-trip render is the frame the camera took.
let kPreviewAspect: CGFloat = 1672.0 / 941.0

/// What the editor shows. The board and its reflection occupy y 190..810 of the
/// frame's 941 rows; the rest is empty black. Framing on that instead keeps the
/// preview to roughly the height the old one had, and the page crops to fill.
let kPreviewDisplayAspect: CGFloat = 1672.0 / 620.0

struct KeyboardPhotoView: NSViewRepresentable {
    var colors: [Int: RGB8]
    var highlight: Set<Int> = []
    var effectName: String = ""
    var onPaint: ((Int) -> Void)?
    var onPaintEnded: (() -> Void)?

    func makeCoordinator() -> KeyboardWebController { KeyboardWebController() }

    func makeNSView(context: Context) -> WKWebView {
        let c = context.coordinator
        c.onPaint = onPaint
        c.onPaintEnded = onPaintEnded
        c.apply(colors: colors, highlight: highlight, label: effectName)
        return c.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let c = context.coordinator
        c.onPaint = onPaint
        c.onPaintEnded = onPaintEnded
        c.apply(colors: colors, highlight: highlight, label: effectName)
    }
}

// MARK: - Offscreen render

/// The review path. WKWebView only paints once it is in a window and laid out,
/// so the snapshot runs a real (offscreen) window and pumps the run loop until
/// the page reports itself ready.
enum KeyboardWebSnapshot {
    static func render(colors: [Int: RGB8], label: String,
                       size: CGSize, timeout: TimeInterval = 25) -> NSImage? {
        let controller = KeyboardWebController(pixelRatio: 1)
        let view = controller.webView
        view.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: view.frame,
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        // Off the visible desktop, but on screen enough that AppKit lays it out
        // and WebKit actually rasterises.
        window.setFrameOrigin(NSPoint(x: -size.width - 400, y: 0))
        window.orderFrontRegardless()

        var painted = false
        controller.apply(colors: colors, highlight: [], label: label)

        // Let the page load, build the scene and draw a frame.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !painted {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            var done = false
            var ok = false
            view.evaluateJavaScript("window.kbRenderNow ? kbRenderNow() : 0") { value, _ in
                ok = ((value as? NSNumber)?.intValue ?? 0) == 1
                done = true
            }
            let inner = Date().addingTimeInterval(2)
            while !done && Date() < inner {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            if ok { controller.markReady() }
            painted = ok && controller.isReady
        }
        guard painted else {
            window.close()
            return nil
        }
        // Let the colours that markReady() queued actually cross the bridge.
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))

        // WebKit throttles requestAnimationFrame for a window that is not on a
        // visible screen, so the frame that would have picked the colours up
        // never runs. Drive the render explicitly instead of waiting for it.
        //
        // The pixels are read straight out of the canvas rather than through
        // takeSnapshot, which captures at the screen's backing scale: on a 2x
        // display that doubled every dimension and the gates could not even
        // compare the result. The canvas is composited onto black because that
        // is the reference photographs' own field, so a round-trip render
        // comes out as exactly what the camera recorded.
        var dataURL: String?
        var drawn = false
        view.evaluateJavaScript("""
            (function(){
              kbRenderNow();
              var src = document.getElementById('gl');
              var out = document.createElement('canvas');
              out.width = src.width; out.height = src.height;
              var ctx = out.getContext('2d');
              ctx.fillStyle = '#000000';
              ctx.fillRect(0, 0, out.width, out.height);
              ctx.drawImage(src, 0, 0);
              return out.toDataURL('image/png');
            })()
            """) { value, _ in
            dataURL = value as? String
            drawn = true
        }
        let drawBy = Date().addingTimeInterval(10)
        while !drawn && Date() < drawBy {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        var image: NSImage?
        if let dataURL, let comma = dataURL.firstIndex(of: ","),
           let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
           let rep = NSBitmapImageRep(data: data),
           rep.pixelsWide == Int(size.width), rep.pixelsHigh == Int(size.height) {
            let result = NSImage(size: size)
            result.addRepresentation(rep)
            image = result
        } else {
            alog("ERR keyboard3d canvas readout failed or came back the wrong size")
        }
        window.close()
        return image
    }
}

// MARK: - Live-window review

extension KeyboardWebSnapshot {
    /// Snapshot whichever preview is currently on screen, at whatever size and
    /// scale the window gives it. Returns false if none has been built, which is
    /// itself the finding.
    static func renderLive(to path: String) -> Bool {
        guard let controller = KeyboardWebController.live, controller.isReady else { return false }
        let view = controller.webView
        guard view.window != nil, view.bounds.width > 1 else { return false }

        var image: NSImage?
        var done = false
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: view.bounds.size)
        view.takeSnapshot(with: config) { snap, _ in image = snap; done = true }
        let deadline = Date().addingTimeInterval(10)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard let data = image?.tiffRepresentation
            .flatMap({ NSBitmapImageRep(data: $0) })
            .flatMap({ $0.representation(using: .png, properties: [:]) }) else { return false }
        try? data.write(to: URL(fileURLWithPath: path))
        return true
    }
}

extension KeyboardWebSnapshot {
    /// The README's screenshots: this app's own frontmost window, drawn in-process so
    /// no Screen Recording permission is involved. A web view does not take part in
    /// cacheDisplay, so its snapshot is laid over the spot it occupies.
    static func captureWindow(to path: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return false }
        content.cacheDisplay(in: content.bounds, to: rep)

        if let controller = KeyboardWebController.live, controller.isReady,
           controller.webView.window === window {
            let view = controller.webView
            var image: NSImage?
            var done = false
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: view.bounds.size)
            view.takeSnapshot(with: config) { snap, _ in image = snap; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            guard let image, let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            var frame = view.convert(view.bounds, to: content)
            if content.isFlipped { frame.origin.y = content.bounds.height - frame.maxY }
            image.draw(in: frame)
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Drive the page's own hit test and confirm the LED id makes it back over
    /// the bridge. This is the half of the preview a render cannot show.
    static func checkPaintBridge() -> Bool {
        guard let controller = KeyboardWebController.live, controller.isReady else { return false }
        let previous = controller.onPaint
        var received: Int?
        controller.onPaint = { received = $0 }
        defer { controller.onPaint = previous }

        // Aim at the centre of the board, where a cap is guaranteed to be.
        let js = """
        (function(){
          var r = document.body.getBoundingClientRect();
          var led = null;
          for (var f = 0.42; f <= 0.62 && led === null; f += 0.04) {
            led = window.__kb3d_probe(r.width * 0.30, r.height * f);
          }
          if (led !== null) window.webkit.messageHandlers.kb.postMessage({t:'paint', led:led});
          return led === null ? -1 : led;
        })()
        """
        var done = false
        controller.webView.evaluateJavaScript(js) { _, _ in done = true }
        let deadline = Date().addingTimeInterval(6)
        while (!done || received == nil) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard let led = received else { return false }
        return kLedIndices.contains(led)
    }
}
