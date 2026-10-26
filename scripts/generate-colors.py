#!/usr/bin/env python3
"""生成明暗双主题的语义色资产（Asset Catalog colorset）。

为什么走 Asset 而不是在 Swift 里根据 colorScheme 算颜色：
SwiftUI 的 static 属性不会随状态变化刷新，如果 Theme 是一堆 static let，
那么切换外观时只有读到 @Environment(\\.colorScheme) 的视图会重建，
散落在各处的 `Theme.ink` 调用点拿到的仍是旧值。
把颜色放进 Asset Catalog 后，`Color("Ink")` 由系统按当前 trait 解析，
所有现有 View 一行都不用改就自动适配。

用法：python3 scripts/generate-colors.py BiliGlass/Resources/Assets.xcassets
"""

import json
import os
import sys

# name -> (light rgba, dark rgba)
PALETTE = {
    # 页面底色：浅色是带粉紫调的近白，深色是近黑的紫蓝
    "CanvasTop": ((0.992, 0.984, 1.000, 1.0), (0.059, 0.051, 0.102, 1.0)),
    "CanvasMid": ((0.957, 0.937, 0.988, 1.0), (0.102, 0.071, 0.161, 1.0)),
    "CanvasBottom": ((0.922, 0.949, 1.000, 1.0), (0.039, 0.071, 0.129, 1.0)),

    # 文字与描边：语义上就是「墨色」，浅色主题下墨是深色
    "Ink": ((0.102, 0.086, 0.149, 1.00), (1.0, 1.0, 1.0, 1.00)),
    "InkDim": ((0.102, 0.086, 0.149, 0.62), (1.0, 1.0, 1.0, 0.62)),
    "InkFaint": ((0.102, 0.086, 0.149, 0.36), (1.0, 1.0, 1.0, 0.38)),

    # 品牌色：浅色主题下要压深，否则在浅底上对比度不够
    "BrandPink": ((0.886, 0.235, 0.455, 1.0), (0.980, 0.420, 0.612, 1.0)),
    "BrandBlue": ((0.106, 0.494, 0.847, 1.0), (0.290, 0.722, 0.961, 1.0)),
    "BrandPurple": ((0.420, 0.310, 0.847, 1.0), (0.549, 0.451, 0.949, 1.0)),
}


def color_entry(rgba, appearances=None):
    entry = {
        "color": {
            "color-space": "srgb",
            "components": {
                "alpha": format(rgba[3], ".3f"),
                "red": format(rgba[0], ".3f"),
                "green": format(rgba[1], ".3f"),
                "blue": format(rgba[2], ".3f"),
            },
        },
        "idiom": "universal",
    }
    if appearances:
        entry["appearances"] = appearances
    return entry


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "BiliGlass/Resources/Assets.xcassets"
    for name, (light, dark) in PALETTE.items():
        folder = os.path.join(root, f"{name}.colorset")
        os.makedirs(folder, exist_ok=True)
        contents = {
            "colors": [
                color_entry(light),
                color_entry(dark, [{"appearance": "luminosity", "value": "dark"}]),
            ],
            "info": {"author": "xcode", "version": 1},
        }
        with open(os.path.join(folder, "Contents.json"), "w", encoding="utf-8") as f:
            json.dump(contents, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"✓ {name}.colorset")


if __name__ == "__main__":
    main()
