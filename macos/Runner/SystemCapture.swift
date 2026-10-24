import CoreMedia
import FlutterMacOS
import ScreenCaptureKit

/// Systeemgeluid via ScreenCaptureKit (#2518). `describe` vraagt niets.
/// `open` is de enige weg die het schermopnamevenster mag tonen. Video
/// wordt weggegooid; het eigen proces telt niet mee, anders neemt de
/// presentatie-doorvoer zichzelf op.
@available(macOS 13.0, *)
final class SystemCapture: NSObject, FlutterStreamHandler, SCStreamOutput,
  SCStreamDelegate
{
  static let shared = SystemCapture()

  private var eventSink: FlutterEventSink?
  private var stream: SCStream?
  private var running = false
  private let queue = DispatchQueue(label: "ocideck.system-capture")

  func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(
      name: "ocideck/system_capture", binaryMessenger: messenger)
    let events = FlutterEventChannel(
      name: "ocideck/system_capture_pcm", binaryMessenger: messenger)
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "describe":
        result(self.describe())
      case "open":
        self.open(result: result)
      case "stop":
        self.stopCapture()
        result(nil)
      case "freeBytes":
        let args = call.arguments as? [String: Any]
        result(self.freeBytes(args?["path"] as? String))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func describe() -> [String: Any] {
    [
      "availability": "tryAfterPermission",
      "inputs": [] as [Any],
    ]
  }

  private func open(result: @escaping FlutterResult) {
    if running {
      result(
        FlutterError(
          code: "sourceUnavailable",
          message: "systeemgeluid is al open",
          details: nil))
      return
    }
    let granted =
      CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    if !granted {
      result(
        FlutterError(
          code: "permissionDenied",
          message: "toestemming voor systeemgeluid geweigerd",
          details: nil))
      return
    }
    Task { @MainActor in
      do {
        try await self.begin(result: result)
      } catch {
        self.stopCapture()
        result(
          FlutterError(
            code: "sourceUnavailable",
            message: "systeemgeluid openen mislukt",
            details: nil))
      }
    }
  }

  private func begin(result: @escaping FlutterResult) async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else {
      throw CocoaError(.fileNoSuchFile)
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.excludesCurrentProcessAudio = true
    config.sampleRate = 48_000
    config.channelCount = 2
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    config.showsCursor = false
    let stream = SCStream(filter: filter, configuration: config, delegate: self)
    try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try await stream.startCapture()
    self.stream = stream
    running = true
    result(["sampleRate": 48000, "channels": 2])
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sample: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, running, CMSampleBufferDataIsReady(sample) else {
      return
    }
    guard let pcm = interleavedS16(sample) else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self, self.running else { return }
      self.eventSink?(FlutterStandardTypedData(bytes: pcm))
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      self?.end(cause: "sourceLost")
    }
  }

  private func end(cause: String) {
    guard running else { return }
    eventSink?(["event": "ended", "cause": cause])
    stopCapture()
  }

  private func stopCapture() {
    let stream = self.stream
    self.stream = nil
    running = false
    stream?.stopCapture()
  }

  private func freeBytes(_ path: String?) -> Int? {
    let url = URL(fileURLWithPath: path ?? NSTemporaryDirectory(), isDirectory: true)
    let values = try? url.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey
    ])
    if let bytes = values?.volumeAvailableCapacityForImportantUsage {
      return Int(bytes)
    }
    return nil
  }

  private func interleavedS16(_ sample: CMSampleBuffer) -> Data? {
    guard let format = CMSampleBufferGetFormatDescription(sample),
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)
    else { return nil }
    let desc = asbd.pointee
    guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
    var length = 0
    var pointer: UnsafeMutablePointer<Int8>?
    guard
      CMBlockBufferGetDataPointer(
        block,
        atOffset: 0,
        lengthAtOffsetOut: nil,
        totalLengthOut: &length,
        dataPointerOut: &pointer) == noErr,
      let pointer
    else { return nil }
    let frames = CMSampleBufferGetNumSamples(sample)
    let channels = Int(desc.mChannelsPerFrame)
    if frames <= 0 || channels <= 0 { return nil }
    let floats = (desc.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    let bits = Int(desc.mBitsPerChannel)
    let count = frames * channels
    var pcm = Data(count: count * 2)
    pcm.withUnsafeMutableBytes { raw in
      let dst = raw.bindMemory(to: Int16.self)
      if floats && bits == 32 {
        let src = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: count)
        for i in 0..<count {
          var s = src[i]
          if s > 1 { s = 1 }
          if s < -1 { s = -1 }
          dst[i] = Int16(s * 32767)
        }
      } else if !floats && bits == 16 {
        let src = UnsafeRawPointer(pointer).bindMemory(to: Int16.self, capacity: count)
        for i in 0..<count { dst[i] = src[i] }
      } else {
        for i in 0..<count { dst[i] = 0 }
      }
    }
    return pcm
  }
}
