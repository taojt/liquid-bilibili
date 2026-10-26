import Foundation
import AVFoundation

/// 播放内核。
///
/// 走两条路：
/// 1. **DASH（首选）**：分离的音视频流，画质档位全、时长完整。代价是需要自己
///    合并两条轨，且必须预检能否在合理时间内读出轨道信息，否则会长时间卡住。
/// 2. **durl（兜底）**：音视频合一的单文件 MP4，AVFoundation 原生支持，稳定但
///    画质档位少，且 B 站对超长视频会截断（单文件模式上限）。
///
/// 防盗链同样绕不开：CDN 校验 Referer，缺失直接 403。AVPlayer 没有公开的
/// header 注入接口，因此统一由 HeaderResourceLoader 接管资源加载。
@MainActor
@Observable
final class PlaybackEngine {
    var player: AVPlayer?
    var isPlaying = false
    var isLoading = false
    var isReady = false
    var errorMessage: String?

    var currentTime: Double = 0
    var duration: Double = 0

    /// 可选清晰度（qn），实际档位受登录态与视频本身限制
    let availableQN: [Int] = [112, 80, 64, 32]
    var currentQN: Int = 64

    /// 当前是否走的 DASH 路径，用于界面上标注
    var usingDash = false

    /// 倍速档位。AVPlayer 的 `rate` 同时承担「播放/暂停」语义，
    /// 因此倍速要写进 `defaultRate`，由 `play()` 自动沿用，避免切档时把暂停当成播放。
    let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var playbackRate: Float = 1.0

    private var detail: VideoDetail?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?

    /// 待应用的续播起点。必须等播放项 `readyToPlay` 之后再 seek：
    /// AVPlayer 在未就绪时收到的 seek 会被**静默丢弃**，表现为「断点续播不生效，
    /// 每次都从头播」——这正是之前续播时好时坏的根因。
    private var pendingStart: Double = 0

    /// 本地进度落盘节流：每 5 秒存一次，避免 0.4 秒一次的高频写 UserDefaults
    private var lastLocalSaveSecond = -1
    /// 服务端心跳节流：20 秒一次，太频繁会被判刷量
    private var lastHeartbeatAt = Date.distantPast
    private static let heartbeatInterval: TimeInterval = 20

    // MARK: - 加载

    /// 加载视频。
    ///
    /// `qn` 传 nil 时按登录态自动选择：登录后能拿到 1080P（80），
    /// 未登录只给到 720P（64）——直传 80 未登录会被降到 64，
    /// 但请求里带上更高档位会让服务端走一次降级判断，没必要。
    func load(detail: VideoDetail, qn: Int? = nil, startAt: Double = 0) async {
        self.detail = detail
        isLoading = true
        errorMessage = nil
        isReady = false
        currentTime = startAt
        lastLocalSaveSecond = -1
        lastHeartbeatAt = .distantPast
        detachObservers()
        player?.pause()

        let targetQN = qn ?? (CookieJar.shared.isLoggedIn ? 80 : 64)
        do {
            try await requestStream(qn: targetQN, startAt: startAt)
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func switchQuality(to qn: Int) async {
        guard qn != currentQN else { return }
        let resume = currentTime
        let wasPlaying = isPlaying
        isLoading = true
        do {
            try await requestStream(qn: qn, startAt: resume)
            if !wasPlaying {
                player?.pause()
                isPlaying = false
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func requestStream(qn: Int, startAt: Double) async throws {
        guard let detail else { throw BiliError.empty }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // DASH 在当前实现下会在 insertTimeRange 阶段挂住（远程 fMP4 的索引段
        // 无法稳定取得），因此默认关闭，仅作为实验开关保留。
        if UserDefaults.standard.bool(forKey: "preferDASH"),
           await playDash(detail: detail, qn: qn, startAt: startAt) {
            return
        }
        try await playDurl(detail: detail, qn: qn, startAt: startAt)
    }

    // MARK: - DASH 路径

    private func playDash(detail: VideoDetail, qn: Int, startAt: Double) async -> Bool {
        guard let data = try? await BiliAPI.shared.playURL(
            aid: detail.aid, cid: detail.cid, qn: qn
        ), let dash = data.dash, !dash.video.isEmpty else {
            return false
        }

        guard let videoSeg = dash.video.first(where: { $0.id <= qn }) ?? dash.video.first,
              let videoURL = URL(string: videoSeg.baseUrl) else {
            return false
        }
        let audioSeg = dash.audio?.max { ($0.bandwidth ?? 0) < ($1.bandwidth ?? 0) }
        let audioURL = audioSeg.flatMap { URL(string: $0.baseUrl) }

        let videoAsset = HeaderResourceLoader.makeAsset(videoURL, isAudio: false)

        // 预检：读不出轨道说明 fMP4 索引没拿全，直接放弃，避免界面长时间转圈
        guard await Self.probeVideoTrack(videoAsset, timeoutSeconds: 8) else { return false }

        let composition = AVMutableComposition()
        do {
            let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else { return false }
            var total = try await videoAsset.load(.duration)

            if let audioURL {
                let audioAsset = HeaderResourceLoader.makeAsset(audioURL, isAudio: true)
                let audioTracks = (try? await audioAsset.loadTracks(withMediaType: .audio)) ?? []
                if let audioTrack = audioTracks.first {
                    let audioDuration = (try? await audioAsset.load(.duration)) ?? total
                    total = CMTimeMinimum(total, audioDuration)
                    if let compAudio = composition.addMutableTrack(
                        withMediaType: .audio,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) {
                        try? compAudio.insertTimeRange(
                            CMTimeRange(start: .zero, duration: total),
                            of: audioTrack,
                            at: .zero
                        )
                    }
                }
            }

            guard let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return false }
            try compVideo.insertTimeRange(
                CMTimeRange(start: .zero, duration: total),
                of: videoTrack,
                at: .zero
            )
            compVideo.preferredTransform = (try? await videoTrack.load(.preferredTransform)) ?? .identity

            currentQN = videoSeg.id
            usingDash = true
            duration = total.seconds.isFinite ? total.seconds : 0
            installPlayer(item: AVPlayerItem(asset: composition), startAt: startAt)
            return true
        } catch {
            return false
        }
    }

    /// 限时探测：能读出视频轨就认为 DASH 可用
    private static func probeVideoTrack(_ asset: AVURLAsset, timeoutSeconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                let tracks = try? await asset.loadTracks(withMediaType: .video)
                return !(tracks ?? []).isEmpty
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    // MARK: - durl 兜底路径

    private func playDurl(detail: VideoDetail, qn: Int, startAt: Double) async throws {
        let data = try await BiliAPI.shared.playURLMp4(
            aid: detail.aid, cid: detail.cid, qn: qn
        )
        guard let first = data.durl?.first, let url = URL(string: first.url) else {
            throw BiliError.api(code: -1, message: "未返回可播放地址")
        }
        currentQN = data.quality ?? qn
        usingDash = false
        duration = 0
        let asset = HeaderResourceLoader.makeAsset(url, isAudio: false)
        installPlayer(item: AVPlayerItem(asset: asset), startAt: startAt)
    }

    // MARK: - 播放器装配

    private func installPlayer(item: AVPlayerItem, startAt: Double) {
        item.preferredForwardBufferDuration = 8
        pendingStart = startAt

        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            switch observed.status {
            case .readyToPlay:
                Task { @MainActor [weak self] in
                    await self?.applyPendingStart()
                }
            case .failed:
                let detail = Self.describe(observed.error)
                Task { @MainActor [weak self] in
                    self?.errorMessage = detail
                    self?.isLoading = false
                }
            default:
                break
            }
        }

        let p = player ?? AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        p.defaultRate = playbackRate
        p.replaceCurrentItem(with: item)
        p.volume = 1.0
        player = p

        attachObservers(to: p)

        p.play()
        isPlaying = true
        isReady = true
    }

    /// 播放项就绪后落地续播点，并顺手把真实时长补进来
    /// （durl 单文件在请求阶段拿不到时长，只能等 AVFoundation 解析完）。
    private func applyPendingStart() async {
        guard let player else { return }
        if let itemDuration = player.currentItem?.duration.seconds,
           itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }
        let target = pendingStart
        pendingStart = 0
        guard target > 0.5 else { return }
        // 断点比总时长还靠后（例如换了清晰度、视频被截断）时不能硬 seeks，
        // 否则会停在片尾黑屏，退回开头更符合预期。
        let upper = duration > 1 ? duration - 1 : target
        let clamped = Swift.min(target, upper)
        await player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = clamped
    }

    // MARK: - 播放控制

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.defaultRate = playbackRate
            player.play()
            player.rate = playbackRate
        }
        isPlaying.toggle()
    }

    /// 切换倍速。播放中立刻生效；暂停状态下只记下来，下次 play() 沿用。
    func setRate(_ rate: Float) {
        playbackRate = rate
        guard let player else { return }
        player.defaultRate = rate
        if isPlaying {
            player.rate = rate
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = min(max(0, seconds), max(duration, 1))
        currentTime = clamped
        Task {
            await player.seek(
                to: CMTime(seconds: clamped, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    func stop() {
        persistProgress(force: true)
        player?.pause()
        detachObservers()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        duration = 0
    }

    // MARK: - 进度持久化

    /// 保存本地断点 + 周期性向服务端上报心跳。
    /// 两个动作失败都无所谓，绝不能因为保存进度而中断播放。
    private func persistProgress(force: Bool = false) {
        guard let detail else { return }
        let position = Int(currentTime)
        guard position > 0 else { return }

        if force || abs(position - lastLocalSaveSecond) >= 5 {
            lastLocalSaveSecond = position
            PlaybackMemory.save(bvid: detail.bvid, position: position, duration: Int(duration))
        }

        guard isPlaying || force else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHeartbeatAt) >= Self.heartbeatInterval else { return }
        lastHeartbeatAt = now

        let aid = detail.aid
        let cid = detail.cid
        let played = currentTime
        Task.detached(priority: .utility) {
            try? await BiliAPI.shared.reportProgress(aid: aid, cid: cid, playedSeconds: played)
        }
    }

    // MARK: - 观察者

    private func attachObservers(to player: AVPlayer) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let secs = time.seconds
            guard secs.isFinite else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = secs
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.persistProgress()
            }
        }
    }

    private func detachObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
    }

    /// 把 AVFoundation 的错误摊平成可读文本，便于定位网络还是解码问题
    private static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "播放失败（无错误详情）" }
        var parts = ["\(error.domain) \(error.code)"]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("底层 \(underlying.domain) \(underlying.code)")
        }
        let message = error.localizedDescription
        if !message.isEmpty { parts.append(message) }
        return parts.joined(separator: " · ")
    }
}
