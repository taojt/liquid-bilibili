import Foundation
import Compression

/// zlib 解压。
///
/// 直播弹幕的 op=5 消息体在 protover=2 时是 zlib 压缩的包，
/// 解压后里面还是若干个完整的「包头 + 负载」，需要递归再拆一次。
///
/// iOS 的 Compression 框架只提供裸 deflate（`COMPRESSION_ZLIB` 实际不含 zlib 头），
/// 而 B站发的是标准 zlib 容器（2 字节头 + deflate + 4 字节 adler32），
/// 所以要先跳过头部再解；两个版本都试一遍，哪种能解出来用哪种。
enum Zlib {
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 6 else { return nil }
        // 标准 zlib 容器：跳过 2 字节头
        if let out = decode(data.subdata(in: 2..<data.count)) { return out }
        // 少数实现直接给裸 deflate，兜底再试一次
        return decode(data)
    }

    private static func decode(_ payload: Data) -> Data? {
        guard !payload.isEmpty else { return nil }
        let source = [UInt8](payload)
        // 弹幕包解开后通常几十 KB，给足余量；不够就翻倍重试
        var capacity = Swift.max(64 * 1024, source.count * 8)

        for _ in 0..<6 {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            let written = compression_decode_buffer(
                buffer,
                capacity,
                source,
                source.count,
                nil,
                COMPRESSION_ZLIB
            )
            if written > 0 {
                let out = Data(bytes: buffer, count: written)
                buffer.deallocate()
                return out
            }
            buffer.deallocate()
            capacity *= 4
        }
        return nil
    }
}
