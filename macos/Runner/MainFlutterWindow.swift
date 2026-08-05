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
      guard call.method == "listCameraNames" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let devices =
        AVCaptureDevice.devices(for: .video) + AVCaptureDevice.devices(for: .muxed)
      result(devices.map { $0.localizedName })
    }

    super.awakeFromNib()
  }
}
