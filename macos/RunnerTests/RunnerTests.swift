import Cocoa
import FlutterMacOS
import XCTest
@testable import huginn_messenger

@MainActor
class RunnerTests: XCTestCase {

  func testStatusItemIsInstalledDuringApplicationLaunch() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let item = try XCTUnwrap(delegate.statusItem)
    XCTAssertTrue(item.isVisible)
    let image = try XCTUnwrap(item.button?.image)
    XCTAssertTrue(image.isValid)
    XCTAssertTrue(image.isTemplate)
    XCTAssertTrue(try XCTUnwrap(item.button?.window).isVisible)
    XCTAssertNotNil(item.menu)
  }

  func testDockUsesTheBundledHuginnIcon() throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
    let bundledIcon = try XCTUnwrap(NSImage(contentsOf: url))
    let dockIcon = try XCTUnwrap(NSApp.applicationIconImage)
    let actual = try bitmap(of: dockIcon)
    let expected = try bitmap(of: bundledIcon)
    var difference: CGFloat = 0
    for y in 0..<32 {
      for x in 0..<32 {
        let a = try XCTUnwrap(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let e = try XCTUnwrap(expected.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        difference += abs(a.redComponent - e.redComponent)
          + abs(a.greenComponent - e.greenComponent)
          + abs(a.blueComponent - e.blueComponent)
      }
    }
    // AppKit can resample the Dock copy; compare the image rather than PNG
    // encoding or insignificant rounding differences.
    XCTAssertLessThan(difference / (32 * 32 * 3), 0.01)
  }

  func testClosingAndReopeningWindowKeepsStatusItem() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let window = try XCTUnwrap(delegate.mainFlutterWindow)
    window.close()
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(try XCTUnwrap(delegate.statusItem).isVisible)
    delegate.showMainWindow(nil)
    XCTAssertTrue(window.isVisible)
  }

  private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
    return bitmap
  }
}
