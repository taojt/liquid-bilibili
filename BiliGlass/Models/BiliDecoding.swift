import Foundation

// MARK: - 宽松类型解码

/// B站的 JSON 字段类型并不稳定：同一个字段在不同接口、不同灰度版本里
/// 可能是数字、字符串、甚至 null。严格按 Int 解码，一个字段漂移就会让
/// 整条响应解析失败，界面只能显示「数据解析失败」，很难定位。
///
/// 这一层专门吃掉这类差异——能解就解，解不出就当缺失，绝不整体抛错。
extension KeyedDecodingContainer {
    /// 数字型字段，兼容 Int / Double / 数字字符串
    func flexibleInt(_ key: Key) -> Int? {
        if let value = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil {
            return value
        }
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil {
            return Int(text.trimmingCharacters(in: .whitespaces))
        }
        if let number = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil {
            return Int(number)
        }
        return nil
    }

    /// 字符串型字段，数字会被转成文本
    func flexibleString(_ key: Key) -> String? {
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil {
            return text
        }
        if let number = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil {
            return "\(number)"
        }
        if let flag = (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil {
            return flag ? "true" : "false"
        }
        return nil
    }

    /// 布尔型字段，兼容 0/1 与 "true"/"false"
    func flexibleBool(_ key: Key) -> Bool? {
        if let flag = (try? decodeIfPresent(Bool.self, forKey: key)) ?? nil {
            return flag
        }
        if let number = (try? decodeIfPresent(Int.self, forKey: key)) ?? nil {
            return number != 0
        }
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil {
            return text == "true" || text == "1"
        }
        return nil
    }
}
