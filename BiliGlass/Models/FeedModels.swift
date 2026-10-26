import Foundation

// MARK: - 统一的卡片展示模型

/// 首页/历史/收藏/动态各接口返回结构都不同，
/// 统一收敛成这个模型供网格卡片使用，避免每个页面各写一套卡片。
struct VideoCellModel: Identifiable, Hashable {
    let id: String            // bvid
    let title: String
    let cover: String
    let duration: Int
    let upName: String?
    let upFace: String?
    let viewCount: Int?
    let danmakuCount: Int?
    let publishedAt: Int?     // 秒级时间戳
    let progress: Int?        // 历史记录的观看进度（秒）

    init(
        id: String,
        title: String,
        cover: String,
        duration: Int = 0,
        upName: String? = nil,
        upFace: String? = nil,
        viewCount: Int? = nil,
        danmakuCount: Int? = nil,
        publishedAt: Int? = nil,
        progress: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.cover = cover
        self.duration = duration
        self.upName = upName
        self.upFace = upFace
        self.viewCount = viewCount
        self.danmakuCount = danmakuCount
        self.publishedAt = publishedAt
        self.progress = progress
    }

    /// 从首页各流（热门/推荐/相关推荐）的通用视频结构转换
    init(video: BiliVideo, publishedAt: Int? = nil) {
        self.id = video.bvid
        self.title = video.title
        self.cover = video.pic
        self.duration = video.duration
        self.upName = video.owner.name
        self.upFace = video.owner.face
        self.viewCount = video.stat?.view
        self.danmakuCount = video.stat?.danmaku
        self.publishedAt = publishedAt
        self.progress = nil
    }

    /// 进度百分比，用于封面上画续播条
    var progressRatio: Double? {
        guard let progress, progress > 0, duration > 0 else { return nil }
        return min(1, Double(progress) / Double(duration))
    }

    /// 补上 UP 主信息（UP 主页的投稿列表接口本身不带这个字段）
    func withUp(name: String?, face: String?) -> VideoCellModel {
        VideoCellModel(
            id: id,
            title: title,
            cover: cover,
            duration: duration,
            upName: name ?? upName,
            upFace: face ?? upFace,
            viewCount: viewCount,
            danmakuCount: danmakuCount,
            publishedAt: publishedAt,
            progress: progress
        )
    }
}

// MARK: - 推荐流

struct RecommendData: Decodable {
    let item: [BiliVideo]?
}

// MARK: - 历史记录

struct HistoryData: Decodable {
    let list: [HistoryItem]?
    let cursor: HistoryCursor?
}

struct HistoryCursor: Decodable {
    let max: Int?
    let viewAt: Int?
    let business: String?

    enum CodingKeys: String, CodingKey {
        case max, business
        case viewAt = "view_at"
    }
}

struct HistoryItem: Decodable {
    let title: String?
    let cover: String?
    let history: HistoryRef?
    let videos: Int?
    let authorName: String?
    let authorFace: String?
    let viewAt: Int?
    let duration: Int?
    let progress: Int?
    let business: String?

    enum CodingKeys: String, CodingKey {
        case title, cover, history, videos, duration, progress, business
        case authorName = "author_name"
        case authorFace = "author_face"
        case viewAt = "view_at"
    }
}

struct HistoryRef: Decodable {
    let oid: Int?
    let bvid: String?
    let cid: Int?
    let page: Int?
    let business: String?
}

// MARK: - 收藏夹

struct FavFolderListData: Decodable {
    let list: [FavFolder]?
}

struct FavFolder: Decodable, Identifiable {
    let id: Int
    let fid: Int
    let mid: Int
    let title: String
    let mediaCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, fid, mid, title
        case mediaCount = "media_count"
    }
}

struct FavResourceData: Decodable {
    let medias: [FavMedia]?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case medias
        case hasMore = "has_more"
    }
}

struct FavMedia: Decodable {
    let id: Int
    let bvid: String?
    let title: String?
    let cover: String?
    let duration: Int?
    let upper: FavUpper?
    let cntInfo: FavCntInfo?

    enum CodingKeys: String, CodingKey {
        case id, bvid, title, cover, duration, upper
        case cntInfo = "cnt_info"
    }
}

struct FavUpper: Decodable {
    let mid: Int?
    let name: String?
    let face: String?
}

struct FavCntInfo: Decodable {
    let collect: Int?
    let play: Int?
    let danmaku: Int?
}

// MARK: - 直播

struct LiveListData: Decodable {
    let list: [LiveRoom]?
}

struct LiveRoom: Decodable, Identifiable {
    let roomid: Int
    let title: String?
    let cover: String?
    let uname: String?
    let face: String?
    let online: Int?
    let areaName: String?

    var id: Int { roomid }

    enum CodingKeys: String, CodingKey {
        case roomid, title, cover, uname, face, online
        case areaName = "area_name"
    }
}

/// 直播拉流地址。durl 里给的是 HLS（m3u8）播放列表。
struct LivePlayData: Decodable {
    let currentQuality: Int?
    let durl: [DurlSegment]?

    enum CodingKeys: String, CodingKey {
        case currentQuality = "current_quality"
        case durl
    }
}

// MARK: - 设备指纹

struct FingerprintData: Decodable {
    let b3: String?
    let b4: String?

    enum CodingKeys: String, CodingKey {
        case b3 = "b_3"
        case b4 = "b_4"
    }
}
