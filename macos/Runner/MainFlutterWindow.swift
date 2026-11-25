import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let platformChannel = FlutterMethodChannel(
      name: "com.example.huginn_messenger/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    platformChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "installUpdate" {
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["path"] as? String,
              URL(fileURLWithPath: path).pathExtension == "pkg",
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "INVALID_PACKAGE", message: "Expected a PKG installer", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
          [url],
          withApplicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app"),
          configuration: configuration
        ) { _, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "INSTALL_FAILED", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
        return
      }
      guard call.method == "showWindow" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      result(nil)
    }

    super.awakeFromNib()
  }
}
