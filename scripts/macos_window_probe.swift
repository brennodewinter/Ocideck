import AppKit
import ApplicationServices
import ImageIO
import Vision

// Run this from an interactive macOS session with Accessibility and Screen Recording.
func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var ref: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &ref) == .success ? ref : nil
}
func axElement(_ object: CFTypeRef?) -> AXUIElement? {
    guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(object, to: AXUIElement.self)
}
func required(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain:"OciDeck resize probe",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
}
func frame(_ window: AXUIElement) -> CGRect {
    var position = CGPoint.zero, size = CGSize.zero
    if let p = attribute(window,kAXPositionAttribute) { AXValueGetValue(p as! AXValue, .cgPoint, &position) }
    if let s = attribute(window,kAXSizeAttribute) { AXValueGetValue(s as! AXValue, .cgSize, &size) }
    return CGRect(origin:position,size:size)
}
func setFrame(_ window: AXUIElement, _ rect: CGRect) throws {
    var position = rect.origin, size = rect.size
    let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint,&position)!)
    let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize,&size)!)
    try required(moved == .success && resized == .success, "Could not set macOS window position or size")
}
func capture(_ pid: pid_t, _ rect: CGRect, _ target: URL) throws -> (URL,CGRect) {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String:Any]] ?? []
    let candidates = windows.compactMap { item -> (UInt32,CGRect)? in
        guard item[kCGWindowOwnerPID as String] as? Int32 == pid,
              item[kCGWindowLayer as String] as? Int == 0,
              let id = item[kCGWindowNumber as String] as? UInt32,
              let bounds = item[kCGWindowBounds as String] as? NSDictionary,
              let actual = CGRect(dictionaryRepresentation:bounds) else {return nil}
        return (id,actual)
    }
    guard let best=candidates.min(by:{ abs($0.1.width-rect.width)+abs($0.1.height-rect.height) <
        abs($1.1.width-rect.width)+abs($1.1.height-rect.height) }) else {
        throw NSError(domain:"OciDeck resize probe",code:2,userInfo:[NSLocalizedDescriptionKey:"No onscreen OciDeck window"])
    }
    try required(abs(best.1.width-rect.width) < 8 && abs(best.1.height-rect.height) < 12,
                 "WindowServer geometry \(best.1) disagrees with Accessibility geometry \(rect)")
    let capture=Process()
    capture.executableURL=URL(fileURLWithPath:"/usr/sbin/screencapture")
    capture.arguments=["-x","-o","-l",String(best.0),target.path]
    try capture.run()
    capture.waitUntilExit()
    try required(capture.terminationStatus == 0,"Window screenshot failed")
    return (target,best.1)
}
func readImage(_ file: URL) throws -> CGImage {
    guard let source=CGImageSourceCreateWithURL(file as CFURL,nil), let image=CGImageSourceCreateImageAtIndex(source,0,nil) else {
        throw NSError(domain:"OciDeck resize probe",code:3,userInfo:[NSLocalizedDescriptionKey:"Screenshot could not be decoded"])
    }
    return image
}
func brightness(_ image: CGImage, _ x: Int, _ y: Int) -> Double {
    guard let crop=image.cropping(to:CGRect(x:x-10,y:y-10,width:20,height:20)),
          let c=CGContext(data:nil,width:1,height:1,bitsPerComponent:8,bytesPerRow:1,
              space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue),
          let data=c.data else {return 0}
    c.interpolationQuality = .high
    c.draw(crop,in:CGRect(x:0,y:0,width:1,height:1))
    return Double(data.load(as:UInt8.self))/255
}
func words(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["nl-NL", "en-US"]
    try VNImageRequestHandler(cgImage:image).perform([request])
    return request.results ?? []
}
func settingsName(_ observation: VNRecognizedTextObservation) -> Bool {
    guard let text = observation.topCandidates(1).first?.string.lowercased() else { return false }
    return text.contains("instellingen") || text.contains("settings")
}
func click(_ point: CGPoint) {
    let source=CGEventSource(stateID:.hidSystemState)
    CGEvent(mouseEventSource:source,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource:source,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left)?.post(tap: .cghidEventTap)
}

func waitFor<Value>(_ description: String, _ process: Process,
                    _ attempt: () throws -> Value?) throws -> Value {
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline && process.isRunning {
        if let value = try attempt() {
            return value
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    throw NSError(domain: "OciDeck window probe", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for " + description])
}

func movePointer(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func tool(_ executable: String, _ arguments: String...) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    try required(process.terminationStatus == 0, executable + " failed during probe setup")
}

func exercise() throws {
    try required(CommandLine.arguments.count == 3, "Usage: swift macos_window_probe.swift APP EVIDENCE")
    try required(AXIsProcessTrusted() && CGPreflightScreenCaptureAccess(),
                 "Accessibility and Screen Recording are required for this session")
    let original = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let evidence = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let files = FileManager.default
    guard let screen = NSScreen.main else {
        throw NSError(domain: "OciDeck window probe", code: 2)
    }

    let key = UUID().uuidString
    let home = files.temporaryDirectory.appendingPathComponent("ocideck-window-" + key)
    let copy = home.appendingPathComponent("OciDeck.app")
    let identifier = "com.dewinter.ocideck.window-probe." + key
    let support = files.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support").appendingPathComponent(identifier)
    try files.createDirectory(at: home, withIntermediateDirectories: true)
    defer {
        try? tool("/usr/bin/defaults", "delete", identifier)
        try? files.removeItem(at: support)
        try? files.removeItem(at: home)
    }
    try files.createDirectory(at: evidence, withIntermediateDirectories: true)
    try tool("/usr/bin/ditto", original.path, copy.path)
    try tool("/usr/bin/plutil", "-replace", "CFBundleIdentifier", "-string", identifier,
             copy.appendingPathComponent("Contents/Info.plist").path)
    try tool("/usr/bin/codesign", "--force", "--sign", "-", copy.path)
    guard let executable = Bundle(url: copy)?.executableURL else {
        throw NSError(domain: "OciDeck window probe", code: 3)
    }
    // macOS preferences are scoped by bundle identifier, even when HOME is overridden.
    try tool("/usr/bin/defaults", "write", identifier, "flutter.app_consent_accepted", "-bool", "true")
    try tool("/usr/bin/defaults", "write", identifier, "AppleLanguages", "-array", "en")

    let output = evidence.appendingPathComponent("application.log")
    _ = files.createFile(atPath: output.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: output)
    defer { try? outputHandle.close() }
    let process = Process()
    process.executableURL = executable
    var environment = ProcessInfo.processInfo.environment
    environment["HOME"] = home.path
    process.environment = environment
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    let previousApplication = NSWorkspace.shared.frontmostApplication
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    let pid = process.processIdentifier
    let active = try waitFor("native application", process) {
        NSRunningApplication(processIdentifier: pid)
    }

    try required(active.bundleIdentifier == identifier, "Probe did not launch under its isolated bundle identifier")
    let app = AXUIElementCreateApplication(pid)
    let window = try waitFor("a native window", process) {
        axElement(attribute(app, kAXMainWindowAttribute))
            ?? (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first
    }
    if let prior = CGEvent(source: nil)?.location {
        defer {
            previousApplication?.activate()
            movePointer(prior)
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        active.activate(options: [.activateAllWindows])
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            try tool("/usr/bin/open", "-a", copy.path)
        }
        _ = try waitFor("the isolated app in the foreground", process) {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ? true : nil
        }
        try assertWindow(window, pid, process, screen, evidence)
    } else {
        throw NSError(domain: "OciDeck window probe", code: 3)
    }
}

func assertWindow(_ window: AXUIElement, _ pid: pid_t, _ process: Process,
                  _ screen: NSScreen, _ evidence: URL) throws {
    let area = screen.visibleFrame
    let safeWidth = min(1480, area.width - 45)
    let safeHeight = min(850, area.height - 55)
    try required(safeWidth >= 1060 && safeHeight >= 740, "Display too small for two test sizes")
    let small = CGRect(x: 20, y: 55, width: min(1100, safeWidth), height: 720)
    let large = CGRect(x: 20, y: 55, width: safeWidth, height: safeHeight)
    var observations: [[String: Any]] = []
    for (index, target) in [small, large, small].enumerated() {
        try setFrame(window, target)
        let rect = try waitFor("logical geometry \(target) from \(frame(window))", process) {
            let actual = frame(window)
            return abs(actual.width - target.width) <= 2 && abs(actual.height - target.height) <= 2
                ? actual : nil
        }
        Thread.sleep(forTimeInterval: 0.75)
        let shot = evidence.appendingPathComponent("window-\(index).png")
        let (file, bounds) = try capture(pid, rect, shot)
        let image = try readImage(file)
        let right = brightness(image, image.width - 48, image.height / 2)
        let bottom = brightness(image, image.width * 3 / 4, image.height - 46)
        try required(right > 0.20 && bottom > 0.20, "Flutter content stops before a window edge")
        let footerHeight = min(image.height, 130)
        guard let footer = image.cropping(to: CGRect(x: 0, y: image.height - footerHeight,
                                                      width: image.width, height: footerHeight)),
              let control = try words(footer).first(where: settingsName) else {
            throw NSError(domain: "OciDeck window probe", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "Visible Settings button is missing"])
        }
        var result: [String: Any] = ["logicalWidth": rect.width, "logicalHeight": rect.height,
                                     "physicalWidth": image.width, "physicalHeight": image.height]
        if index == 1 {
            let location = CGPoint(
                x: bounds.minX + bounds.width * control.boundingBox.midX,
                y: bounds.maxY - bounds.height * CGFloat(footerHeight) / CGFloat(image.height)
                    * control.boundingBox.midY)
            try required(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                         "The probe no longer owns the foreground")
            movePointer(location)
            click(location)
            let modal = evidence.appendingPathComponent("settings-after-click.png")
            let field = try waitFor("Settings search field after a native mouse click", process) {
                let (file, _) = try capture(pid, rect, modal)
                return try words(readImage(file)).first {
                    guard let text = $0.topCandidates(1).first?.string.lowercased() else { return false }
                    return text.contains("search a setting") || text.contains("zoek een instelling")
                }
            }
            let box = field.boundingBox
            let neutralPoint = CGPoint(x: bounds.minX + bounds.width * box.midX,
                                       y: bounds.minY + bounds.height * (1 - box.midY) - 30)
            movePointer(neutralPoint)
            Thread.sleep(forTimeInterval: 0.3)
            let neutral = NSCursor.currentSystem?.image.tiffRepresentation
            movePointer(CGPoint(x: bounds.minX + bounds.width * box.midX,
                                y: bounds.minY + bounds.height * (1 - box.midY)))
            _ = try waitFor("native cursor change over Settings search", process) {
                guard let cursor = NSCursor.currentSystem?.image.tiffRepresentation,
                      cursor != neutral else { return nil as Bool? }
                return true
            }
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(pid)
            }
            result["cursorChanged"] = true
            result["settingsClicked"] = true
        }
        observations.append(result)
        print("Observed native window \(rect)")
    }
    try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
        .write(to: evidence.appendingPathComponent("result.json"))
}

do {
    try exercise()
} catch {
    fputs(error.localizedDescription + "\n", stderr)
    exit(1)
}
