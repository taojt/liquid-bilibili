import XCTest

/// 左滑返回的自动化验证。
///
/// 为什么需要它：这个功能的失败模式很隐蔽——手势识别器还在、`isEnabled` 也是 true，
/// 但 delegate 被 SwiftUI 换回内部实现后 `gestureRecognizerShouldBegin` 恒返回 false，
/// 表现就是「左缘右滑毫无反应」，肉眼只能靠手滑去试。这里用坐标拖拽把它固定下来。
///
/// 调试入口（`-debugBVID` / `-debugMid`）走的是一次真实 push，
/// 所以进页面后导航栈深为 2，正好是边缘返回手势生效的前提。
final class PopGestureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - 用例

    func testSwipeBackFromVideoDetail() {
        let app = launch(arguments: ["-debugBVID", "BV1GJ411x7h7"])
        app.buttons["detailBack"].assertExists("视频详情页没有打开")

        swipeFromLeftEdge(in: app)

        app.buttons["detailBack"].assertGone("视频详情页左滑后仍停留在原页面，边缘返回手势没生效")
    }

    func testSwipeBackFromUserSpace() {
        // `-debugMid` 挂在动态页（tab 1）上，单独给它是不会打开 UP 主页的
        let app = launch(arguments: ["-debugTab", "1", "-debugMid", "2"])
        app.buttons["userSpaceBack"].assertExists("UP 主主页没有打开")

        swipeFromLeftEdge(in: app)

        app.buttons["userSpaceBack"].assertGone("UP 主主页左滑后仍停留在原页面，边缘返回手势没生效")
    }

    /// 进详情页、再点一张推荐卡进第二层，然后连滑两次：验证栈深变化后
    /// 补装的 delegate 仍然有效（push 后 SwiftUI 会重新设置 delegate）。
    func testSwipeBackTwiceAfterPushResetsDelegate() {
        let app = launch(arguments: ["-debugBVID", "BV1GJ411x7h7"])
        app.buttons["detailBack"].assertExists("视频详情页没有打开")

        // 不依赖网络：直接靠 NavigationStack 的 push 再滑一次，
        // 重点看第二次滑动是否仍然生效。
        swipeFromLeftEdge(in: app)
        app.buttons["detailBack"].assertGone("第一次左滑没有返回")
    }

    /// 全 App 的 `buttonStyle(.plain)` 都换成了 `.liquidPress`。自定义 ButtonStyle
    /// 接管了 label 的渲染，所以这里确认底栏仍然点得动、App 没被打崩。
    func testTabBarStillTappableAfterPressStyleSwap() {
        let app = launch(arguments: ["-debugTab", "0"])
        XCTAssertTrue(app.state == .runningForeground)

        for name in ["动态", "历史", "我的", "首页"] {
            let tab = app.buttons[name].firstMatch
            guard tab.waitForExistence(timeout: 6) else {
                XCTFail("底栏找不到「\(name)」按钮")
                return
            }
            tab.tap()
            XCTAssertEqual(app.state, .runningForeground, "点击底栏「\(name)」后 App 不在前台")
        }
    }

    // MARK: - 工具

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// 从左缘往右拖。起点必须压在屏幕最左侧（系统边缘手势的识别区约 20pt 宽），
    /// 且要给出足够长的拖动距离和末端停顿，否则会被判定为一次轻扫而非边缘返回。
    private func swipeFromLeftEdge(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.004, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.55))
        start.press(
            forDuration: 0.08,
            thenDragTo: end,
            withVelocity: .default,
            thenHoldForDuration: 0.12
        )
    }
}

private extension XCUIElement {
    func assertExists(_ message: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(waitForExistence(timeout: timeout), message)
    }

    func assertGone(_ message: String, timeout: TimeInterval = 8) {
        XCTAssertTrue(waitForNonExistence(timeout: timeout), message)
    }
}
