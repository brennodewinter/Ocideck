import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
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

    // Register the app's plugins in every sub-window (e.g. the audience/beamer
    // window) too, so video_player, image loading, etc. work there as well.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }
}
