import SwiftUI

/// 历史页：观看记录，卡片上带续播进度条。
struct HistoryView: View {
    @State private var store = VideoFeedStore(source: .history)

    var body: some View {
        ZStack {
            CanvasBackdrop()

            VStack(spacing: 0) {
                header
                VideoFeedGrid(
                    store: store,
                    emptyHint: "还没有观看记录"
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("历史")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("观看记录会随登录账号同步")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer(minLength: 0)

            GlassIconButton(systemName: "arrow.clockwise", size: 34) {
                Task { await store.refresh() }
            }
        }
        .padding(.horizontal, Theme.contentPadding)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
