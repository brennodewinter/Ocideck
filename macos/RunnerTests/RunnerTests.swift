import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

  func testControlHIsFindReplaceBeforeTextInput() throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.control],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\u{8}",
      charactersIgnoringModifiers: "h",
      isARepeat: false,
      keyCode: 4))
    XCTAssertTrue(isFindReplaceShortcut(event))
  }

  func testBackspaceIsNotFindReplace() throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\u{7f}",
      charactersIgnoringModifiers: "\u{7f}",
      isARepeat: false,
      keyCode: 51))
    XCTAssertFalse(isFindReplaceShortcut(event))
  }

}
