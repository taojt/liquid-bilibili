import SwiftUI
import AVFoundation

/// AVPlayerLayer 的 SwiftUI 包装。用 layerClass 直接指定 AVPlayerLayer，
/// 避免 VideoPlayer 自带控件与自定义玻璃控制层冲突。
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // 同一个 AVPlayer 会被内嵌播放器和全屏播放器先后持有，
        // 每次更新都重新绑定一次，确保视频出现在最新建的 layer 上。
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }

    /// 注意：这里刻意不在 dismantle 里把 player 置 nil。
    /// AVPlayer 只把画面渲染到最后一次绑定的 AVPlayerLayer 上，
    /// 如果旧 layer 在销毁时把 player 摘掉，会连带把新 layer 的画面一起熄掉（全屏黑屏就源于此）。
    /// 旧 layer 随 UIView 一起释放，AVPlayer 的引用计数会自然归零。
}
