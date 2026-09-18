import AppKit
import XCTest

@testable import DesktopMultiWindowSupport

final class CoverScreenStyleTests: XCTestCase {
    func testPreservesFullscreenStyleMask() {
        let current: NSWindow.StyleMask = [.titled, .resizable, .fullScreen]

        XCTAssertEqual(coverScreenStyleMask(from: current), current)
    }

    func testConvertsOrdinaryWindowToBorderless() {
        let current: NSWindow.StyleMask = [.titled, .closable, .resizable]

        XCTAssertEqual(coverScreenStyleMask(from: current), [.borderless])
    }
}
