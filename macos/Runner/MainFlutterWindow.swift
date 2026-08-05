import AVFoundation
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Camera *names* for the Camera tab. Capture itself goes through
    // OpenCV's AVFoundation backend, which addresses devices by integer
    // index and cannot name them, and the `camera` plugin that names them
    // elsewhere has no macOS implementation.
    //
    // The list MUST mirror OpenCV's own enumeration in
    // cap_avfoundation_mac.mm — devicesWithMediaType:AVMediaTypeVideo plus
    // AVMediaTypeMuxed, in that order — so the name at position N describes
    // the device OpenCV opens for index N. That API is deprecated (hence
    // the build warning), deliberately: the modern DiscoverySession orders
    // devices differently, which made the picker open the wrong camera.
    let cameraChannel = FlutterMethodChannel(
      name: "omni_sniffer/apple_cameras",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
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

    super.awakeFromNib()
  }
}
