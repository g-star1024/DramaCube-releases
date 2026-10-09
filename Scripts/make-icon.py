#!/usr/bin/env python3
"""剧立方 DramaCube — macOS App 图标生成。

设计：深紫黑渐变 squircle 底 + 等距立方体（三面粉：粉/深粉/浅粉）+ 白色播放三角。
规范：1024 画布、824pt 图形区居中、185px 圆角、四角透明。
输出：AppIcon-1024.png + iconset + AppIcon.icns
"""
from PIL import Image, ImageDraw, ImageFilter
import math, subprocess, os, sys

S = 4  # 4x 超采样抗锯齿
CANVAS = 1024 * S
BOX = 824 * S          # macOS 规范图形区
MARGIN = (CANVAS - BOX) // 2
RADIUS = 185 * S

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "logo-src")

# ---------- 渐变底（深紫黑，左上亮右下暗） ----------
def diagonal_gradient(size, c1, c2):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    # 归一化对角距离查色
    for y in range(h):
        for x in range(0, w, 1):
            t = (x + y) / (w + h)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img

# 逐像素渐变在 4096 下太慢，用小图放大替代
def fast_gradient(size, c1, c2):
    small = diagonal_gradient((256, 256), c1, c2)
    return small.resize(size, Image.BICUBIC)

# ---------- 立方体 ----------
def draw_cube(draw, T, L, R, M, LL, LR, B):
    """尖角等距立方体：三面纯色 + 棱线高光。"""
    draw.polygon([T, R, M, L], fill=(255, 128, 156, 255))   # 顶面（浅粉）
    draw.polygon([L, M, B, LL], fill=(255, 45, 85, 255))    # 左面（品牌粉）
    draw.polygon([M, R, LR, B], fill=(179, 18, 61, 255))    # 右面（深粉）
    edge_color = (255, 255, 255, 70)
    for a, b in [(T, M), (L, M), (R, M), (M, B)]:
        draw.line([a, b], fill=edge_color, width=int(2.2 * S))

def main():
    base = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    # ---- squircle 底 ----
    grad = fast_gradient((BOX, BOX), (46, 26, 66), (16, 9, 30))  # 深紫 → 近黑
    mask = Image.new("L", (BOX, BOX), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, BOX - 1, BOX - 1], radius=RADIUS, fill=255)
    base.paste(grad, (MARGIN, MARGIN), mask)

    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    # ---- 底部投影 ----
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    cx, cy = 512 * S, 828 * S
    sd.ellipse([cx - 250 * S, cy - 58 * S, cx + 250 * S, cy + 58 * S], fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30 * S))

    # ---- 等距立方体 ----
    # 注意：坐标以 1024 逻辑画布为准，pt() 只做超采样缩放（不再加 MARGIN，
    # 否则图形整体偏移到右下角）。
    def pt(x, y):
        return (x * S, y * S)

    T  = pt(512, 256)   # 顶
    L  = pt(292, 384)   # 左上
    R  = pt(732, 384)   # 右上
    M  = pt(512, 512)   # 中心
    LL = pt(292, 640)   # 左下
    LR = pt(732, 640)   # 右下
    B  = pt(512, 768)   # 底

    draw_cube(draw, T, L, R, M, LL, LR, B)

    # ---- 播放三角（白色，带轻投影，光学位移） ----
    tri_cx, tri_cy = 536, 512
    size = 118
    tri = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    td = ImageDraw.Draw(tri)
    t1 = pt(tri_cx - size * 0.42, tri_cy - size * 0.6)
    t2 = pt(tri_cx - size * 0.42, tri_cy + size * 0.6)
    t3 = pt(tri_cx + size * 0.58, tri_cy)
    t_shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(t_shadow).polygon([t1, t2, t3], fill=(0, 0, 0, 90))
    t_shadow = t_shadow.filter(ImageFilter.GaussianBlur(10 * S))
    td.polygon([(t1[0] - 3 * S, t1[1] - 3 * S), (t2[0] - 3 * S, t2[1] + 3 * S), (t3[0] + 3 * S, t3[1])],
               fill=(255, 255, 255, 255))

    # ---- 顶部内高光（细弧线，macOS 质感） ----
    gloss = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    gd.rounded_rectangle([MARGIN + 6 * S, MARGIN + 6 * S, MARGIN + BOX - 6 * S, MARGIN + BOX - 6 * S],
                         radius=RADIUS - 6 * S, outline=(255, 255, 255, 28), width=int(3 * S))

    # ---- 合成 ----
    base = Image.alpha_composite(base, shadow)
    base = Image.alpha_composite(base, layer)
    base = Image.alpha_composite(base, t_shadow)
    base = Image.alpha_composite(base, tri)
    base = Image.alpha_composite(base, gloss)

    # ---- 下采样输出 ----
    final = base.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(OUT_DIR, exist_ok=True)
    src = os.path.join(OUT_DIR, "AppIcon-1024.png")
    final.save(src)

    # ---- iconset + icns ----
    iconset = os.path.join(OUT_DIR, "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for name, size in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                       ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                       ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                       ("icon_512x512@2x", 1024)]:
        subprocess.run(["sips", "-z", str(size), str(size), src, "--out",
                        os.path.join(iconset, f"{name}.png")], capture_output=True)
    icns = os.path.join(os.path.dirname(OUT_DIR), "..", "Resources", "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.abspath(icns)], capture_output=True)
    print("OK ->", os.path.abspath(icns))

if __name__ == "__main__":
    sys.exit(main())
