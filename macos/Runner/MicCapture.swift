import AVFoundation
import CoreAudio
import Darwin
import FlutterMacOS

/// Desktop-microfoon voor #2516. `describe` en `freeBytes` openen niets
/// en vragen niets. `open` is de enige weg die om toestemming mag vragen.
/// Een Bluetooth-wissel of een verdwenen apparaat stopt de opname; we
/// stappen niet stil over op een ander apparaat.
final class MicCapture: NSObject, FlutterStreamHandler {
  static let shared = MicCapture()

  private var eventSink: FlutterEventSink?
  private var engine: AVAudioEngine?
  private var configObserver: NSObjectProtocol?
  private var aliveDevice: AudioDeviceID = 0
  private var aliveBlock: AudioObjectPropertyListenerBlock?
  private var observeChanges = false
  private var running = false

  func register(messenger: FlutterBinaryMessenger) {
    let methods = FlutterMethodChannel(
      name: "ocideck/mic_capture", binaryMessenger: messenger)
    let events = FlutterEventChannel(
      name: "ocideck/mic_capture_pcm", binaryMessenger: messenger)
    events.setStreamHandler(self)
    methods.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "describe":
        result(self.describe())
      case "open":
        let args = call.arguments as? [String: Any]
        self.open(deviceId: args?["deviceId"] as? String, result: result)
      case "stop":
        self.stopEngine()
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
    let inputs = listInputs()
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .denied, .restricted:
      return [
        "availability": "unavailable",
        "reason": "toestemming geweigerd",
        "inputs": inputs,
      ]
    case .authorized:
      if inputs.isEmpty {
        return [
          "availability": "unavailable",
          "reason": "geen invoerapparaat",
          "inputs": inputs,
        ]
      }
      return ["availability": "available", "inputs": inputs]
    case .notDetermined:
      return ["availability": "tryAfterPermission", "inputs": inputs]
    @unknown default:
      return [
        "availability": "unavailable",
        "reason": "onbekende toestemmingsstaat",
        "inputs": inputs,
      ]
    }
  }

  private func open(deviceId: String?, result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      startEngine(deviceId: deviceId, result: result)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          if granted {
            self.startEngine(deviceId: deviceId, result: result)
          } else {
            result(
              FlutterError(
                code: "permissionDenied",
                message: "toestemming geweigerd",
                details: nil))
          }
        }
      }
    case .denied, .restricted:
      result(
        FlutterError(
          code: "permissionDenied",
          message: "toestemming geweigerd",
          details: nil))
    @unknown default:
      result(
        FlutterError(
          code: "sourceUnavailable",
          message: "microfoon niet beschikbaar",
          details: nil))
    }
  }

  private func startEngine(deviceId: String?, result: @escaping FlutterResult) {
    stopEngine()
    let engine = AVAudioEngine()
    let input = engine.inputNode
    if let deviceId, let id = UInt32(deviceId) {
      if !deviceHasInput(id) || !setInputDevice(id, node: input) {
        result(
          FlutterError(
            code: "sourceUnavailable",
            message: "invoerapparaat niet gevonden",
            details: nil))
        return
      }
      watchAlive(id)
    } else {
      watchAlive(defaultInputDevice())
    }
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      stopEngine()
      result(
        FlutterError(
          code: "sourceUnavailable",
          message: "geen audioklok op de invoer",
          details: nil))
      return
    }
    input.installTap(onBus: 0, bufferSize: 4096, format: format) {
      [weak self] buffer, _ in
      guard let self, let data = self.interleavedS16(buffer) else { return }
      DispatchQueue.main.async {
        guard self.running else { return }
        self.eventSink?(FlutterStandardTypedData(bytes: data))
      }
    }
    do {
      try engine.start()
    } catch {
      stopEngine()
      result(
        FlutterError(
          code: "sourceUnavailable",
          message: "microfoon starten mislukt",
          details: nil))
      return
    }
    self.engine = engine
    running = true
    let rate = Int(format.sampleRate.rounded())
    let channels = Int(format.channelCount)
    // De configuratiewissel vuurt ook bij het starten zelf. Pas daarna
    // telt hij als een echt vertrokken apparaat.
    DispatchQueue.main.async { [weak self] in
      guard let self, self.running else { return }
      self.observeChanges = true
      self.configObserver = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange,
        object: engine,
        queue: .main
      ) { [weak self] _ in
        guard let self, self.observeChanges else { return }
        self.end(cause: self.endCause())
      }
    }
    result(["sampleRate": rate, "channels": channels])
  }

  private func endCause() -> String {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    if status == .denied || status == .restricted {
      return "permissionRevoked"
    }
    return "sourceLost"
  }

  private func end(cause: String) {
    guard running else { return }
    eventSink?(["event": "ended", "cause": cause])
    stopEngine()
  }

  private func stopEngine() {
    observeChanges = false
    if let configObserver {
      NotificationCenter.default.removeObserver(configObserver)
      self.configObserver = nil
    }
    removeAliveListener()
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine = nil
    running = false
  }

  private func interleavedS16(_ buffer: AVAudioPCMBuffer) -> Data? {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    if frames == 0 || channels == 0 { return nil }
    var out = Data(count: frames * channels * 2)
    let wrote: Bool = out.withUnsafeMutableBytes { raw in
      guard let dst = raw.baseAddress?.assumingMemoryBound(to: Int16.self) else {
        return false
      }
      if let ints = buffer.int16ChannelData {
        for channel in 0..<channels {
          for frame in 0..<frames {
            dst[frame * channels + channel] = ints[channel][frame]
          }
        }
        return true
      }
      if let floats = buffer.floatChannelData {
        for channel in 0..<channels {
          for frame in 0..<frames {
            let sample = max(-1, min(1, floats[channel][frame]))
            dst[frame * channels + channel] = Int16(sample * 32767)
          }
        }
        return true
      }
      return false
    }
    return wrote ? out : nil
  }

  private func freeBytes(_ path: String?) -> Int? {
    guard let path, !path.isEmpty else { return nil }
    var stats = statfs()
    if statfs(path, &stats) != 0 { return nil }
    let bytes = Int64(stats.f_bavail) * Int64(stats.f_bsize)
    if bytes < 0 { return nil }
    return Int(bytes)
  }

  private func listInputs() -> [[String: Any]] {
    let fallback = defaultInputDevice()
    return inputDeviceIds().map { id in
      [
        "id": String(id),
        "label": deviceName(id),
        "transport": transportName(id),
        "isDefault": id == fallback,
      ]
    }
  }

  private func inputDeviceIds() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    if AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) != noErr {
      return []
    }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    if count <= 0 { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    if AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) != noErr {
      return []
    }
    return ids.filter(deviceHasInput)
  }

  private func deviceHasInput(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    if AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) != noErr {
      return false
    }
    return size > 0
  }

  private func defaultInputDevice() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }

  private func deviceName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceNameCFString,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    // De property geeft een +1 CFStringRef terug. `Unmanaged?` is groter
    // dan die pointer, dus we lezen de pointer zelf en nemen het eigendom
    // over — anders lekt de naam, of we lezen voorbij de schrijf.
    var raw: UnsafeMutableRawPointer?
    var size = UInt32(MemoryLayout<UnsafeMutableRawPointer>.size)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &raw)
    if status == noErr, let raw {
      let taken = Unmanaged<CFString>.fromOpaque(raw).takeRetainedValue() as String
      if !taken.isEmpty { return taken }
    }
    return "Microfoon \(id)"
  }

  private func transportName(_ id: AudioDeviceID) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) != noErr {
      return "unknown"
    }
    switch transport {
    case kAudioDeviceTransportTypeUSB:
      return "usb"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
      return "bluetooth"
    case kAudioDeviceTransportTypeBuiltIn:
      return "builtIn"
    default:
      return "unknown"
    }
  }

  private func setInputDevice(_ id: AudioDeviceID, node: AVAudioInputNode) -> Bool {
    guard let unit = node.audioUnit else { return false }
    var device = id
    let status = AudioUnitSetProperty(
      unit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &device,
      UInt32(MemoryLayout<AudioDeviceID>.size))
    return status == noErr
  }

  private func watchAlive(_ id: AudioDeviceID) {
    removeAliveListener()
    guard id != 0 else { return }
    aliveDevice = id
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsAlive,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      guard let self, self.running, self.observeChanges else { return }
      if !self.isAlive(id) { self.end(cause: self.endCause()) }
    }
    aliveBlock = block
    AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block)
  }

  private func isAlive(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsAlive,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var alive: UInt32 = 1
    var size = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &alive) != noErr {
      return false
    }
    return alive != 0
  }

  private func removeAliveListener() {
    guard aliveDevice != 0, let block = aliveBlock else {
      aliveDevice = 0
      aliveBlock = nil
      return
    }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsAlive,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    AudioObjectRemovePropertyListenerBlock(
      aliveDevice, &address, DispatchQueue.main, block)
    aliveDevice = 0
    aliveBlock = nil
  }
}
