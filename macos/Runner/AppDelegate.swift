import Cocoa
import FlutterMacOS

/// Bridges macOS "open document" events (double-click / "Open With" in Finder)
/// to Flutter over the `ocideck/open_file` method channel.
///
/// macOS often delivers open events before the Flutter engine is ready, so
/// paths are buffered until the Dart side asks for them via `getLaunchFiles`
/// (cold start). Once Dart has signalled it is ready, later events are pushed
/// immediately via `openFiles` (warm start).
final class OpenFileHandler {
  static let shared = OpenFileHandler()

  private var pending: [String] = []
  private var flutterReady = false
  private var channel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "ocideck/open_file", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getLaunchFiles" {
        self.flutterReady = true
        let files = self.pending
        self.pending = []
        result(files)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func addFiles(_ paths: [String]) {
    // macOS may deliver the same launch through both `application(_:open:)`
    // and the legacy `application(_:openFile:)`. Drop paths already queued so a
    // single open never produces two tabs.
    let fresh = paths.filter { !pending.contains($0) }
    guard !fresh.isEmpty else { return }
    pending.append(contentsOf: fresh)
    flush()
  }

  private func flush() {
    guard flutterReady, let channel = channel, !pending.isEmpty else { return }
    let files = pending
    pending = []
    channel.invokeMethod("openFiles", arguments: files)
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
      NSApp.applicationIconImage = NSImage(contentsOfFile: iconPath)
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Finder open events ("Open With", double-click) arrive here on all
  // supported macOS versions. We deliberately do not also implement the legacy
  // `application(_:openFile:)`, which would deliver the same launch twice.
  override func application(_ application: NSApplication, open urls: [URL]) {
    let paths = urls.filter { $0.isFileURL }.map { $0.path }
    OpenFileHandler.shared.addFiles(paths)
  }
}
