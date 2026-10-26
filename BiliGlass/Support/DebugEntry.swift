import Foundation

/// 调试入口。
///
/// 模拟器里没法脚本化点击，因此提供一个只读 UserDefaults 的直达入口，
/// 便于用 `simctl spawn booted defaults write com.biliglass.app debugTab -int 2`
/// 直接落到某个页面做回归验证。正式使用时这些键不存在，行为与正常启动一致。
enum DebugEntry {
    /// 底部 Tab：0 首页 / 1 动态 / 2 历史 / 3 我的
    static var tab: Int? {
        guard let value = intValue("debugTab") else { return nil }
        return (0...3).contains(value) ? value : nil
    }

    /// 首页二级 Tab：0 推荐 / 1 关注 / 2 热门 / 3 直播
    static var segment: Int? {
        guard let value = intValue("debugSegment") else { return nil }
        return (0...3).contains(value) ? value : nil
    }

    /// 直接打开某个视频详情
    static var bvid: String? {
        guard let value = UserDefaults.standard.string(forKey: "debugBVID"), !value.isEmpty else { return nil }
        return value
    }

    /// 直接打开某个 UP 主主页
    static var mid: Int? {
        guard let value = intValue("debugMid"), value > 0 else { return nil }
        return value
    }

    /// 直接打开「我的主页」（可指定 mid 便于未登录时验证）
    static var mySpaceMid: Int? {
        guard let value = intValue("debugMySpace"), value > 0 else { return nil }
        return value
    }

    /// 我的主页默认落在哪一段：history / favorites / likes
    static var mySpaceTab: String? {
        UserDefaults.standard.string(forKey: "debugMySpaceTab")
    }

    /// 打开播放页后立刻弹出弹幕设置
    static var danmakuSettings: Bool {
        UserDefaults.standard.bool(forKey: "debugDanmakuSettings")
    }

    /// 直接指定弹幕显示区域：full / top / bottom
    static var danmakuArea: String? {
        UserDefaults.standard.string(forKey: "debugDanmakuArea")
    }

    /// 直接指定弹幕不透明度（0.2 ~ 1.0）
    static var danmakuOpacity: Double? {
        guard let value = intValue("debugDanmakuOpacity") else { return nil }
        return Double(value) / 100.0
    }

    /// 在弹幕层左上角打印轨道/尺寸诊断信息
    static var danmakuInfo: Bool {
        UserDefaults.standard.bool(forKey: "debugDanmakuInfo")
    }

    /// 详情页打开后自动滚到评论区
    static var comment: Bool {
        UserDefaults.standard.bool(forKey: "debugComment")
    }

    /// 详情页打开后自动播一次一键三连动效（不调接口，未登录也能截图）
    static var tripleBurst: Bool {
        UserDefaults.standard.bool(forKey: "debugTripleBurst")
    }

    /// 评论区出现时直接弹出输入框（未登录也弹，用于验证输入框布局）
    static var commentComposer: Bool {
        UserDefaults.standard.bool(forKey: "debugCommentComposer")
    }

    /// 直接打开某个直播间（跳过直播列表）
    static var liveRoom: Int? {
        guard let value = intValue("debugLiveRoom"), value > 0 else { return nil }
        return value
    }

    /// 详情页启动后立刻进全屏，用于验证转屏
    static var fullscreen: Bool {
        UserDefaults.standard.bool(forKey: "debugFullscreen")
    }

    /// 首页启动后直接停在顶栏收起态（模拟器里没法脚本化滑动，用于截图验证）
    static var collapsed: Bool {
        UserDefaults.standard.bool(forKey: "debugCollapsed")
    }

    /// 列表首屏直接滚到中段，用于复现「滚动后」的底部状态
    static var scroll: Bool {
        UserDefaults.standard.bool(forKey: "debugScroll")
    }

    /// 首页启动后直接推进搜索页
    static var search: Bool {
        UserDefaults.standard.bool(forKey: "debugSearch")
    }

    /// 指定播放倍速，用于验证倍速链路
    static var rate: Float? {
        let value = UserDefaults.standard.double(forKey: "debugRate")
        return value > 0 ? Float(value) : nil
    }

    /// 预填搜索词并直接发起搜索，用于验证搜索接口的 WBI 签名
    static var keyword: String? {
        guard let value = UserDefaults.standard.string(forKey: "debugKeyword"),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// 读整数型调试键。
    ///
    /// 真机上没法 `defaults write`，只能用 `devicectl ... launch app -debugTab 1`
    /// 走 NSArgumentDomain。参数域里数字**按字符串**存，`as? Int` 会失败，
    /// 因此这里先试 Int，再退回字符串解析。
    private static func intValue(_ key: String) -> Int? {
        if let number = UserDefaults.standard.object(forKey: key) as? Int {
            return number
        }
        if let text = UserDefaults.standard.object(forKey: key) as? String {
            return Int(text)
        }
        return nil
    }

    /// 清空，避免每次启动都被带到调试页
    static func clear() {
        let defaults = UserDefaults.standard
        for key in [
            "debugTab", "debugSegment", "debugBVID", "debugFullscreen",
            "debugSearch", "debugMid", "debugLiveRoom", "debugAppearance",
            "debugMySpace", "debugMySpaceTab", "debugDanmakuSettings",
            "debugDanmakuArea", "debugDanmakuOpacity", "debugDanmakuInfo",
            "debugComment", "debugTripleBurst", "debugKeyword", "debugRate",
            "debugCommentComposer", "debugCollapsed", "debugScroll"
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// navigationDestination(item:) 需要一个 Identifiable 载体
struct BVIDTarget: Identifiable, Hashable {
    let id: String
}

/// UP 主 mid 的载体
struct MIDTarget: Identifiable, Hashable {
    let id: Int
}
