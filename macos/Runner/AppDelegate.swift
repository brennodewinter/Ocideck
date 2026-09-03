import Cocoa
import FlutterMacOS

/// Bridges macOS "open document" events (double-click / "Open With" in Finder)
/// to Flutter over the `ocideck/open_file` method channel.
///
/// macOS often delivers open events before the Flutter engine is ready, so
/// paths are buffered until the Dart side asks for them via `getLaunchFiles`
/// (cold start). Once Dart has signalled it is ready, later events are pushed
/// immediately via `openFiles` (warm start).
/// Zorgt dat élk gewoon bestand in de open-kiezer aantikbaar is — ook wanneer
/// macOS een onthouden UTI-filter of de CFBundleDocumentTypes van de app
/// anders zou grijzen. Mappen blijven navigeerbaar.
private final class EnableAllFilesDelegate: NSObject, NSOpenSavePanelDelegate {
  func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
    true
  }
}

final class OpenFileHandler {
  static let shared = OpenFileHandler()

  private var pending: [String] = []
  private var flutterReady = false
  private var channel: FlutterMethodChannel?
  /// Sterke referentie zolang het paneel open is — anders ruimt ARC de
  /// delegate op en valt `shouldEnable` stil.
  private var pickDelegate: EnableAllFilesDelegate?
  private var saveDelegate: EnableAllFilesDelegate?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "ocideck/open_file", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "getLaunchFiles":
        self.flutterReady = true
        let files = self.pending
        self.pending = []
        result(files)
      case "pickFile":
        // Eigen kiezer: file_picker's FileType.any zet géén filter, en een
        // sheet boven een Flutter-dialoog erfde soms de document-types van de
        // app waardoor .md grijs bleef. Dialoog eerst dicht + runModal +
        // lege allowedContentTypes + shouldEnable=true.
        let args = call.arguments as? [String: Any]
        self.pickFile(
          title: args?["dialogTitle"] as? String,
          initialDirectory: args?["initialDirectory"] as? String,
          allowsMultiple: args?["allowsMultiple"] as? Bool ?? false,
          result: result)
      case "saveFile":
        // Eigen opslaan-kiezer, om dezelfde reden als pickFile hierboven:
        // file_picker.saveFile gebruikt beginSheetModal op het Flutter-venster,
        // en die sheet erft de CFBundleDocumentTypes-filter van de app en
        // verschijnt niet betrouwbaar. runModal + lege allowedContentTypes
        // spiegelt de openen-kiezer. De Dart-kant sluit de bestemmingsdialoog
        // vóór deze call, zodat er geen geneste modal is.
        let saveArgs = call.arguments as? [String: Any]
        self.saveFile(
          title: saveArgs?["dialogTitle"] as? String,
          fileName: saveArgs?["fileName"] as? String,
          initialDirectory: saveArgs?["initialDirectory"] as? String,
          result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  /// Systeemvenster "bestand openen" waarin elk bestand selecteerbaar is.
  /// Validatie (Marp of plat document) gebeurt aan de Dart-kant na de keuze.
  ///
  /// Levert altijd een LIJST van paden — ook bij één bestand — zodat er maar
  /// één vorm over het kanaal reist. Met allowsMultiple mag de gebruiker een
  /// stapel tegelijk aanwijzen; elk pad opent aan de Dart-kant in een eigen
  /// tabblad.
  private func pickFile(
    title: String?,
    initialDirectory: String?,
    allowsMultiple: Bool,
    result: @escaping FlutterResult
  ) {
    let dialog = NSOpenPanel()
    dialog.title = title ?? ""
    dialog.canChooseFiles = true
    dialog.canChooseDirectories = false
    dialog.allowsMultipleSelection = allowsMultiple
    dialog.allowsOtherFileTypes = true
    dialog.canSelectHiddenExtension = true
    // Lege allowedContentTypes = alle typen (Apple). De
    // EnableAllFilesDelegate forceert shouldEnable=true voor alles wat toch
    // nog grijs zou staan.
    dialog.allowedContentTypes = []
    let delegate = EnableAllFilesDelegate()
    pickDelegate = delegate
    dialog.delegate = delegate
    if let initialDirectory, !initialDirectory.isEmpty {
      dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
    }

    // runModal, geen sheet: een sheet op het Flutter-venster erfde de
    // CFBundleDocumentTypes-filter van de app. De Dart-kant sluit het
    // Openen-dialoog vóór deze call, zodat er geen geneste modal is.
    let response = dialog.runModal()
    pickDelegate = nil
    if response == .OK {
      result(dialog.urls.map { $0.path })
    } else {
      result([String]())
    }
  }

  /// Systeemvenster "bestand opslaan". Spiegel van [pickFile]: runModal i.p.v.
  /// file_picker's sheet, met lege allowedContentTypes zodat de
  /// CFBundleDocumentTypes-filter van de app het venster niet beperkt of
  /// onzichtbaar maakt. De aanroeper schrijft de bytes zelf naar het gekozen
  /// pad (file_picker.saveFile doet op desktop ook niet meer dan het pad
  /// leveren).
  private func saveFile(
    title: String?,
    fileName: String?,
    initialDirectory: String?,
    result: @escaping FlutterResult
  ) {
    let dialog = NSSavePanel()
    dialog.title = title ?? ""
    dialog.showsTagField = false
    dialog.showsHiddenFiles = false
    dialog.canCreateDirectories = true
    dialog.nameFieldStringValue = fileName ?? ""
    dialog.allowsOtherFileTypes = true
    dialog.canSelectHiddenExtension = true
    // Lege allowedContentTypes = alle typen (Apple). De
    // EnableAllFilesDelegate forceert shouldEnable=true.
    dialog.allowedContentTypes = []
    let delegate = EnableAllFilesDelegate()
    saveDelegate = delegate
    dialog.delegate = delegate
    if let initialDirectory, !initialDirectory.isEmpty {
      dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
    }

    // runModal, geen sheet: dezelfde reden als bij pickFile — een sheet op het
    // Flutter-venster erfde de CFBundleDocumentTypes-filter en verschijnt niet
    // betrouwbaar. De Dart-kant sluit de bestemmingsdialoog vóór deze call.
    let response = dialog.runModal()
    saveDelegate = nil
    if response == .OK, let path = dialog.url?.path {
      result(path)
    } else {
      result(nil)
    }
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

/// Leest `NSPasteboardTypeHTML`. Het pasteboard-pakket levert die variant op
/// macOS niet (alleen Windows/Android), terwijl webeditors hun neststructuur
/// juist daar neerzetten (#1595).
final class ClipboardHtmlHandler {
  static let shared = ClipboardHtmlHandler()

  private var channel: FlutterMethodChannel?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "ocideck/clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "html":
        result(Self.htmlFromPasteboard())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private static func htmlFromPasteboard() -> String? {
    let pasteboard = NSPasteboard.general
    if let html = pasteboard.string(forType: .html), !html.isEmpty {
      return html
    }
    if let html = pasteboard.string(forType: NSPasteboard.PasteboardType("public.html")),
      !html.isEmpty
    {
      return html
    }
    return nil
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
