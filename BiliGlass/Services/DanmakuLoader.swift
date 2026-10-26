import Foundation

/// 弹幕拉取与解析。
///
/// B站弹幕接口给的是 **deflate 压缩的 XML**（`Content-Encoding: deflate`），
/// URLSession 会自动解压，所以拿到手就是明文 XML，直接丢给 XMLParser。
///
/// 单条格式：
/// `<d p="出现时间,模式,字号,颜色,时间戳,弹幕池,用户哈希,行号,权重">正文</d>`
enum DanmakuLoader {
    /// 单次最多渲染多少条。热门视频弹幕可达数十万条，
    /// 全量排轨会拖慢首帧，取前 8000 条（按时间排序后）观感已经足够。
    static let maxCount = 8000

    static func load(cid: Int) async -> [DanmakuItem] {
        guard let data = try? await BiliAPI.shared.danmakuXML(cid: cid) else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [DanmakuItem] {
        let delegate = Handler()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()

        // 按时间排序是排轨与二分查找的前提
        var items = delegate.items
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        items.sort { $0.time < $1.time }
        return items
    }

    private final class Handler: NSObject, XMLParserDelegate {
        var items: [DanmakuItem] = []
        private var buffer = ""
        private var currentParams: String?
        private var nextID = 0

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            guard elementName == "d" else { return }
            currentParams = attributeDict["p"]
            buffer.removeAll(keepingCapacity: true)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentParams != nil else { return }
            buffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard elementName == "d", let params = currentParams else { return }
            currentParams = nil

            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            let fields = params.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 4,
                  let time = Double(fields[0]),
                  let mode = Int(fields[1]),
                  let color = Int(fields[3])
            else { return }

            // mode 6 是逆向弹幕、7 是高级弹幕、8 是脚本弹幕，一律跳过：
            // 前者会从右往左飞（打乱轨道模型），后两者需要剧本引擎
            guard (1...5).contains(mode) else { return }

            items.append(
                DanmakuItem(
                    id: nextID,
                    text: text,
                    time: time,
                    mode: mode,
                    colorValue: color
                )
            )
            nextID += 1
        }
    }
}
