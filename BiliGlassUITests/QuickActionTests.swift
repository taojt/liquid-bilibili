import XCTest

/// 主屏快捷项（3D Touch 重按 / Haptic Touch 长按）的回归用例。
///
/// 这条链路跨进程：菜单由 SpringBoard 画，点击后才把 `UIApplicationShortcutItem`
/// 交给 App，所以只能开一个 SpringBoard 的 `XCUIApplication` 去戳图标，
/// 没法在 App 内部验证。
///
/// 最后一条 `testDebugShortcutRouting` 不碰 SpringBoard，只验证 App 侧的路由，
/// 在没法操作主屏的环境里（比如无人值守跑）仍然能覆盖落地逻辑。
final class QuickActionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - SpringBoard 真实路径

    func testQuickActionMenuShowsBothEntries() {
        longPressAppIcon()

        XCTAssertNotNil(quickActionItem("搜索"), "长按菜单里没有「搜索」")
        XCTAssertNotNil(quickActionItem("热门视频"), "长按菜单里没有「热门视频」")

        // 收起菜单，别把状态留给下一个用例
        XCUIDevice.shared.press(.home)
    }

    func testQuickActionHotLandsOnPopularTab() {
        longPressAppIcon(coldStart: true)
        guard let item = quickActionItem("热门视频") else {
            XCTFail("长按菜单里没有「热门视频」")
            return
        }
        item.tap()

        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "点快捷项后 App 没有起来")
        let popular = app.buttons["热门"].firstMatch
        XCTAssertTrue(popular.waitForExistence(timeout: 20), "没有回到首页")
        XCTAssertTrue(popular.isSelected, "落地后没有停在「热门」二级 Tab")
    }

    /// 同一件事，但 App 是被退到后台而不是杀掉：走的是 `performActionFor`，
    /// 和冷启动的 `UIScene.ConnectionOptions.shortcutItem` 是两条不同的通路
    func testQuickActionHotWhileInBackground() {
        longPressAppIcon(coldStart: false)
        guard let item = quickActionItem("热门视频") else {
            XCTFail("长按菜单里没有「热门视频」")
            return
        }
        item.tap()

        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "点快捷项后 App 没有回到前台")
        let popular = app.buttons["热门"].firstMatch
        XCTAssertTrue(popular.waitForExistence(timeout: 20), "没有回到首页")
        XCTAssertTrue(popular.isSelected, "落地后没有停在「热门」二级 Tab")
    }

    func testQuickActionSearchOpensSearchPage() {
        longPressAppIcon()
        guard let item = quickActionItem("搜索") else {
            XCTFail("长按菜单里没有「搜索」")
            return
        }
        item.tap()

        let app = XCUIApplication()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "点快捷项后 App 没有起来")
        XCTAssertTrue(
            app.staticTexts["bilibili 热搜"].waitForExistence(timeout: 20),
            "落地后没有打开搜索页"
        )
    }

    // MARK: - 只验证路由（不依赖主屏）

    func testDebugShortcutRouting() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugShortcut", "hot"]
        app.launch()

        let popular = app.buttons["热门"].firstMatch
        XCTAssertTrue(popular.waitForExistence(timeout: 20))
        XCTAssertTrue(popular.isSelected, "快捷项「热门视频」没有切到热门 Tab")
    }

    // MARK: - 工具

    /// 先起一次 App 保证它被装上、图标在主屏可见，再退回主屏长按图标。
    ///
    /// `coldStart` 决定点击快捷项时 App 是被杀掉（冷启动）还是留在后台（热启动），
    /// 这两条系统通路完全不同，需要分别覆盖。
    private func longPressAppIcon(coldStart: Bool = false) {
        let app = XCUIApplication()
        app.launch()
        if coldStart {
            app.terminate()
        } else {
            XCUIDevice.shared.press(.home)
        }
        // 在主屏按 Home 会回到第一页，按两次保险
        XCUIDevice.shared.press(.home)

        // 新装的 App 排在主屏后面几页，得翻页找。
        // 注意 `icons[...]` 在别的页上也会命中，只是 frame 为 0，所以要连着 frame 一起判断
        let board = springboard
        var icon = board.icons["bilibili"].firstMatch
        var page = 0
        while !(icon.exists && icon.frame.width > 0) && page < 5 {
            board.swipeLeft()
            page += 1
            icon = board.icons["bilibili"].firstMatch
        }

        XCTAssertTrue(
            icon.exists && icon.frame.width > 0,
            "翻遍 \(page) 页主屏都没找到 bilibili 图标"
        )
        // 1.5s 稳过长按阈值；太短会被判成普通点击，直接把 App 打开
        icon.press(forDuration: 1.5)
    }

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// 快捷菜单的元素类型在不同系统版本上不一致（buttons / cells / staticTexts 都见过），
    /// 逐个试，不要假设
    private func quickActionItem(_ title: String) -> XCUIElement? {
        let board = springboard
        for candidate in [board.buttons[title], board.cells[title], board.staticTexts[title]] {
            if candidate.waitForExistence(timeout: 5) { return candidate }
        }
        return nil
    }
}
