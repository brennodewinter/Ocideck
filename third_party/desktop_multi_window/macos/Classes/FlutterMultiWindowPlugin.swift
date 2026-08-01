// NOTICE: This file was modified by the OciDeck project.
// Original: desktop_multi_window (c) 2021 Mixin, Apache License 2.0 (see
// ../../LICENSE), commit 58a5868d1cb9031defa5db5868d6aaea0486d24a.
// Change: set mouseTrackingMode so non-key windows receive hover events;
// skip the window being registered/created when broadcasting onWindowsChanged
// (both AttachWindow and CreateWindow), whose engine handler is not installed
// yet (avoids a kInvalidArguments platform-message error on start).
// Modification notice per Apache-2.0 section 4(b); see ../../MODIFICATIONS.md.

import Cocoa
import FlutterMacOS

public class FlutterMultiWindowPlugin: NSObject, FlutterPlugin {

    private let windowId: WindowId
    private let windowArgument: String
    

    init(window: FlutterWindow) {
        self.windowId = window.windowId
        self.windowArgument = window.windowArgument
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        guard let app = NSApplication.shared.delegate as? FlutterAppDelegate else {
            debugPrint(
                "failed to find flutter main window, application delegate is not FlutterAppDelegate"
            )
            return
        }
        guard let window = app.mainFlutterWindow else {
            debugPrint("failed to find flutter main window")
            return
        }
        MultiWindowManager.shared.AttachWindow(window: window, registrar: registrar)
    }

    public typealias OnWindowCreatedCallback = (FlutterViewController) -> Void
    static var onWindowCreatedCallback: OnWindowCreatedCallback?

    public static func setOnWindowCreatedCallback(_ callback: @escaping OnWindowCreatedCallback) {
        onWindowCreatedCallback = callback
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let isWindowEvent = call.method.hasPrefix("window_")
        if isWindowEvent {
            let arguments = call.arguments as! [String: Any?]
            let windowId = arguments["windowId"] as! WindowId
            guard let window = MultiWindowManager.shared.windows[windowId] else {
                result(
                    FlutterError(
                        code: "-1", message: "failed to find target window. \(windowId)",
                        details: nil))
                return
            }

            window.handleWindowMethod(method: call.method, arguments: arguments, result: result)
            return
        }

        switch call.method {
        case "createWindow":
            let arguments = call.arguments as! [String: Any?]
            let windowId = MultiWindowManager.shared.CreateWindow(arguments: arguments)
            result(windowId)
        case "getWindowDefinition":
            let definition: [String: Any] = [
                "windowId": windowId,
                "windowArgument": windowArgument,
            ]
            result(definition)
        case "getAllWindows":
            let windows = MultiWindowManager.shared.getAllWindows()
            result(windows)
        default:
            result(FlutterMethodNotImplemented)
        }

    }
}

class MultiWindowManager: NSObject {

    static let shared: MultiWindowManager = MultiWindowManager()

    private override init() {}

    var windows: [WindowId: FlutterWindow] = [:]

    func AttachWindow(window: NSWindow, registrar: FlutterPluginRegistrar) {
        // check window exists
        for (_, flutterWindow) in windows {
            if flutterWindow.window == window {
                return
            }
        }
        let windowId = WindowId.generate()
        let flutterWindow = FlutterWindow(windowId: windowId, windowArgument: "", window: window)
        windows[windowId] = flutterWindow

        let channel = registerMultiWindowChannel(window: flutterWindow, with: registrar)
        flutterWindow.setChannel(channel)

        // Same guard as CreateWindow: don't send onWindowsChanged to the window
        // being attached. This runs during plugin registration at startup — the
        // engine's platform-message handler is not installed yet, so notifying
        // this window makes FlutterEngineSendPlatformMessage fail with
        // kInvalidArguments / "Invalid engine handle" as the very first log line.
        // Any *other* already-attached window is still notified.
        notifyWindowsChanged(excluding: windowId)
    }

    func CreateWindow(arguments: [String: Any?]) -> WindowId {
        let windowId = WindowId.generate()

        let config = WindowConfiguration.fromJson(arguments)

        let window = CustomWindow(configuration: config)

        let project = FlutterDartProject()
        project.dartEntrypointArguments = ["multi_window", windowId, config.arguments]
        let flutterViewController = FlutterViewController(project: project)
        // By default Flutter only delivers hover (mouse-moved) events to the
        // key window. The audience/beamer window is borderless and never
        // becomes key (the keyboard must stay with the presenter), so without
        // this it would never see hover at all — and state set by a click
        // (e.g. a chart highlight) would never be cleared again.
        flutterViewController.mouseTrackingMode = .inActiveApp
        window.contentViewController = flutterViewController
        window.setFrame(NSRect(x: 0, y: 0, width: 800, height: 600), display: true)

        window.orderFront(nil)
        window.setIsVisible(!config.hiddenAtLaunch)

        FlutterMultiWindowPlugin.onWindowCreatedCallback?(flutterViewController)

        let registrar = flutterViewController.registrar(forPlugin: "DesktopMultiWindowPlugin")

        let flutterWindow = FlutterWindow(
            windowId: windowId, windowArgument: config.arguments, window: window)
        windows[windowId] = flutterWindow

        let channel = registerMultiWindowChannel(window: flutterWindow, with: registrar)
        flutterWindow.setChannel(channel)

        // Notify the *existing* windows, but not the one just created. Its
        // Flutter engine is not running yet — the Dart isolate has not set up
        // its method-channel handler — so sending to it here makes
        // FlutterEngineSendPlatformMessage fail with kInvalidArguments /
        // "Invalid engine handle" on startup. The new window has no use for its
        // own creation event anyway (a window queries getAllWindows on demand),
        // so skipping it drops the failing message without losing behaviour.
        notifyWindowsChanged(excluding: windowId)

        return windowId
    }

    func removeWindow(windowId: WindowId) {
        if windows.removeValue(forKey: windowId) != nil {
            notifyWindowsChanged()
        }
    }

    func getAllWindowIds() -> [WindowId] {
        return Array(windows.keys)
    }

    func getAllWindows() -> [[String: String]] {
        return windows.values.map { window in
            [
                "windowId": window.windowId,
                "windowArgument": window.windowArgument,
            ]
        }
    }

    private func notifyWindowsChanged(excluding excludedId: WindowId? = nil) {
        for (id, window) in windows where id != excludedId {
            window.notifyWindowEvent("onWindowsChanged", data: [:])
        }
    }

    // register multi window method channel for all engine. include main or created by this plugin
    private func registerMultiWindowChannel(
        window: FlutterWindow, with registrar: FlutterPluginRegistrar
    ) -> FlutterMethodChannel {
        let channel = FlutterMethodChannel(
            name: "mixin.one/desktop_multi_window", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(FlutterMultiWindowPlugin(window: window), channel: channel)

        // register window method channel plugin
        WindowChannel.register(with: registrar)

        return channel
    }

}
