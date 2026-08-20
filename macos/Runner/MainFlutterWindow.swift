import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    pointDartcvAtBundledFramework()

    let flutterViewController = FlutterViewController()
    // Keep hover events flowing while this window is not key (e.g. when a
    // dialog or the beamer window is in front): otherwise an element that was
    // hovered when the window lost key status keeps its hover styling because
    // the matching exit event is never delivered.
    flutterViewController.mouseTrackingMode = .inActiveApp
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Bridge macOS "open document" events to Flutter. Registered only on the
    // main window's engine, not on audience/beamer sub-windows.
    OpenFileHandler.shared.register(messenger: flutterViewController.engine.binaryMessenger)
    ClipboardHtmlHandler.shared.register(
      messenger: flutterViewController.engine.binaryMessenger)

    // Register the app's plugins in every sub-window (e.g. the audience/beamer
    // window) too, so video_player, image loading, etc. work there as well.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }

  /// Tells `dartcv4` (behind `opencv_core`) where the OpenCV binary actually is.
  ///
  /// On macOS the OpenCV symbols ship as `DartCvMacOS.framework`, but the
  /// package first tries `dlopen("libdartcv.dylib")` — a file that does not
  /// exist in a Flutter bundle. That call fails, the package prints a long
  /// "Error loading libdartcv.dylib ... fallback to process" block, and only
  /// then falls back to `DynamicLibrary.process()`, which does work. The result
  /// is a scary-looking error on every run that means nothing, which is exactly
  /// the kind of noise that trains you to skim past real errors.
  ///
  /// `DARTCV_LIB_PATH` is the package's own override, read before the fallback
  /// path is built, so pointing it at the framework binary inside our bundle
  /// makes the first attempt succeed and the message never appear. Must run
  /// before the Flutter engine starts: Dart caches `Platform.environment` on
  /// first access, and the VM boots with the FlutterViewController below.
  private func pointDartcvAtBundledFramework() {
    guard let frameworks = Bundle.main.privateFrameworksPath,
      let framework = Bundle(path: "\(frameworks)/DartCvMacOS.framework"),
      let binary = framework.executablePath
    else { return }

    // Overwrite = 0: an externally set DARTCV_LIB_PATH stays authoritative, so
    // pointing the app at a custom OpenCV build keeps working.
    setenv("DARTCV_LIB_PATH", binary, 0)
  }
}
