import Foundation

// MARK: - 通用包装

/// B站所有接口统一外壳：{ code, message, ttl, data }
struct BiliResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let data: T?
}

struct EmptyPayload: Decodable {}

// MARK: - 用户与统计

struct BiliOwner: Decodable, Hashable {
    let mid: Int
    let name: String
    let face: String
}

struct BiliStat: Decodable, Hashable {
    let view: Int?
    let danmaku: Int?
    let like: Int?
    let reply: Int?
    let favorite: Int?
    let coin: Int?
    let share: Int?
}

// MARK: - 视频条目

/// 热门/推荐流中的一条视频
struct BiliVideo: Decodable, Identifiable, Hashable {
    let aid: Int
    let bvid: String
    let cid: Int
    let pic: String
    let title: String
    let duration: Int
    let owner: BiliOwner
    let stat: BiliStat?

    var id: String { bvid }

    /// 推荐接口用 "id" 字段承载 bvid，这里做兼容
    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, pic, title, duration, owner, stat, id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aid = try c.decodeIfPresent(Int.self, forKey: .aid) ?? 0
        cid = try c.decodeIfPresent(Int.self, forKey: .cid) ?? 0
        pic = try c.decodeIfPresent(String.self, forKey: .pic) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        stat = try c.decodeIfPresent(BiliStat.self, forKey: .stat)
        // bvid 与 id 二选一
        if let b = try c.decodeIfPresent(String.self, forKey: .bvid) {
            bvid = b
        } else {
            bvid = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        }
        // owner 可能是对象，推荐流里也可能缺失
        if let o = try c.decodeIfPresent(BiliOwner.self, forKey: .owner) {
            owner = o
        } else {
            owner = BiliOwner(mid: 0, name: "未知UP主", face: "")
        }
    }
}

struct PopularData: Decodable {
    let list: [BiliVideo]
    let noMore: Bool?

    enum CodingKeys: String, CodingKey {
        case list
        case noMore = "no_more"
    }
}

// MARK: - 视频详情

struct VideoPage: Decodable, Hashable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
}

struct VideoDetail: Decodable {
    let aid: Int
    let bvid: String
    let cid: Int
    let title: String
    let pic: String
    let desc: String?
    let owner: BiliOwner
    let stat: BiliStat?
    let pages: [VideoPage]?
}

// MARK: - 播放地址（DASH）

struct DashSegment: Decodable, Identifiable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]?
    let bandwidth: Int?
    let codecid: Int?
    let width: Int?
    let height: Int?
    let frameRate: String?

    /// 兼容 baseUrl / base_url 两种写法
    enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecid, width, height
        case baseUrl, base_url
        case backupUrl, backup_url
        case frameRate, frame_rate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        bandwidth = try c.decodeIfPresent(Int.self, forKey: .bandwidth)
        codecid = try c.decodeIfPresent(Int.self, forKey: .codecid)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        frameRate = try c.decodeIfPresent(String.self, forKey: .frameRate)
            ?? c.decodeIfPresent(String.self, forKey: .frame_rate)
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl)
            ?? c.decode(String.self, forKey: .base_url)
        backupUrl = try c.decodeIfPresent([String].self, forKey: .backupUrl)
            ?? c.decodeIfPresent([String].self, forKey: .backup_url)
    }
}

struct DashPayload: Decodable {
    let video: [DashSegment]
    let audio: [DashSegment]?
}

/// durl：音视频合一的单文件 MP4。fnval=1 时返回，
/// 优点是 AVFoundation 原生支持、随机访问可靠，缺点是画质档位有限。
struct DurlSegment: Decodable {
    let order: Int?
    let url: String
    let length: Int?
    let size: Int?
}

struct PlayURLData: Decodable {
    let quality: Int?
    let format: String?
    let dash: DashPayload?
    let durl: [DurlSegment]?
}

// MARK: - 用户信息（同时携带 WBI 密钥）

struct WbiImg: Decodable {
    let imgUrl: String
    let subUrl: String

    enum CodingKeys: String, CodingKey {
        case imgUrl = "img_url"
        case subUrl = "sub_url"
    }
}

struct NavData: Decodable {
    /// 未登录时接口返回 code -101，data 里依然带 wbi_img，因此 isLogin 必须可解，
    /// 不能因为缺失就整体解码失败。
    let isLogin: Bool?
    let uname: String?
    let face: String?
    let mid: Int?
    let wbiImg: WbiImg?

    enum CodingKeys: String, CodingKey {
        case isLogin, uname, face, mid
        case wbiImg = "wbi_img"
    }

    var loggedIn: Bool { isLogin == true }
}

// MARK: - 扫码登录

struct QRGenerateData: Decodable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }
}

struct QRPollData: Decodable {
    let url: String?
    let refreshToken: String?
    let timestamp: Int?
    let code: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case url, timestamp, code, message
        case refreshToken = "refresh_token"
    }
}

/// 扫码状态，把 B站的数字状态码翻译成可读语义
enum QRStatus: Equatable {
    case waiting          // 86101 未扫码
    case scanned          // 86090 已扫码待确认
    case expired          // 86038 二维码失效
    case success          // 0     登录成功
    case failure(String)

    init(code: Int, message: String? = nil) {
        switch code {
        case 0: self = .success
        case 86101: self = .waiting
        case 86090: self = .scanned
        case 86038: self = .expired
        default: self = .failure(message ?? "未知状态 \(code)")
        }
    }

    var hint: String {
        switch self {
        case .waiting: return "请使用哔哩哔哩 App 扫码"
        case .scanned: return "已扫码，请在手机上确认"
        case .expired: return "二维码已失效，点击刷新"
        case .success: return "登录成功"
        case .failure(let m): return m
        }
    }
}

// MARK: - 画质

/// DASH 的 quality id 与中文名对照
enum BiliQuality {
    static func name(for id: Int) -> String {
        switch id {
        case 127: return "8K 超清"
        case 126: return "杜比视界"
        case 125: return "HDR 真彩"
        case 120: return "4K 超清"
        case 116: return "1080P60"
        case 112: return "1080P+"
        case 80: return "1080P 高清"
        case 74: return "720P60"
        case 64: return "720P 高清"
        case 32: return "480P 清晰"
        case 16: return "360P 流畅"
        default: return "画质 \(id)"
        }
    }

    static func badge(for id: Int) -> String {
        switch id {
        case 127: return "8K"
        case 126: return "杜比"
        case 125: return "HDR"
        case 120: return "4K"
        case 116: return "60帧"
        case 112: return "1080+"
        case 80: return "1080P"
        case 74: return "720P60"
        case 64: return "720P"
        case 32: return "480P"
        default: return "360P"
        }
    }
}
