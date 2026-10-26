import Foundation

// MARK: - 搜索结果

struct SearchData: Decodable {
    let result: [SearchVideo]?
    let numPages: Int?
    let numResults: Int?

    enum CodingKeys: String, CodingKey {
        case result
        case numPages = "numPages"
        case numResults = "numResults"
    }
}

/// 搜索结果里的一条视频。
///
/// 注意 `title` 带 `<em class="keyword">` 高亮标签、`duration` 是 "12:34" 这种字符串，
/// 都要在转换层清洗掉，不要把脏数据带进展示层。
struct SearchVideo: Decodable {
    let bvid: String?
    let title: String?
    let pic: String?
    let author: String?
    let play: Int?
    let videoReview: Int?
    let duration: String?
    let pubdate: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, title, pic, author, play, duration, pubdate
        case videoReview = "video_review"
    }

    var durationSeconds: Int {
        guard let duration else { return 0 }
        let parts = duration.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }

    var cleanTitle: String {
        (title ?? "").strippingHTML
    }
}

// MARK: - 热搜

struct SearchSquareData: Decodable {
    let trending: SearchTrending?
}

struct SearchTrending: Decodable {
    let title: String?
    let list: [SearchHotWord]?
}

struct SearchHotWord: Decodable, Identifiable {
    let keyword: String?
    let showName: String?
    let heatScore: Int?

    var id: String { keyword ?? UUID().uuidString }
    var display: String { showName ?? keyword ?? "" }

    enum CodingKeys: String, CodingKey {
        case keyword
        case showName = "show_name"
        case heatScore = "heat_score"
    }
}

// MARK: - 清洗

extension String {
    /// 去掉搜索结果标题里的高亮标签并还原 HTML 实体
    var strippingHTML: String {
        var text = replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&nbsp;": " "
        ]
        for (key, value) in entities {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SearchVideo {
    /// 搜索结果的字段名和首页流不一致，转成统一的卡片模型
    var cellModel: VideoCellModel? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoCellModel(
            id: bvid,
            title: cleanTitle,
            cover: pic ?? "",
            duration: durationSeconds,
            upName: author,
            upFace: nil,
            viewCount: play,
            danmakuCount: videoReview,
            publishedAt: pubdate
        )
    }
}
