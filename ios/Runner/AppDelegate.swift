import AVFoundation
import CoreImage
import Flutter
import ImageIO
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeCamera: NativeCameraController?
  private let watchBridge = WatchBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleCameraNames")
    else { return }

    // Names and permission for the Camera tab. Capture itself now runs in
    // NativeCameraController below — OpenCV's iOS backend is pinned to
    // 480×360 and dies on any attempt to ask for more — but this channel
    // stays: a code-pushed Dart side older than the native module still
    // calls listCameraNames, and both generations request permission here.
    let cameraChannel = FlutterMethodChannel(
      name: "omni_sniffer/apple_cameras",
      binaryMessenger: registrar.messenger())
    cameraChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "listCameraNames":
        let devices =
          AVCaptureDevice.devices(for: .video) + AVCaptureDevice.devices(for: .muxed)
        result(devices.map { $0.localizedName })
      case "requestCameraAccess":
        // Capture never asks for consent on its own — it just opens the
        // device and reads nothing while the decision is pending.
        // Authorization has to be settled here, before the Dart side
        // opens anything.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
          result(true)
        case .notDetermined:
          AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { result(granted) }
          }
        default:
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let controller = NativeCameraController()
    nativeCamera = controller
    let captureChannel = FlutterMethodChannel(
      name: "omni_sniffer/native_camera",
      binaryMessenger: registrar.messenger())
    captureChannel.setMethodCallHandler { [weak controller] call, result in
      controller?.handle(call, result: result)
    }
    let frameChannel = FlutterEventChannel(
      name: "omni_sniffer/native_camera/frames",
      binaryMessenger: registrar.messenger())
    frameChannel.setStreamHandler(controller)

    // The paired Apple Watch mirrors the session screen's tiles. Activated
    // here so the watch can be handed the current screen the moment it
    // launches, whether or not the golfer has opened a session yet.
    watchBridge.attach(messenger: registrar.messenger())
  }
}

// MARK: - Native camera capture

/// One camera streaming JPEG frames to Flutter — the capture backend for the
/// Camera tab on iOS.
///
/// The rest of the pipeline (ring buffer, shot trigger, replay, export)
/// consumes JPEG frames with wall-clock timestamps, so that is exactly what
/// this produces: every frame is encoded here and shipped over the event
/// channel, and the Dart side decodes a throttled subset for the live
/// preview. Rotation is applied on the capture connection — the hardware
/// path — so the buffers themselves arrive oriented and every consumer
/// agrees for free, matching the OpenCV worker's rotate-at-the-source
/// contract.
private final class NativeCameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  struct StartError: Error { let message: String }

  private let slot: Int
  private let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let videoQueue: DispatchQueue
  private let ciContext = CIContext()
  private let colorSpace = CGColorSpaceCreateDeviceRGB()

  /// Called with each outgoing event, from the capture queue.
  private let emit: ([String: Any]) -> Void

  private var errorObserver: NSObjectProtocol?

  private static let jpegQuality = CIImageRepresentationOption(
    rawValue: kCGImageDestinationLossyCompressionQuality as String)

  init(slot: Int, emit: @escaping ([String: Any]) -> Void) {
    self.slot = slot
    self.emit = emit
    self.videoQueue = DispatchQueue(label: "omni-camera-frames-\(slot)")
    super.init()
  }

  /// Opens [deviceId] on the format nearest the request and starts frames
  /// flowing. Zero width/height means no preference, which lands on
  /// 1280×720@60 — high enough rate to be worth scrubbing, small enough
  /// that six seconds of clip doesn't menace the memory ceiling.
  func start(
    deviceId: String, width: Int, height: Int, fps: Int, rotationQuarterTurns: Int,
    mirrored: Bool
  ) throws -> [String: Any] {
    guard !deviceId.isEmpty, let device = AVCaptureDevice(uniqueID: deviceId) else {
      throw StartError(
        message: "That camera is no longer attached. Rescan and pick again.")
    }

    let wantAuto = width <= 0 || height <= 0
    let wantWidth = wantAuto ? 1280 : width
    let wantHeight = wantAuto ? 720 : height
    // A chosen size with no chosen rate means 30, matching the desktop
    // worker's contract; full auto aims higher because it can.
    let wantFps = fps > 0 ? fps : (wantAuto ? 60 : 30)

    // Nearest size first, rate ceiling second. A format that cannot reach
    // the asked rate is penalised but stays eligible — a camera with no
    // 120fps mode should still open at its best, not refuse.
    var best: AVCaptureDevice.Format?
    var bestScore = Int.min
    for format in device.formats {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      let maxRate = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
      var score = -10 * (abs(Int(dims.width) - wantWidth) + abs(Int(dims.height) - wantHeight))
      if maxRate + 0.5 < Double(wantFps) {
        score -= Int(Double(wantFps) - maxRate) * 20
      }
      if score > bestScore {
        bestScore = score
        best = format
      }
    }
    guard let format = best else {
      throw StartError(message: "The camera reports no usable formats.")
    }
    let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    let maxRate = format.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 30
    let grantedFps = max(1, min(wantFps, Int(maxRate)))

    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      throw StartError(
        message: "The camera refused to open: \(error.localizedDescription)")
    }

    session.beginConfiguration()
    // The chosen activeFormat governs, not a preset.
    session.sessionPreset = .inputPriority
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      throw StartError(message: "The camera's stream could not be attached.")
    }
    session.addInput(input)
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: videoQueue)
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      throw StartError(message: "The camera's output could not be attached.")
    }
    session.addOutput(output)
    session.commitConfiguration()

    do {
      try device.lockForConfiguration()
      device.activeFormat = format
      // Same value both ends pins the rate rather than capping it.
      let frameDuration = CMTime(value: 1, timescale: CMTimeScale(grantedFps))
      device.activeVideoMinFrameDuration = frameDuration
      device.activeVideoMaxFrameDuration = frameDuration
      device.unlockForConfiguration()
    } catch {
      throw StartError(
        message: "The camera would not take its configuration: \(error.localizedDescription)")
    }

    applyRotation(rotationQuarterTurns)
    applyMirror(mirrored)

    errorObserver = NotificationCenter.default.addObserver(
      forName: .AVCaptureSessionRuntimeError, object: session, queue: nil
    ) { [weak self] note in
      guard let self = self else { return }
      let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
      self.emit([
        "type": "error",
        "slot": self.slot,
        "message": error?.localizedDescription ?? "The camera stopped unexpectedly.",
      ])
    }

    session.startRunning()
    return [
      "width": Int(dims.width),
      "height": Int(dims.height),
      "fps": Double(grantedFps),
    ]
  }

  /// Clockwise quarter turns, mapped onto the connection so rotation costs
  /// nothing per frame. Index 0 is the sensor's native landscape.
  func applyRotation(_ quarterTurns: Int) {
    guard let connection = output.connection(with: .video),
      connection.isVideoOrientationSupported
    else { return }
    let orientations: [AVCaptureVideoOrientation] = [
      .landscapeRight, .portrait, .landscapeLeft, .portraitUpsideDown,
    ]
    connection.videoOrientation = orientations[((quarterTurns % 4) + 4) % 4]
  }

  /// Left-to-right mirror, carried by the connection like the rotation above,
  /// so it costs nothing per frame and lands on the recorded buffers rather
  /// than only on what's displayed. The automatic adjustment has to be turned
  /// off first — left on, AVFoundation overwrites the value with its own
  /// front/back-camera default.
  func applyMirror(_ mirrored: Bool) {
    guard let connection = output.connection(with: .video),
      connection.isVideoMirroringSupported
    else { return }
    connection.automaticallyAdjustsVideoMirroring = false
    connection.isVideoMirrored = mirrored
  }

  func stop() {
    if let observer = errorObserver {
      NotificationCenter.default.removeObserver(observer)
      errorObserver = nil
    }
    output.setSampleBufferDelegate(nil, queue: nil)
    if session.isRunning {
      session.stopRunning()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    guard
      let jpeg = ciContext.jpegRepresentation(
        of: image, colorSpace: colorSpace, options: [Self.jpegQuality: 0.75])
    else { return }
    // Wall clock, not the buffer's presentation time: the ring buffer lines
    // frames up against the BLE packet's arrival, which is stamped with the
    // same clock on the Dart side.
    let us = Int(Date().timeIntervalSince1970 * 1_000_000)
    emit([
      "type": "frame",
      "slot": slot,
      "jpeg": FlutterStandardTypedData(bytes: jpeg),
      "us": us,
    ])
  }
}

/// Owns the per-slot feeds and speaks the omni_sniffer/native_camera
/// channels. All session work happens on one serial queue; frame and error
/// events hop to the main thread, where the event sink lives.
final class NativeCameraController: NSObject, FlutterStreamHandler {
  private let sessionQueue = DispatchQueue(label: "omni-camera-control")
  private var feeds: [Int: NativeCameraFeed] = [:]
  private var sink: FlutterEventSink?

  private static func discoverDevices() -> [AVCaptureDevice] {
    var types: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
    ]
    if #available(iOS 17.0, *) {
      // External UVC cameras, which iPadOS enumerates here.
      types.append(.external)
    }
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: types, mediaType: .video, position: .unspecified
    ).devices
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "listDevices":
      result(Self.discoverDevices().map { ["id": $0.uniqueID, "name": $0.localizedName] })

    case "start":
      let slot = args["slot"] as? Int ?? 0
      let deviceId = args["deviceId"] as? String ?? ""
      let width = args["width"] as? Int ?? 0
      let height = args["height"] as? Int ?? 0
      let fps = args["fps"] as? Int ?? 0
      let rotation = args["rotation"] as? Int ?? 0
      let mirrored = args["mirrored"] as? Bool ?? false
      sessionQueue.async { [weak self] in
        guard let self = self else { return }
        // A replaced feed stops before its successor starts; two sessions
        // on one slot would fight over the device.
        self.feeds.removeValue(forKey: slot)?.stop()
        let feed = NativeCameraFeed(slot: slot) { [weak self] message in
          DispatchQueue.main.async { self?.sink?(message) }
        }
        do {
          let granted = try feed.start(
            deviceId: deviceId, width: width, height: height, fps: fps,
            rotationQuarterTurns: rotation, mirrored: mirrored)
          self.feeds[slot] = feed
          DispatchQueue.main.async { result(granted) }
        } catch let error as NativeCameraFeed.StartError {
          DispatchQueue.main.async {
            result(FlutterError(code: "camera", message: error.message, details: nil))
          }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(code: "camera", message: error.localizedDescription, details: nil))
          }
        }
      }

    case "stop":
      let slot = args["slot"] as? Int ?? 0
      sessionQueue.async { [weak self] in
        self?.feeds.removeValue(forKey: slot)?.stop()
        DispatchQueue.main.async { result(nil) }
      }

    case "setRotation":
      let slot = args["slot"] as? Int ?? 0
      let turns = args["turns"] as? Int ?? 0
      sessionQueue.async { [weak self] in
        self?.feeds[slot]?.applyRotation(turns)
        DispatchQueue.main.async { result(nil) }
      }

    case "setMirrored":
      let slot = args["slot"] as? Int ?? 0
      let mirrored = args["mirrored"] as? Bool ?? false
      sessionQueue.async { [weak self] in
        self?.feeds[slot]?.applyMirror(mirrored)
        DispatchQueue.main.async { result(nil) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
