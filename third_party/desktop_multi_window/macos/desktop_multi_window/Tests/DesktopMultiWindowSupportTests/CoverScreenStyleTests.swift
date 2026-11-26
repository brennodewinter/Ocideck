import AppKit
import XCTest

@testable import DesktopMultiWindowSupport

final class CoverScreenStyleTests: XCTestCase {
    func testIdentitySelectionRejectsEmptyRemovedAndShiftedDisplays() {
        XCTAssertNil(audienceDisplayIndex([], presenter: "a", target: "b"))
        XCTAssertNil(audienceDisplayIndex(["a"], presenter: "a", target: "b"))
        XCTAssertNil(audienceDisplayIndex(["a", "c"], presenter: "a", target: "b"))
        XCTAssertNil(audienceDisplayIndex(["b", "c"], presenter: "a", target: "b"))
        XCTAssertNil(audienceDisplayIndex(["a", "b"], presenter: "a", target: "a"))
        XCTAssertNil(audienceDisplayIndex(["a", "b", "b"], presenter: "a", target: "b"))
        XCTAssertEqual(audienceDisplayIndex(["a", "b"], presenter: "a", target: "b"), 1)
        XCTAssertEqual(audienceDisplayIndex(["b", "a"], presenter: "a", target: "b"), 0)
        XCTAssertEqual(audienceDisplayIndex(["c", "b", "a"], presenter: "a", target: "b"), 1)
    }

    func testPreservesFullscreenStyleMask() {
        let current: NSWindow.StyleMask = [.titled, .resizable, .fullScreen]

        XCTAssertEqual(coverScreenStyleMask(from: current), current)
    }

    func testConvertsOrdinaryWindowToBorderless() {
        let current: NSWindow.StyleMask = [.titled, .closable, .resizable]

        XCTAssertEqual(coverScreenStyleMask(from: current), [.borderless])
    }
}
