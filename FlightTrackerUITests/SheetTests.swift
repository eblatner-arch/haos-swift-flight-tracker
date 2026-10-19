import XCTest

/// Drives the app in the simulator against the stand-in add-on (tools/mock_addon.py): swipes the
/// sheet, opens a flight and an FAA program, and saves screenshots and measurements to SHOTS_DIR.
final class SheetTests: XCTestCase {
    var dir = ""
    var log: [String] = []

    override func setUp() {
        continueAfterFailure = true
        dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory()
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    func note(_ s: String) {
        log.append(s)
        try? log.joined(separator: "\n").write(toFile: dir + "/results.txt", atomically: true, encoding: .utf8)
    }

    func drag(_ app: XCUIApplication, from: CGFloat, to: CGFloat) {
        let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.05)
        sleep(1)
    }

    func testSheet() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-server", "http://localhost:8765/"]
        app.launch()
        let title = app.staticTexts["sheetTitle"]
        XCTAssert(title.waitForExistence(timeout: 30))
        sleep(4)
        let H = app.frame.height
        shot("u1-start")
        let y0 = title.frame.minY
        note("start: title at \(Int(y0)) of \(Int(H))")
        drag(app, from: 0.75, to: 0.15)        // swipe up on the list
        let y1 = title.frame.minY
        shot("u2-swiped-up")
        note("after swipe up: \(Int(y1)) (moved \(Int(y0 - y1)))")
        drag(app, from: 0.5, to: 0.3)          // at full: this should scroll the list
        shot("u3-scrolled")
        note("after scroll at full: title \(Int(title.frame.minY))")
        drag(app, from: 0.3, to: 0.6)          // scroll back to the top
        drag(app, from: 0.3, to: 0.85)         // then pull the sheet down
        let y2 = title.frame.minY
        shot("u4-pulled-down")
        note("after pull down: \(Int(y2))")
        drag(app, from: 0.92, to: 0.98)
        // open a flight
        let row = app.staticTexts["Nashville to Newark"].firstMatch
        if row.waitForExistence(timeout: 5) {
            drag(app, from: 0.88, to: 0.5)
            if row.isHittable { row.tap() } else { note("row not hittable") }
            sleep(4)
            shot("u5-flight")
            note("opened a flight")
        } else {
            note("no flight row found")
        }
        // the FAA program map
        let gdp = app.buttons.containing(NSPredicate(format: "label CONTAINS 'GDP'")).firstMatch
        if gdp.waitForExistence(timeout: 3) {
            gdp.tap()
            sleep(1)
            let map = app.buttons["Map ›"].firstMatch
            if map.waitForExistence(timeout: 3) { map.tap(); sleep(5); shot("u6-program"); note("opened the program map") }
            else { note("no Map › button") }
        } else {
            note("no GDP card")
        }
    }
}
