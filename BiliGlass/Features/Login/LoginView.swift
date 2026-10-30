import SwiftUI

/// 扫码登录页。
///
/// 密码/短信登录需要在网页端完成极验人机验证，原生端无法生成对应参数，
/// 因此这里只提供扫码这一条可靠路径。
struct LoginView: View {
    @Environment(\.dismiss) private var dismiss

    private var auth: AuthService { AuthService.shared }

    var body: some View {
        ZStack {
            CanvasBackdrop()

            // 光斑让玻璃有可折射的内容
            Circle()
                .fill(Theme.glow(for: "login"))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(x: -80, y: -180)
            Circle()
                .fill(Theme.blue.opacity(0.28))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: 120, y: 260)

            VStack(spacing: 26) {
                title
                qrCard
                statusLine
                actions
            }
            .padding(.horizontal, 28)

            closeButton
        }
        .task {
            if auth.qrImage == nil, !auth.isLoggedIn {
                await auth.startQRLogin()
            }
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if loggedIn { dismiss() }
        }
    }

    // MARK: - 标题

    private var title: some View {
        VStack(spacing: 8) {
            Text("登录哔哩哔哩")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("使用哔哩哔哩 App 扫码即可登录")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkDim)
        }
    }

    // MARK: - 二维码玻璃卡

    private var qrCard: some View {
        GlassPanel(tint: nil, interactive: false, corner: 28) {
            ZStack {
                if auth.isLoading || auth.qrImage == nil {
                    ProgressView()
                        .tint(Theme.ink)
                        .frame(width: 220, height: 220)
                } else if let image = auth.qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(.white, in: .rect(cornerRadius: 18))

                    if auth.status == .expired {
                        expiredOverlay
                    }
                }
            }
            .padding(22)
        }
    }

    private var expiredOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("二维码已失效")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Button("刷新") {
                Task { await auth.startQRLogin() }
            }
            .buttonStyle(.glassProminent)
        }
        .frame(width: 220, height: 220)
        .background(.black.opacity(0.68), in: .rect(cornerRadius: 18))
    }

    // MARK: - 状态

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(auth.errorMessage ?? auth.status.hint)
                .font(.system(size: 13))
                .foregroundStyle(auth.status == .scanned ? Theme.pink : Theme.inkDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
    }

    private var statusColor: Color {
        switch auth.status {
        case .scanned: return Theme.pink
        case .expired, .failure: return .orange
        case .success: return .green
        case .waiting: return Theme.inkFaint
        }
    }

    // MARK: - 操作

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await auth.startQRLogin() }
            } label: {
                Label("重新获取二维码", systemImage: "qrcode")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.glass)
            .disabled(auth.isLoading)

            Text("凭证仅保存在本机钥匙串，不会上传到任何第三方服务器")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
        }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                GlassIconButton(systemName: "xmark", size: 36) {
                    auth.stopPolling()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }
}
