import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private(set) var statusItem: NSStatusItem?

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)

    // Load the icon from this bundle instead of a cached named Flutter image.
    if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let icon = NSImage(contentsOf: url) {
      NSApp.applicationIconImage = icon
    }

    guard statusItem == nil else { return }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      let image = NSImage(named: "StatusIcon")
      image?.size = NSSize(width: 18, height: 18)
      image?.isTemplate = true
      button.image = image
      button.toolTip = "Huginn Messenger"
      button.setAccessibilityLabel("Huginn Messenger")
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(
      title: "Open Huginn Messenger", action: #selector(showMainWindow(_:)), keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)

    let settingsItem = NSMenuItem(
      title: "Notification settings…", action: #selector(openNotificationSettings(_:)), keyEquivalent: ""
    )
    settingsItem.target = self
    menu.addItem(settingsItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Huginn Messenger", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)

    item.menu = menu
    statusItem = item
  }

  @objc func showMainWindow(_ sender: Any?) {
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc private func openNotificationSettings(_ sender: Any?) {
    guard let bundleID = Bundle.main.bundleIdentifier,
          let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)")
    else { return }
    NSWorkspace.shared.open(url)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep the messenger and local notifications running after closing its window.
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow(sender)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
