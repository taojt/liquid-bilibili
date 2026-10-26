import Foundation

/// 直播弹幕客户端。
///
/// 走 B站的弹幕长连接协议（`wss://<host>:<wss_port>/sub`），包结构是固定 16 字节头：
///
/// ```
/// 0..3   totalLen  (BE UInt32)  整包长度
/// 4..5   headerLen (BE UInt16)  固定 16
/// 6..7   protover  (BE UInt16)  0/1 明文，2 zlib，3 brotli
/// 8..11  operation (BE UInt32)  2 心跳 / 3 人气 / 5 通知 / 7 认证 / 8 认证回复
/// 12..15 sequence  (BE UInt32)
/// ```
///
/// 握手时声明 `protover: 2`（zlib）。**不要用 3**——那是 brotli，
/// iOS 没有系统级的 brotli 解码器，接了也解不开。
@MainActor
@Observable
final class LiveDanmakuClient {
    /// 最近收到的弹幕，只保留尾部若干条，避免长跑内存涨上去
    private(set) var bullets: [LiveBullet] = []
    var isConnected = false
    var statusText = ""
    /// 人气值（心跳回复 op=3 带回来的数字）
    var popularity = 0
    /// 本次连接的起点。弹幕的 `time` 就是相对它算出来的，
    /// 渲染层必须用同一个零点，否则时间轴会错位。
    private(set) var sessionStartedAt = Date()

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var session: URLSession?
    private var nextID = 0
    private var roomID = 0
    private var reconnectAttempt = 0
    private var isStopping = false

    private let maxBullets = 320
    private let heartbeatInterval: UInt64 = 30

    // MARK: - 连接

    func connect(roomID rawRoomID: Int) async {
        disconnect()
        isStopping = false
        roomID = rawRoomID
        statusText = "正在连接弹幕…"

        let realRoomID = (try? await BiliAPI.shared.liveRoomInit(roomID: rawRoomID))?.roomID ?? rawRoomID
        guard let info = try? await BiliAPI.shared.liveDanmuInfo(roomID: realRoomID) else {
            statusText = "弹幕服务器获取失败"
            return
        }
        guard let host = info.hostList?.first(where: { ($0.wssPort ?? 0) > 0 }),
              let hostName = host.host,
              let port = host.wssPort,
              let url = URL(string: "wss://\(hostName):\(port)/sub")
        else {
            statusText = "没有可用的弹幕服务器"
            return
        }

        sessionStartedAt = Date()
        bullets = []

        var request = URLRequest(url: url)
        request.setValue(HTTPClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://live.bilibili.com", forHTTPHeaderField: "Origin")

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        self.session = session

        let task = session.webSocketTask(with: request)
        socket = task
        task.resume()

        sendAuth(token: info.token ?? "", roomID: realRoomID)
        startReceiveLoop()
        startHeartbeat()

        statusText = "弹幕已连接"
        isConnected = true
    }

    func disconnect() {
        isStopping = true
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    // MARK: - 包头

    private func makePacket(operation: UInt32, body: Data) -> Data {
        var data = Data(capacity: 16 + body.count)
        appendBE32(&data, UInt32(16 + body.count))
        appendBE16(&data, 16)      // headerLen
        appendBE16(&data, 1)       // 上行一律明文
        appendBE32(&data, operation)
        appendBE32(&data, 1)       // sequence
        data.append(body)
        return data
    }

    private func appendBE32(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private func appendBE16(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    private func sendAuth(token: String, roomID: Int) {
        let auth: [String: Any] = [
            "uid": AuthService.shared.userID ?? 0,
            "roomid": roomID,
            "protover": 2,
            "platform": "web",
            "type": 2,
            "key": token,
            "clientver": "1.8.5",
            "buvid": CookieJar.shared.cookies["buvid3"] ?? ""
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: auth) else { return }
        send(makePacket(operation: 7, body: body))
    }

    private func send(_ data: Data) {
        socket?.send(.data(data)) { _ in }
    }

    // MARK: - 收包

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let socket = self.socket else { return }
                do {
                    let message = try await socket.receive()
                    switch message {
                    case .data(let data):
                        self.handleFrame(data)
                    case .string(let text):
                        self.handleFrame(Data(text.utf8))
                    @unknown default:
                        break
                    }
                } catch {
                    // 取消是主动断开，不该走重连
                    if Task.isCancelled || self.isStopping { return }
                    await self.handleDisconnect()
                    return
                }
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.send(self.makePacket(operation: 2, body: Data("{}".utf8)))
            }
        }
    }

    private func handleDisconnect() async {
        isConnected = false
        guard reconnectAttempt < 2, !isStopping else {
            statusText = "弹幕连接已断开"
            return
        }
        reconnectAttempt += 1
        statusText = "弹幕重连中（\(reconnectAttempt)/2）…"
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !isStopping else { return }
        await connect(roomID: roomID)
    }

    // MARK: - 解包

    /// 一帧数据里可能套着多帧（压缩包里就是多帧），所以递归处理
    private func handleFrame(_ data: Data) {
        var offset = 0
        while offset + 16 <= data.count {
            let total = Int(be32(data, offset))
            let headerLen = Int(be16(data, offset + 4))
            let protover = Int(be16(data, offset + 6))
            let operation = Int(be32(data, offset + 8))

            guard total >= headerLen, headerLen >= 16, offset + total <= data.count else { return }

            let body = data.subdata(in: (offset + headerLen)..<(offset + total))
            offset += total

            switch protover {
            case 2, 3:
                // protover 3 是 brotli，理论上不会出现（我们申请的是 2），解不开就跳过
                if let inflated = Zlib.inflate(body) {
                    handleFrame(inflated)
                }
            default:
                if operation == 3 {
                    // 人气值：4 字节大端整数
                    if body.count >= 4 {
                        popularity = Int(be32(body, 0))
                    }
                } else if operation == 8 {
                    // 认证回复：{"code":0}。非 0 说明 key/uid 对不上，
                    // 此时连接是「假活」——收不到任何弹幕，必须让用户看见。
                    if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                       let code = object["code"] as? Int, code != 0 {
                        statusText = "弹幕认证失败（\(code)）"
                        isConnected = false
                    }
                } else if operation == 5 {
                    parseMessages(body)
                }
            }
        }
    }

    private func be16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) << 8 | UInt16(data[base + 1])
    }

    private func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base]) << 24
            | UInt32(data[base + 1]) << 16
            | UInt32(data[base + 2]) << 8
            | UInt32(data[base + 3])
    }

    // MARK: - 消息

    private func parseMessages(_ body: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: body) else { return }
        if let dictionary = object as? [String: Any] {
            consume(dictionary)
        } else if let list = object as? [[String: Any]] {
            for dictionary in list { consume(dictionary) }
        }
    }

    private func consume(_ json: [String: Any]) {
        guard let cmd = json["cmd"] as? String else { return }

        if cmd.hasPrefix("DANMU_MSG") {
            guard let info = json["info"] as? [Any], info.count > 2,
                  let text = info[1] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }

            let meta = info[0] as? [Any]
            // info[0][1] 是模式，info[0][3] 是颜色；不同版本未必都有
            let mode = intValue(meta, 1) ?? 1
            let colorValue = intValue(meta, 3) ?? 0xFFFFFF
            var userName: String?
            if let user = info[2] as? [Any], user.count > 1 {
                userName = user[1] as? String
            }
            append(text: text, mode: mode, colorValue: colorValue, userName: userName)
        } else if cmd.hasPrefix("WATCHED_CHANGE") {
            // {"data":{"num":1234,"text_small":"1234"}}
            if let data = json["data"] as? [String: Any], let num = data["num"] as? Int {
                popularity = num
            }
        }
    }

    private func intValue(_ array: [Any]?, _ index: Int) -> Int? {
        guard let array, index >= 0, index < array.count else { return nil }
        if let value = array[index] as? Int { return value }
        if let value = array[index] as? NSNumber { return value.intValue }
        if let text = array[index] as? String { return Int(text) }
        return nil
    }

    private func append(text: String, mode: Int, colorValue: Int, userName: String?) {
        nextID += 1
        let bullet = LiveBullet(
            id: nextID,
            text: text,
            mode: mode,
            colorValue: colorValue,
            userName: userName,
            time: Date().timeIntervalSince(sessionStartedAt)
        )
        bullets.append(bullet)
        if bullets.count > maxBullets {
            bullets.removeFirst(bullets.count - maxBullets)
        }
    }
}
