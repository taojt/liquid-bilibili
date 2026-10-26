#!/usr/bin/env swift
//
// generate-icon.swift
//
// 用 CoreGraphics 绘制 App 图标，输出 iOS 18+ 需要的三套变体：
//   AppIcon-1024.png         默认
//   AppIcon-1024-dark.png    深色模式
//   AppIcon-1024-tinted.png  着色模式（系统按亮度叠 tint，因此给透明底 + 白色图形）
//
// 设计取向：二次元的视觉语言是「高饱和渐变 + 星光 + 光环 + 玻璃质感」，
// 所以底子是粉→紫→蓝的对角渐变，中间一圈魔法光环托住白色玻璃播放三角，
// 四角钉几颗尖角星芒（キラキラ）。
//
// 为什么不用 AI 生图：图标要在 60pt 下依然清晰，几何图形矢量绘制最稳；
// 而且三套变体共用同一份几何描述，风格必然一致，改一次全变。
//
// 用法：xcrun swift scripts/generate-icon.swift BiliGlass/Resources/Assets.xcassets/AppIcon.appiconset
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let S = CGFloat(side)
let cx = S / 2
let cy = S / 2

// MARK: - 工具

func makeContext(alpha: Bool) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info: CGBitmapInfo = alpha
        ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let ctx = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: info.rawValue
    ) else { fatalError("无法创建 CGContext") }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("无法写入 \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("编码失败 \(url.path)") }
    print("✓ \(url.lastPathComponent)")
}

// MARK: - 几何：播放三角

/// 播放三角形顶点（相对中心）。已内缩，给圆角留余量。
func playPoints(scale: CGFloat = 1) -> [CGPoint] {
    let raw: [(CGFloat, CGFloat)] = [(-153, -180), (-153, 180), (153, 0)]
    return raw.map { pair in
        CGPoint(x: cx + pair.0 * scale, y: cy + pair.1 * scale)
    }
}

/// 圆角半径上限
let cornerRadius: CGFloat = 34

/// 圆角多边形，**单条闭合轮廓**。
///
/// 之前用「描边环 ∪ 原三角形」的并集做法能得到实心圆角三角形，
/// 但 `stroke` 会把并集轮廓的全部子路径都描出来（外圈 + 内圈），
/// 于是三角形内部出现两道莫名其妙的细线。
/// 改成在每个顶点把直边截短、用二次贝塞尔绕过顶点，得到的是一条干净轮廓，
/// 填充、裁剪、描边都不会有多余线条。
func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let n = points.count
    guard n >= 3 else { return path }

    func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return CGPoint(x: dx / len, y: dy / len)
    }
    func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }

    var starts: [CGPoint] = []
    var ends: [CGPoint] = []
    for i in 0..<n {
        let cur = points[i]
        let prev = points[(i - 1 + n) % n]
        let next = points[(i + 1) % n]
        let toPrev = unit(cur, prev)
        let toNext = unit(cur, next)
        // 圆角不能吃掉超过半条边
        let r = min(radius, length(cur, prev) * 0.45, length(cur, next) * 0.45)
        starts.append(CGPoint(x: cur.x + toPrev.x * r, y: cur.y + toPrev.y * r))
        ends.append(CGPoint(x: cur.x + toNext.x * r, y: cur.y + toNext.y * r))
    }

    path.move(to: starts[0])
    for i in 0..<n {
        path.addQuadCurve(to: ends[i], control: points[i])
        path.addLine(to: starts[(i + 1) % n])
    }
    path.closeSubpath()
    return path
}

func roundedTrianglePath(scale: CGFloat = 1) -> CGPath {
    roundedPolygon(playPoints(scale: scale), radius: cornerRadius * scale)
}

// MARK: - 几何：星芒

/// 四角星芒。四个尖角之间用二次贝塞尔向内收腰，收得越紧越像「闪光」。
func sparklePath(center: CGPoint, radius: CGFloat, waist: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = radius
    let w = r * waist
    p.move(to: CGPoint(x: center.x, y: center.y + r))
    p.addQuadCurve(
        to: CGPoint(x: center.x + r, y: center.y),
        control: CGPoint(x: center.x + w, y: center.y + w)
    )
    p.addQuadCurve(
        to: CGPoint(x: center.x, y: center.y - r),
        control: CGPoint(x: center.x + w, y: center.y - w)
    )
    p.addQuadCurve(
        to: CGPoint(x: center.x - r, y: center.y),
        control: CGPoint(x: center.x - w, y: center.y - w)
    )
    p.addQuadCurve(
        to: CGPoint(x: center.x, y: center.y + r),
        control: CGPoint(x: center.x - w, y: center.y + w)
    )
    p.closeSubpath()
    return p
}

/// 在相对坐标（0~1）处画一颗星芒。带辉光，让它在深色底上也是「发光」的。
func drawSparkle(
    ctx: CGContext,
    at spot: CGPoint,
    radius: CGFloat,
    waist: CGFloat = 0.16,
    color: CGColor,
    glow: CGColor?
) {
    let center = CGPoint(x: S * spot.x, y: S * spot.y)
    let path = sparklePath(center: center, radius: radius, waist: waist)

    if let glow {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: radius * 1.6, color: glow)
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
}

/// 小圆点星光，补密度用
func drawDot(ctx: CGContext, at spot: CGPoint, radius: CGFloat, color: CGColor) {
    let center = CGPoint(x: S * spot.x, y: S * spot.y)
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
}

// MARK: - 中央图形

/// 魔法光环：一圈很细的圆环 + 一层柔光，二次元里托住主体的那种。
func drawHalo(ctx: CGContext, radius: CGFloat, width: CGFloat, color: CGColor, glow: CGColor?) {
    let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)

    if let glow {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: radius * 0.5, color: glow)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: rect)
        ctx.restoreGState()
    }

    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokeEllipse(in: rect)
}

func drawGlyph(ctx: CGContext, scale: CGFloat, fill: [CGColor], glow: CGColor?, rim: CGColor?) {
    let solid = roundedTrianglePath(scale: scale)

    // 1. 外发光
    if let glow {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 96, color: glow)
        ctx.setFillColor(fill[0])
        ctx.addPath(solid)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 2. 实心底
    ctx.saveGState()
    ctx.addPath(solid)
    ctx.setFillColor(fill[0])
    ctx.fillPath()
    ctx.restoreGState()

    // 3. 玻璃质感：自上而下的渐变
    ctx.saveGState()
    ctx.addPath(solid)
    ctx.clip()
    // 注意：颜色个数必须和 locations 个数一致，否则 CGGradient 行为未定义（会出现带状分层）
    ctx.drawLinearGradient(
        gradient(fill, [0, 0.55, 1]),
        start: CGPoint(x: 0, y: S * 0.86),
        end: CGPoint(x: 0, y: S * 0.14),
        options: []
    )

    // 4. 顶部一道线性高光 + 底部一道内阴影
    ctx.drawLinearGradient(
        gradient([rgb(1, 1, 1, 0.45), rgb(1, 1, 1, 0)], [0, 1]),
        start: CGPoint(x: 0, y: S * 0.78),
        end: CGPoint(x: 0, y: S * 0.46),
        options: []
    )
    ctx.drawLinearGradient(
        gradient([rgb(0.32, 0.16, 0.42, 0.16), rgb(0.32, 0.16, 0.42, 0)], [0, 1]),
        start: CGPoint(x: 0, y: S * 0.28),
        end: CGPoint(x: 0, y: S * 0.58),
        options: []
    )
    ctx.restoreGState()

    // 5. 边缘一圈细高光，让玻璃有厚度
    if let rim {
        ctx.setStrokeColor(rim)
        ctx.setLineWidth(3)
        ctx.addPath(solid)
        ctx.strokePath()
    }
}

// MARK: - 三套变体

func renderDefault() -> CGImage {
    let ctx = makeContext(alpha: false)

    // 底色：B站粉 → 紫 → 蓝的对角渐变
    ctx.drawLinearGradient(
        gradient([rgb(1.00, 0.45, 0.64), rgb(0.66, 0.38, 0.94), rgb(0.20, 0.70, 0.98)], [0, 0.52, 1]),
        start: CGPoint(x: 0, y: S),
        end: CGPoint(x: S, y: 0),
        options: []
    )

    // 两团柔光，让背景不是死渐变
    ctx.drawRadialGradient(
        gradient([rgb(1, 0.62, 0.78, 0.85), rgb(1, 0.62, 0.78, 0)], [0, 1]),
        startCenter: CGPoint(x: S * 0.16, y: S * 0.88),
        startRadius: 0,
        endCenter: CGPoint(x: S * 0.16, y: S * 0.88),
        endRadius: S * 0.62,
        options: []
    )
    ctx.drawRadialGradient(
        gradient([rgb(0.42, 0.92, 1, 0.70), rgb(0.42, 0.92, 1, 0)], [0, 1]),
        startCenter: CGPoint(x: S * 0.90, y: S * 0.10),
        startRadius: 0,
        endCenter: CGPoint(x: S * 0.90, y: S * 0.10),
        endRadius: S * 0.58,
        options: []
    )

    // 主角背后的柔光，把三角从背景里「托」出来
    ctx.drawRadialGradient(
        gradient([rgb(1, 1, 1, 0.34), rgb(1, 1, 1, 0)], [0, 1]),
        startCenter: CGPoint(x: cx, y: cy),
        startRadius: 0,
        endCenter: CGPoint(x: cx, y: cy),
        endRadius: S * 0.40,
        options: []
    )

    // 魔法光环
    drawHalo(ctx: ctx, radius: 322, width: 9, color: rgb(1, 1, 1, 0.50), glow: rgb(1, 0.85, 0.95, 0.55))
    drawHalo(ctx: ctx, radius: 366, width: 3, color: rgb(1, 1, 1, 0.24), glow: nil)

    // 星芒：一颗大的在右上，一颗中等在左下，其余撒点
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.795, y: 0.775), radius: 74, color: rgb(1, 1, 1, 0.96), glow: rgb(1, 0.92, 0.98, 0.85))
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.205, y: 0.290), radius: 48, color: rgb(1, 1, 1, 0.88), glow: rgb(0.75, 0.95, 1, 0.75))
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.845, y: 0.320), radius: 30, color: rgb(1, 1, 1, 0.80), glow: nil)
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.300, y: 0.790), radius: 22, color: rgb(1, 1, 1, 0.72), glow: nil)

    drawDot(ctx: ctx, at: CGPoint(x: 0.700, y: 0.185), radius: 11, color: rgb(1, 1, 1, 0.80))
    drawDot(ctx: ctx, at: CGPoint(x: 0.150, y: 0.560), radius: 8, color: rgb(1, 1, 1, 0.66))
    drawDot(ctx: ctx, at: CGPoint(x: 0.535, y: 0.905), radius: 6, color: rgb(1, 1, 1, 0.58))

    drawGlyph(
        ctx: ctx,
        scale: 0.92,
        fill: [rgb(1, 1, 1), rgb(1, 0.965, 0.98), rgb(0.92, 0.88, 1)],
        glow: rgb(0.40, 0.14, 0.46, 0.45),
        rim: rgb(1, 1, 1, 0.65)
    )

    return ctx.makeImage()!
}

func renderDark() -> CGImage {
    let ctx = makeContext(alpha: false)

    // 深色底：近黑的紫蓝，比纯黑更有材质感
    ctx.drawLinearGradient(
        gradient([rgb(0.07, 0.05, 0.12), rgb(0.14, 0.08, 0.22), rgb(0.05, 0.10, 0.20)], [0, 0.5, 1]),
        start: CGPoint(x: 0, y: S),
        end: CGPoint(x: S, y: 0),
        options: []
    )

    ctx.drawRadialGradient(
        gradient([rgb(0.98, 0.42, 0.61, 0.55), rgb(0.98, 0.42, 0.61, 0)], [0, 1]),
        startCenter: CGPoint(x: S * 0.18, y: S * 0.86),
        startRadius: 0,
        endCenter: CGPoint(x: S * 0.18, y: S * 0.86),
        endRadius: S * 0.68,
        options: []
    )
    ctx.drawRadialGradient(
        gradient([rgb(0.29, 0.72, 0.96, 0.50), rgb(0.29, 0.72, 0.96, 0)], [0, 1]),
        startCenter: CGPoint(x: S * 0.86, y: S * 0.12),
        startRadius: 0,
        endCenter: CGPoint(x: S * 0.86, y: S * 0.12),
        endRadius: S * 0.60,
        options: []
    )

    // 深色下光环更亮，形成霓虹感
    drawHalo(ctx: ctx, radius: 322, width: 10, color: rgb(1, 0.72, 0.85, 0.62), glow: rgb(1, 0.42, 0.65, 0.85))
    drawHalo(ctx: ctx, radius: 366, width: 3, color: rgb(0.72, 0.90, 1, 0.34), glow: nil)

    drawSparkle(ctx: ctx, at: CGPoint(x: 0.795, y: 0.775), radius: 74, color: rgb(1, 0.95, 0.98), glow: rgb(1, 0.55, 0.75, 0.95))
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.205, y: 0.290), radius: 48, color: rgb(0.85, 0.95, 1), glow: rgb(0.35, 0.80, 1, 0.85))
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.845, y: 0.320), radius: 30, color: rgb(1, 1, 1, 0.85), glow: nil)
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.300, y: 0.790), radius: 22, color: rgb(1, 1, 1, 0.75), glow: nil)

    drawDot(ctx: ctx, at: CGPoint(x: 0.700, y: 0.185), radius: 11, color: rgb(0.85, 1, 1, 0.85))
    drawDot(ctx: ctx, at: CGPoint(x: 0.150, y: 0.560), radius: 8, color: rgb(1, 0.85, 0.92, 0.70))
    drawDot(ctx: ctx, at: CGPoint(x: 0.535, y: 0.905), radius: 6, color: rgb(1, 1, 1, 0.60))

    // 深色下图形用粉白渐变，配合更明显的辉光
    drawGlyph(
        ctx: ctx,
        scale: 0.92,
        fill: [rgb(1, 0.86, 0.91), rgb(1, 1, 1), rgb(0.84, 0.90, 1)],
        glow: rgb(0.98, 0.42, 0.61, 0.80),
        rim: rgb(1, 1, 1, 0.55)
    )

    return ctx.makeImage()!
}

/// 着色模式：系统按亮度套 tint，所以只留白色图形 + 透明底，层级最干净。
/// 星芒保留两颗大的，否则纯三角在小尺寸下会显得空。
func renderTinted() -> CGImage {
    let ctx = makeContext(alpha: true)
    ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))

    // 光环
    ctx.setStrokeColor(rgb(1, 1, 1, 0.55))
    ctx.setLineWidth(9)
    ctx.strokeEllipse(in: CGRect(x: cx - 322, y: cy - 322, width: 644, height: 644))

    drawSparkle(ctx: ctx, at: CGPoint(x: 0.795, y: 0.775), radius: 62, color: rgb(1, 1, 1, 0.95), glow: nil)
    drawSparkle(ctx: ctx, at: CGPoint(x: 0.205, y: 0.290), radius: 40, color: rgb(1, 1, 1, 0.85), glow: nil)

    ctx.addPath(roundedTrianglePath(scale: 0.92))
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillPath()

    return ctx.makeImage()!
}

// MARK: - main

let args = CommandLine.arguments
let outputDir = args.count > 1
    ? URL(fileURLWithPath: args[1])
    : URL(fileURLWithPath: "AppIcon.appiconset")

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

writePNG(renderDefault(), to: outputDir.appendingPathComponent("AppIcon-1024.png"))
writePNG(renderDark(), to: outputDir.appendingPathComponent("AppIcon-1024-dark.png"))
writePNG(renderTinted(), to: outputDir.appendingPathComponent("AppIcon-1024-tinted.png"))
