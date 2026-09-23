import XCTest

/// Drives the real app through the keyboard, the way a person would. Each test launches with
/// `-uiTesting`, so it works on a throwaway file and never touches the real scratchpad.
final class JotsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-ApplePersistenceIgnoreState", "YES"]
        if reset {
            app.launchArguments.append("-uiTestingReset")
        }
        app.launch()
        return app
    }

    @MainActor
    private func editor(in app: XCUIApplication) -> XCUIElement {
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the editor should appear")
        return editor
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWritingMarkdown() throws {
        let app = launch()
        let editor = editor(in: app)
        editor.click()

        editor.typeText("# Groceries\n")
        // Return continues a task list; Return on the empty item ends it, and one more adds a
        // blank line.
        editor.typeText("- [ ] milk\neggs\n\n\n")
        editor.typeText("Some ")
        // ⌘B with nothing selected inserts a pair of markers around the caret.
        editor.typeKey("b", modifierFlags: .command)
        editor.typeText("bold")
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeText(" text and `code`.\n\n> a quote\n\n\n```\nlet x = 1\n```\n")

        XCTAssertEqual(
            editor.value as? String,
            "# Groceries\n- [ ] milk\n- [ ] eggs\n\nSome **bold** text and `code`.\n\n> a quote\n\n```\nlet x = 1\n```\n"
        )
        attachScreenshot(of: app, named: "Rendered Markdown")

        // Mark as Done on the "milk" line, the second line.
        editor.typeKey(.upArrow, modifierFlags: .command)
        editor.typeKey(.downArrow, modifierFlags: [])
        editor.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertTrue((editor.value as? String ?? "").contains("- [x] milk"))
        attachScreenshot(of: app, named: "Task checked")
    }

    @MainActor
    func testTextSurvivesQuitAndRelaunch() throws {
        var app = launch()
        editor(in: app).click()
        editor(in: app).typeText("remember this\n- [ ] and this")
        // Quit normally (not a kill) so the app gets to save on the way out.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))

        app = launch(reset: false)
        XCTAssertEqual(editor(in: app).value as? String, "remember this\n- [ ] and this")
        attachScreenshot(of: app, named: "After relaunch")
    }
}
