#!/usr/bin/env python3
"""剧立方 DramaCube — Flutter 全平台图标生成（极简播放键 logo）。

源图：outputs/logo-candidates/Ultra_minimal_app_icon...（粉-橙渐变圆角方 + 白色播放三角，
纯白画布背景，右下角「AI生成」小水印）。
处理：纯白画布 → 透明（保留形状边缘）；裁掉右下角水印区；按各平台尺寸缩放输出。
输出：macOS appiconset / Android mipmap / web icons+favicon / Windows app_icon.ico。
"""
from PIL import Image
import os, subprocess, shutil

SRC = ("/Users/huluobo/WorkBuddy/2026-10-09-08-54-58/outputs/logo-candidates/"
       "Ultra_minimal_app_icon__a_roun_2026-10-12T13-18-57.png")
APP = "/Users/huluobo/WorkBuddy/2026-10-09-08-54-58/hongguo-desktop/apps/flutter"


def content_alpha(img):
    """纯白画布 → 透明（其余像素含渐变形状全保留）。迭代 3 次吃掉锯齿白的半透明过渡。"""
    img = img.convert("RGBA")
    data = list(img.getdata())
    out = []
    for r, g, b, a in data:
        # 白色（纯白及近白）→ 透明
        if r > 245 and g > 245 and b > 245:
            out.append((r, g, b, 0))
        else:
            out.append((r, g, b, a))
    img.putdata(out)
    return img


def inpaint_watermark(img):
    """右下角水印文字（低饱和浅色，约 x0.88-0.97/y0.88-0.97）向四周采样最近
    高饱和渐变色填充（该位置紧邻形状圆角边缘，不能整区挖空，只能逐像素修补）。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    x0, x1 = int(w * 0.86), w
    y0, y1 = int(h * 0.86), h

    def is_wm(r, g, b):
        mx, mn = max(r, g, b), min(r, g, b)
        return (mx - mn) < 42 and 120 < mx < 245  # 低饱和浅色（粉橙渐变高饱和）

    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a == 0 or not is_wm(r, g, b):
                continue
            # 向 8 邻域外扩找最近非水印、非透明像素取色
            best = None
            for rad in range(1, 40):
                for dy in range(-rad, rad + 1):
                    for dx in range(-rad, rad + 1):
                        nx, ny = x + dx, y + dy
                        if not (0 <= nx < w and 0 <= ny < h):
                            continue
                        nr, ng, nb, na = px[nx, ny]
                        if na > 0 and not is_wm(nr, ng, nb):
                            best = (nr, ng, nb, 255)
                            break
                    if best:
                        break
                if best:
                    break
            if best:
                px[x, y] = best
    return img


def load_master():
    img = Image.open(SRC)
    img = content_alpha(img)   # 白色画布 → 透明（保留渐变形状）
    img = inpaint_watermark(img)  # 修补右下角水印
    return img


def save(img, size, path, opaque=False):
    out = img.resize((size, size), Image.LANCZOS)
    if opaque:  # Android 启动图标等需不透明底：贴白底（透明角→白）
        bg = Image.new("RGBA", (size, size), (255, 255, 255, 255))
        bg = Image.alpha_composite(bg, out)
        out = bg.convert("RGB")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    return path


def main():
    m = load_master()
    made = []

    # ---- macOS appiconset（文件名即 Contents.json 引用的） ----
    mac = f"{APP}/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        made.append(save(m, size, f"{mac}/app_icon_{size}.png"))

    # ---- Android mipmap（不透明底，避免启动黑角） ----
    for dpi, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)]:
        made.append(save(m, size, f"{APP}/android/app/src/main/res/mipmap-{dpi}/ic_launcher.png", opaque=True))

    # ---- Web ----
    made.append(save(m, 192, f"{APP}/web/icons/Icon-192.png"))
    made.append(save(m, 512, f"{APP}/web/icons/Icon-512.png"))
    made.append(save(m, 192, f"{APP}/web/icons/Icon-maskable-192.png", opaque=True))
    made.append(save(m, 512, f"{APP}/web/icons/Icon-maskable-512.png", opaque=True))
    made.append(save(m, 64, f"{APP}/web/favicon.png", opaque=True))

    # ---- Windows .ico（多尺寸嵌入） ----
    ico_path = f"{APP}/windows/runner/resources/app_icon.ico"
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    m.save(ico_path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                            (64, 64), (128, 128), (256, 256)])
    made.append(ico_path)

    print("生成完成：")
    for p in made:
        print(" ", os.path.relpath(p, APP), os.path.getsize(p), "B")


if __name__ == "__main__":
    main()
