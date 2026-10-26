import SwiftUI

/// 弹幕设置面板：不透明度 + 显示区域。
///
/// 用 `.presentationDetents([.height(400)])` 弹出，盖在播放页上时不遮住画面，
/// 调完直接看得到效果——这比「确定/取消」更好用，所以这里不做确认按钮。
///
/// 必须显式 `presentationBackground`：iOS 27 的 sheet 默认是**玻璃底**，
/// 直接透出下面的播放页和标题，浅色模式下分区和 chip 会糊成一片。
struct DanmakuSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var settings: DanmakuSettings { DanmakuSettings.shared }

    /// 滑杆要绑一个本地值：直接绑到 `@Observable` 的计算属性上
    /// 会在拖动过程中触发大量写盘，本地值拖动结束再落地。
    @State private var draftOpacity: Double = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    opacitySection
                    areaSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("弹幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("恢复默认") {
                        settings.reset()
                        draftOpacity = settings.opacity
                    }
                    .font(.system(size: 13))
                    .disabled(settings.isDefault)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .presentationBackground(Theme.canvas)
        .onAppear { draftOpacity = settings.opacity }
    }

    // MARK: - 不透明度

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("不透明度")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int((draftOpacity * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.pink)
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Text("淡")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)

                Slider(
                    value: $draftOpacity,
                    in: DanmakuSettings.opacityRange,
                    step: 0.05
                ) { editing in
                    // 松手才写盘，拖动过程只改本地值
                    if !editing { settings.opacity = draftOpacity }
                }
                .tint(Theme.pink)

                Text("浓")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }

            opacityPreview
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.5)
        }
    }

    /// 一眼能看出当前透明度效果的小样
    private var opacityPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.10, blue: 0.18),
                            Color(red: 0.20, green: 0.16, blue: 0.30)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 14) {
                Text("这是弹幕预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text("效果实时生效")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.pink)
            }
            .shadow(color: .black.opacity(0.85), radius: 1.4)
            .opacity(draftOpacity)
        }
        .frame(height: 52)
    }

    // MARK: - 显示区域

    private var areaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("显示区域")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                ForEach(DanmakuArea.allCases) { area in
                    areaChip(area)
                }
            }

            Text("上半区适合看直播时下方有礼物/互动条的场景；下半区适合画面顶部有字幕或比分板时使用。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.ink.opacity(0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func areaChip(_ area: DanmakuArea) -> some View {
        let selected = settings.area == area
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                settings.area = area
            }
        } label: {
            VStack(spacing: 7) {
                areaThumbnail(area, selected: selected)
                Text(area.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.pink : Theme.inkDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(selected ? Theme.pink.opacity(0.14) : Theme.ink.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        selected ? Theme.pink.opacity(0.55) : Theme.ink.opacity(0.14),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    /// 用三个小方块示意区域落点，比 SF Symbol 直观
    private func areaThumbnail(_ area: DanmakuArea, selected: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Theme.ink.opacity(0.13))
                .frame(width: 34, height: 24)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(selected ? Theme.pink : Theme.inkDim.opacity(0.55))
                .frame(
                    width: 34,
                    height: area == .full ? 24 : 12
                )
                .offset(y: area == .bottom ? 12 : 0)
        }
    }
}
