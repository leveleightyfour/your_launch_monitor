import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Camera *names* for the Camera tab, same contract as the macOS Runner:
    // capture goes through OpenCV's AVFoundation backend, which addresses
    // devices by integer index, and this list lets index N carry a name a
    // golfer recognises ("Back Camera") rather than an internal identifier.
    //
    // The list MUST mirror OpenCV's own enumeration in cap_avfoundation.mm —
    // devicesWithMediaType:AVMediaTypeVideo plus AVMediaTypeMuxed, in that
    // order — so the name at position N describes the device OpenCV opens
    // for index N. That API is deprecated (hence the build warning),
    // deliberately: the modern DiscoverySession orders devices differently,
    // which made the picker open the wrong camera on macOS.
    guard
      let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleCameraNames")
    else { return }
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
        // Capture goes through OpenCV, which never asks for consent — it
        // just opens the device and reads nothing while the decision is
        // pending. Authorization has to be settled here, before the Dart
        // side probes its first index.
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
  }
}
