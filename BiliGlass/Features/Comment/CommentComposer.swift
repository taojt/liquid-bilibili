import SwiftUI

/// 评论 / 回复输入弹层。
///
/// 用底部 sheet 而不是内嵌输入框：详情页是长滚动列表，
/// 内嵌输入框在键盘弹起时很容易被顶到屏幕外。
struct CommentComposer: View {
    /// "发表评论" / "回复 @xxx"
    let title: String
    var placeholder: String = "发一条友善的评论"
    var onSend: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private let limit = 1000

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmed.isEmpty && trimmed.count <= limit && !sending
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                editor
                HStack {
                    Text("\(trimmed.count)/\(limit)")
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(trimmed.count > limit ? .red : Theme.inkFaint)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(CanvasBackdrop())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .font(.system(size: 13))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("发送")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .disabled(!canSend)
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        .onAppear {
            // sheet 动画结束后再抢焦点，否则有时键盘不弹
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                focused = true
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(height: 150)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func send() async {
        guard canSend else { return }
        sending = true
        let ok = await onSend(trimmed)
        sending = false
        if ok { dismiss() }
    }
}
