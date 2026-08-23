import XCTest
@testable import DaisyTranslator

@MainActor
final class AppDelegateWindowToggleTests: XCTestCase {
    func testUnpinnedWindowUsesActualWindowOrder() {
        XCTAssertEqual(AppDelegate.mainWindowMenuAction(
            isVisible: true,
            alwaysOnTop: false,
            isFrontmost: false
        ), .show)
        XCTAssertEqual(AppDelegate.mainWindowMenuAction(
            isVisible: true,
            alwaysOnTop: false,
            isFrontmost: true
        ), .hide)
    }

    func testPinnedVisibleWindowHidesRegardlessOfWindowOrder() {
        XCTAssertEqual(AppDelegate.mainWindowMenuAction(
            isVisible: true,
            alwaysOnTop: true,
            isFrontmost: false
        ), .hide)
    }

    func testHiddenWindowAlwaysShows() {
        XCTAssertEqual(AppDelegate.mainWindowMenuAction(
            isVisible: false,
            alwaysOnTop: true,
            isFrontmost: true
        ), .show)
    }

    func testUnavailableWindowOrderUsesNeutralToggleAction() {
        XCTAssertEqual(AppDelegate.mainWindowMenuAction(
            isVisible: true,
            alwaysOnTop: false,
            isFrontmost: nil
        ), .toggle)
    }
}
