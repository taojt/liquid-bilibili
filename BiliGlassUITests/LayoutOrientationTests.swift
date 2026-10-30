import XCTest

/// 横屏 / 多 Tab 的布局回归。
///
/// 这两个问题都是真机上暴露、模拟器不会自己出现的：
/// 1. 横屏下列数写死 4 列，封面被拉得过大；
/// 2. 底栏闸门用「当前选中 Tab」登记，页面重建后会把别的 Tab 的底栏钉死。
///
/// 断言用截图附件而不是元素查询：布局问题（列数、留白、底栏位置）
/// 没法用 `exists` 表达，只能人眼看图。
final class LayoutOrientationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// 横屏下首页网格与底栏，以及切 Tab 后底栏是否还在
    func testLandscapeAndTabBarVisibility() {
        let app = XCUIApplication()
        app.launchArguments = ["-debugTab", "0"]
        app.launch()
        // 首页要等接口回来才有内容；这里不锚定具体元素——
        // 二级 Tab 的文字被 Button 合并后不一定作为独立 staticText 暴露
        Thread.sleep(forTimeInterval: 14)
        attach(app, name: "01-竖屏-首页")

        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 5)
        attach(app, name: "02-横屏-首页")

        // 依次切四个 Tab，每切一次都截一张：
        // 底栏如果被闸门钉死，切换之后就会消失
        let titles = ["动态", "历史", "我的", "首页"]
        for (i, title) in titles.enumerated() {
            let button = app.buttons[title].firstMatch
            if button.waitForExistence(timeout: 6) {
                button.tap()
            } else {
                XCTFail("横屏下找不到底栏按钮「\(title)」")
            }
            Thread.sleep(forTimeInterval: 4)
            attach(app, name: "0\(i + 3)-横屏-切到\(title)")
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
