// NOTICE: This file was modified by the OciDeck project.
// Original: desktop_multi_window (c) 2021 Mixin, Apache License 2.0 (see
// ../../LICENSE), commit 58a5868d1cb9031defa5db5868d6aaea0486d24a.
// Change: implemented window_close, window_setFrame and window_coverScreen.
// Modification notice per Apache-2.0 section 4(b); see ../../MODIFICATIONS.md.

import Cocoa
import FlutterMacOS
import Foundation

typealias WindowId = String

extension WindowId {
    static func generate() -> WindowId {
        return UUID().uuidString
    }
}

class CustomWindow: NSWindow {

    init(configuration: WindowConfiguration) {
        super.init(
            contentRect: NSRect(x: 10, y: 10, width: 800, height: 600),
            styleMask: [.miniaturizable, .closable, .titled, .resizable], backing: .buffered,
            defer: false)

        self.isReleasedWhenClosed = false
    }
}

class FlutterWindow: NSObject {
    let windowId: WindowId
    let windowArgument: String
    private(set) var window: NSWindow
    private var channel: FlutterMethodChannel?

    private var willBecomeActiveObserver: NSObjectProtocol?
    private var didResignActiveObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?

    init(windowId: WindowId, windowArgument: String, window: NSWindow) {
        self.windowId = windowId
        self.windowArgument = windowArgument
        self.window = window
        super.init()

        willBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        didResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.didChangeOcclusionState(notification)
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [windowId] _ in
            MultiWindowManager.shared.removeWindow(windowId: windowId)
        }
    }

    deinit {
        if let willBecomeActiveObserver = willBecomeActiveObserver {
            NotificationCenter.default.removeObserver(willBecomeActiveObserver)
        }
        if let didResignActiveObserver = didResignActiveObserver {
            NotificationCenter.default.removeObserver(didResignActiveObserver)
        }
        if let closeObserver = closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
    }

    @objc func didChangeOcclusionState(_ notification: Notification) {
        if let controller = window.contentViewController as? FlutterViewController {
            controller.engine.handleDidChangeOcclusionState(notification)
        }
    }

    func setChannel(_ channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func notifyWindowEvent(_ event: String, data: [String: Any]) {
        if let channel = channel {
            channel.invokeMethod(event, arguments: data)
        } else {
            debugPrint("Channel not set for window \(windowId), cannot notify event \(event)")
        }
    }

    func handleWindowMethod(method: String, arguments: Any?, result: @escaping FlutterResult) {
        let args = arguments as? [String: Any?]
        switch method {
        case "window_show":
            window.makeKeyAndOrderFront(nil)
            window.setIsVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            result(nil)
        case "window_hide":
            window.orderOut(nil)
            result(nil)
        case "window_close":
            window.close()
            result(nil)
        case "window_setFrame":
            if let x = args?["x"] as? Double,
                let y = args?["y"] as? Double,
                let w = args?["width"] as? Double,
                let h = args?["height"] as? Double
            {
                window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            }
            result(nil)
        case "window_coverScreen":
            // Make this window a borderless surface that fills an entire screen —
            // used to show the audience slide fullscreen on the beamer while the
            // main (presenter) window stays on the laptop. We deliberately do not
            // make it the key window, so the keyboard stays with the presenter.
            let screens = NSScreen.screens
            var target: NSScreen? = nil
            // Prefer the screen the presenter is NOT on, when told which one that
            // is. The `external` heuristic below picks the non-primary screen,
            // which is only right when the presenter sits on the primary screen;
            // in a reversed setup it would pile both windows on the external
            // display (#1913).
            if let presenterIndex = args?["presenterScreen"] as? Int,
               presenterIndex >= 0, presenterIndex < screens.count,
               screens.count > 1 {
                let presenterScreen = screens[presenterIndex]
                target = screens.first(where: { $0 != presenterScreen })
            }
            if target == nil {
                let external = (args?["external"] as? Bool) ?? true
                target = NSScreen.main
                if external, let ext = screens.first(where: { $0 != NSScreen.main }) {
                    target = ext
                }
            }
            if let screen = target ?? screens.first {
                window.styleMask = [.borderless]
                // Raise above the menu bar (.mainMenu == 24) so the macOS menu
                // bar and notch area on the beamer are covered by the slide; a
                // plain .normal window would sit *under* the menu bar and leave
                // the Apple/Wi-Fi strip visible during the presentation. We stay
                // below .popUpMenu (101) so context menus still show on top.
                window.level = .statusBar
                // Keep the cover in place across Spaces/displays without ever
                // stealing keyboard focus from the presenter window.
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
                window.isOpaque = true
                window.setFrame(screen.frame, display: true)
                window.orderFrontRegardless()
                window.setIsVisible(true)
            }
            result(nil)
        default:
            result(FlutterError(code: "-1", message: "unknown method \(method)", details: nil))
        }
    }

}
