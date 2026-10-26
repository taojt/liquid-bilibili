import Foundation

// MARK: - 直播间信息

/// `room/v1/Room/room_init`：短号换成真实房间号，顺带拿到开播状态。
struct RoomInitData: Decodable {
    let roomID: Int?
    let shortID: Int?
    let liveStatus: Int?

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case shortID = "short_id"
        case liveStatus = "live_status"
    }
}

/// `xlive/web-room/v1/index/getDanmuInfo`：弹幕服务器地址与鉴权 token。
/// 这个接口现在必须 WBI 签名，未签名直接 -352。
struct DanmuInfoData: Decodable {
    let token: String?
    let hostList: [DanmuHost]?

    enum CodingKeys: String, CodingKey {
        case token
        case hostList = "host_list"
    }
}

struct DanmuHost: Decodable {
    let host: String?
    let wssPort: Int?

    enum CodingKeys: String, CodingKey {
        case host
        case wssPort = "wss_port"
    }
}

// MARK: - 实时弹幕

/// 直播弹幕。与点播弹幕的区别在于**没有时间轴**——消息是推过来的，
/// 时间只有一个含义：相对于本次连接建立时刻过了多少秒。
struct LiveBullet: Identifiable, Hashable {
    let id: Int
    let text: String
    /// 1/2/3 滚动，4 底部固定，5 顶部固定
    let mode: Int
    /// 0xRRGGBB
    let colorValue: Int
    let userName: String?
    /// 收到这条弹幕时，本次连接已经建立了多少秒
    let time: Double

    /// 转成点播弹幕层能吃的模型，复用同一套轨道调度与绘制
    var item: DanmakuItem {
        DanmakuItem(id: id, text: text, time: time, mode: mode, colorValue: colorValue)
    }
}
