import Foundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// 登录态与扫码流程。
///
/// 只支持扫码登录：密码/短信登录在网页端需要极验（Geetest）人机验证参数，
/// 原生端无法生成，强行模拟会被判风控。
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    var profile: NavData?
    var qrImage: UIImage?
    var status: QRStatus = .waiting
    var isLoading = false
    var errorMessage: String?

    private var pollTask: Task<Void, Never>?
    private var currentKey: String?
    private var refreshTask: Task<Void, Never>?

    var isLoggedIn: Bool { CookieJar.shared.isLoggedIn }

    /// 账号 UID。收藏夹等接口需要 up_mid，优先用 nav 返回值，
    /// 冷启动时 nav 还没回来就退回 Cookie 里的 DedeUserID。
    var userID: Int? {
        if let mid = profile?.mid { return mid }
        return Int(CookieJar.shared.userID)
    }

    private init() {}

    // MARK: - 会话

    /// 启动时恢复会话：Cookie 已在 Keychain 里，这里向 nav 确认是否仍然有效
    func restore() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if let info = await BiliAPI.shared.nav(), info.loggedIn {
                self.profile = info
            } else {
                self.profile = nil
            }
        }
    }

    func refreshProfile() async {
        if let info = await BiliAPI.shared.nav(), info.loggedIn {
            profile = info
        } else {
            profile = nil
        }
    }

    func logout() {
        stopPolling()
        CookieJar.shared.clear()
        profile = nil
        qrImage = nil
        status = .waiting
    }

    // MARK: - 扫码登录

    func startQRLogin() async {
        stopPolling()
        isLoading = true
        errorMessage = nil
        status = .waiting
        qrImage = nil

        do {
            let data = try await BiliAPI.shared.qrGenerate()
            currentKey = data.qrcodeKey
            qrImage = QRCodeRenderer.image(from: data.url, scale: 10)
            isLoading = false
            beginPolling(key: data.qrcodeKey)
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            status = .failure(error.localizedDescription)
        }
    }

    private func beginPolling(key: String) {
        pollTask = Task { [weak self] in
            guard let self else { return }
            // 二维码有效期 180 秒，每 1.2 秒轮询一次，留出余量
            for _ in 0..<150 {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if Task.isCancelled { return }

                do {
                    let result = try await BiliAPI.shared.qrPoll(qrcodeKey: key)
                    let s = QRStatus(code: result.code, message: result.message)
                    self.status = s

                    switch s {
                    case .success:
                        await self.refreshProfile()
                        self.stopPolling()
                        return
                    case .expired:
                        self.stopPolling()
                        return
                    case .failure(let msg):
                        self.errorMessage = msg
                        self.stopPolling()
                        return
                    default:
                        continue
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.status = .expired
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

/// 二维码渲染
enum QRCodeRenderer {
    static func image(from string: String, scale: CGFloat) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
