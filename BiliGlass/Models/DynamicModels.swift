import Foundation

// MARK: - 关注动态

/// `polymer/web-dynamic` 系列接口的返回。
/// 三层模块嵌套（module_author / module_dynamic / module_stat），
/// 字段几乎全是可空的，因此这里一律用可选类型，缺字段不至于整体解码失败。
struct DynFeedData: Decodable {
    let items: [DynItem]?
    let offset: String?
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([DynItem].self, forKey: .items)) ?? nil
        offset = c.flexibleString(.offset)
        hasMore = c.flexibleBool(.hasMore)
    }
}

struct DynItem: Decodable {
    let idStr: String?
    let type: String?
    let modules: DynModules?

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case type
        case modules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        idStr = c.flexibleString(.idStr)
        type = c.flexibleString(.type)
        modules = (try? c.decodeIfPresent(DynModules.self, forKey: .modules)) ?? nil
    }
}

struct DynModules: Decodable {
    let author: DynAuthor?
    let dynamic: DynDynamic?
    let stat: DynStat?

    enum CodingKeys: String, CodingKey {
        case author = "module_author"
        case dynamic = "module_dynamic"
        case stat = "module_stat"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        author = (try? c.decodeIfPresent(DynAuthor.self, forKey: .author)) ?? nil
        dynamic = (try? c.decodeIfPresent(DynDynamic.self, forKey: .dynamic)) ?? nil
        stat = (try? c.decodeIfPresent(DynStat.self, forKey: .stat)) ?? nil
    }
}

struct DynAuthor: Decodable {
    let mid: Int?
    let name: String?
    let face: String?
    let pubTs: Int?
    /// 「投稿了视频」「发布了动态」
    let pubAction: String?

    enum CodingKeys: String, CodingKey {
        case mid, name, face
        case pubTs = "pub_ts"
        case pubAction = "pub_action"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // pub_ts 实测是字符串（"1783878096"），mid 是数字，两个都要容忍
        mid = c.flexibleInt(.mid)
        name = c.flexibleString(.name)
        face = c.flexibleString(.face)
        pubTs = c.flexibleInt(.pubTs)
        pubAction = c.flexibleString(.pubAction)
    }
}

struct DynDynamic: Decodable {
    let desc: DynDesc?
    let major: DynMajor?

    enum CodingKeys: String, CodingKey {
        case desc, major
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        desc = (try? c.decodeIfPresent(DynDesc.self, forKey: .desc)) ?? nil
        major = (try? c.decodeIfPresent(DynMajor.self, forKey: .major)) ?? nil
    }
}

struct DynDesc: Decodable {
    let text: String?

    enum CodingKeys: String, CodingKey { case text }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.flexibleString(.text)
    }
}

struct DynMajor: Decodable {
    let type: String?
    let archive: DynArchive?

    enum CodingKeys: String, CodingKey { case type, archive }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.flexibleString(.type)
        archive = (try? c.decodeIfPresent(DynArchive.self, forKey: .archive)) ?? nil
    }
}

struct DynArchive: Decodable {
    /// 注意：动态接口里 aid 是字符串，不是数字
    let aid: String?
    let bvid: String?
    let title: String?
    let cover: String?
    let desc: String?
    let durationText: String?
    let stat: DynArchiveStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, cover, desc, stat
        case durationText = "duration_text"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aid = c.flexibleString(.aid)
        bvid = c.flexibleString(.bvid)
        title = c.flexibleString(.title)
        cover = c.flexibleString(.cover)
        desc = c.flexibleString(.desc)
        durationText = c.flexibleString(.durationText)
        stat = (try? c.decodeIfPresent(DynArchiveStat.self, forKey: .stat)) ?? nil
    }

    /// "12:34" -> 754
    var durationSeconds: Int {
        guard let durationText else { return 0 }
        let parts = durationText.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }
}

struct DynArchiveStat: Decodable {
    let play: String?
    let danmaku: String?

    enum CodingKeys: String, CodingKey { case play, danmaku }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        play = c.flexibleString(.play)
        danmaku = c.flexibleString(.danmaku)
    }
}

struct DynStat: Decodable {
    let comment: DynCount?
    let forward: DynCount?
    let like: DynCount?

    enum CodingKeys: String, CodingKey { case comment, forward, like }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comment = (try? c.decodeIfPresent(DynCount.self, forKey: .comment)) ?? nil
        forward = (try? c.decodeIfPresent(DynCount.self, forKey: .forward)) ?? nil
        like = (try? c.decodeIfPresent(DynCount.self, forKey: .like)) ?? nil
    }
}

struct DynCount: Decodable {
    let count: Int?

    enum CodingKeys: String, CodingKey { case count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = c.flexibleInt(.count)
    }
}

// MARK: - 时间线展示模型

/// 动态时间线的一条。
///
/// 把三层嵌套模块压平成视图直接能用的结构，同时也兼容「只有转发/纯文字」的条目
/// （archive 为空时只渲染正文）。
struct DynamicCell: Identifiable, Hashable {
    let id: String
    let authorMid: Int?
    let authorName: String
    let authorFace: String?
    let pubTs: Int?
    let action: String?
    let text: String?

    let bvid: String?
    let title: String?
    let cover: String?
    let duration: Int
    let playText: String?
    let danmakuText: String?

    let likeCount: Int?
    let commentCount: Int?
    let forwardCount: Int?

    init?(item: DynItem) {
        guard let id = item.idStr, !id.isEmpty else { return nil }
        let author = item.modules?.author
        let dynamic = item.modules?.dynamic
        let archive = dynamic?.major?.archive
        let stat = item.modules?.stat

        // 既没有投稿也没有正文的条目（比如直播预约卡）直接丢弃
        let text = dynamic?.desc?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasArchive = !(archive?.bvid ?? "").isEmpty
        let hasText = !(text ?? "").isEmpty
        guard hasArchive || hasText else { return nil }

        self.id = id
        authorMid = author?.mid
        authorName = author?.name ?? "未知UP主"
        authorFace = author?.face
        pubTs = author?.pubTs
        action = author?.pubAction
        self.text = hasText ? text : nil
        bvid = hasArchive ? archive?.bvid : nil
        title = archive?.title
        cover = archive?.cover
        duration = archive?.durationSeconds ?? 0
        playText = archive?.stat?.play
        danmakuText = archive?.stat?.danmaku
        likeCount = stat?.like?.count
        commentCount = stat?.comment?.count
        forwardCount = stat?.forward?.count
    }

    /// 相对时间：刚刚 / 12分钟前 / 3小时前 / 昨天 / 09-20
    var publishedText: String {
        guard let pubTs, pubTs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(pubTs))
        let seconds = Date().timeIntervalSince(date)
        switch seconds {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(seconds / 60))分钟前"
        case ..<86_400: return "\(Int(seconds / 3600))小时前"
        case ..<(86_400 * 2): return "昨天"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: date)
        }
    }
}

// MARK: - 数值解析

extension String {
    /// 动态接口里的播放量/弹幕数是字符串，可能是 "7997344" 也可能是 "799.7万"
    var biliCountValue: Int? {
        if let plain = Int(self) { return plain }
        var text = self.trimmingCharacters(in: .whitespaces)
        var scale = 1.0
        if text.hasSuffix("亿") {
            scale = 100_000_000
            text.removeLast()
        } else if text.hasSuffix("万") {
            scale = 10_000
            text.removeLast()
        }
        guard let base = Double(text) else { return nil }
        return Int(base * scale)
    }
}
