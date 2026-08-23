import XCTest
@testable import DaisyTranslator

@MainActor
final class AppDelegateWindowToggleTests: XCTestCase {
    func testUnpinnedWindowOnlyHidesWhenVisibleAndKey() {
        XCTAssertFalse(AppDelegate.shouldHideMainWindow(
            isVisible: true,
            isKeyWindow: false,
            alwaysOnTop: false
        ))
        XCTAssertTrue(AppDelegate.shouldHideMainWindow(
            isVisible: true,
            isKeyWindow: true,
            alwaysOnTop: false
        ))
    }

    func testPinnedVisibleWindowHidesEvenWhenNotKey() {
        XCTAssertTrue(AppDelegate.shouldHideMainWindow(
            isVisible: true,
            isKeyWindow: false,
            alwaysOnTop: true
        ))
    }

    func testHiddenWindowAlwaysShows() {
        XCTAssertFalse(AppDelegate.shouldHideMainWindow(
            isVisible: false,
            isKeyWindow: true,
            alwaysOnTop: true
        ))
    }
}
