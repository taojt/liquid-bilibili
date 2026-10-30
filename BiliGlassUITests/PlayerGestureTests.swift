import XCTest

/// 播放器手势的回归用例。
///
/// 长按加速、竖滑调亮度/音量这类「按住才生效 / 松手就回滚」的行为没有静态痕迹：
/// `press` 会阻塞到松手，松手瞬间状态已经恢复，屏幕上抓不到证据。
/// 所以 App 侧在诊断 HUD 里留了几个**只增不减 / 读回实际值**的格子：
/// `boost=`（加速触发次数）、`dim=` / `vol=`（写入后读回的亮度音量），
/// 用 `-debugDiag` 打开后就能在动作结束后读到它们。
final class PlayerGestureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - 长按加速

    func testLongPressAppliesTemporaryRate() {
        let app = launchDetail()

        XCTAssertTrue(app.staticTexts["boost=0"].exists, "长按前不该有加速记录")

        playAreaPoint(app).press(forDuration: 1.6)

        XCTAssertTrue(
            app.staticTexts["boost=1"].waitForExistence(timeout: 5),
            "长按播放区没有触发加速"
        )
        // 松手后「最近一次临时倍速」应该还留着 2，不能被恢复值 1 覆盖
        XCTAssertTrue(
            app.staticTexts["tmpRate=2"].waitForExistence(timeout: 5),
            "临时倍速没有被记录下来"
        )
    }

    // MARK: - 全屏竖滑

    func testFullscreenLeftDragAdjustsBrightness() {
        let app = launchFullscreen()

        XCTAssertTrue(app.staticTexts["dim=nil"].exists, "还没滑过不该有亮度记录")

        // 左半屏往下滑：亮度应该变小
        drag(app, from: CGVector(dx: 0.25, dy: 0.35), to: CGVector(dx: 0.25, dy: 0.85))

        let value = dimValue(app)
        XCTAssertNotNil(value, "左半屏竖滑没有调整亮度")
        XCTAssertLessThan(value ?? 1, 0.85, "下滑之后亮度应该明显下降")
    }

    func testFullscreenRightDragAdjustsVolume() {
        let app = launchFullscreen()

        XCTAssertTrue(app.staticTexts["vol=nil"].exists, "还没滑过不该有音量记录")

        // 右半屏往上滑：音量应该变大。
        // 模拟器起始音量是 0，往下滑读回值还是 0，证明不了任何事，所以往上滑
        drag(app, from: CGVector(dx: 0.78, dy: 0.85), to: CGVector(dx: 0.78, dy: 0.35))

        let value = volumeValue(app)
        XCTAssertNotNil(value, "右半屏竖滑没有调整音量")
        XCTAssertGreaterThan(value ?? 0, 0.2, "上滑之后音量应该明显变大")
    }

    // MARK: - 工具

    /// 打开详情页并等到播放器就绪（`倍速` 菜单出现即代表 isReady）
    private func launchDetail(fullscreen: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-debugBVID", "BV19wnQ6sExk", "-debugDiag", "YES"]
        if fullscreen { args += ["-debugFullscreen", "YES"] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(
            app.staticTexts["倍速"].waitForExistence(timeout: 25),
            "详情页播放器没有就绪"
        )
        // 让自动起播先跑起来：beginBoost 要求 isPlaying
        Thread.sleep(forTimeInterval: 2.5)
        return app
    }

    private func launchFullscreen() -> XCUIApplication {
        let app = launchDetail(fullscreen: true)
        // `fs=true ready=… play=…` 是一整行 Text，不能按下标精确匹配
        let predicate = NSPredicate(format: "label BEGINSWITH 'fs=true'")
        XCTAssertTrue(
            app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: 10),
            "没有进入全屏"
        )
        return app
    }

    /// 播放区左侧中部。避开中央的播放/±10 按钮和底部进度条，
    /// 否则按下去会变成点按钮而不是长按空白区
    private func playAreaPoint(_ app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.22))
    }

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(withNormalizedOffset: from)
            .press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: to),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
    }

    /// 从 `dim=0.42` 这样的诊断行里取出数值
    private func dimValue(_ app: XCUIApplication) -> Double? {
        numericValue(app, prefix: "dim=")
    }

    private func volumeValue(_ app: XCUIApplication) -> Double? {
        numericValue(app, prefix: "vol=")
    }

    private func numericValue(_ app: XCUIApplication, prefix: String) -> Double? {
        // 用正则而不是 `BEGINSWITH`，把 `dim=nil` 这种占位行排除掉，
        // 否则元素一直存在、`waitForExistence` 立刻返回，会读到还没更新的旧值
        let predicate = NSPredicate(format: "label MATCHES %@", prefix + "[0-9.]+")
        let element = app.staticTexts.matching(predicate).firstMatch
        guard element.waitForExistence(timeout: 5) else { return nil }
        return Double(element.label.replacingOccurrences(of: prefix, with: ""))
    }
}
