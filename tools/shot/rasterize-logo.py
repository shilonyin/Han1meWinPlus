# 从矢量图重新栅格化位图资源
#
# 背景：托盘图标、原生启动画面、app 图标这三处只能用位图——托盘由 cnativeapi
# 用 GDI+ 加载（见 image_windows.cpp 的 Gdiplus::Bitmap），原生启动画面同样走
# GDI+（windows/runner/main.cpp 的 StartupLockup），app 图标则由构建期工具栅格化。
# GDI+ 不认 SVG，所以这些位置只能喂位图。
#
# 但这个位图不该是「设计稿导出的那张」——那张只有 1286x254，笔画边缘的抗锯齿
# 过渡只有 2-3 像素。这里以 docs/logo-lockup.svg 为源重新渲染，边缘由矢量直接
# 采样得出，与 README / 应用内用的字形保证同一份。
#
# 渲染器用 resvg（Rust 实现，渲染质量与主流浏览器一致）。
#
# 用法（仓库根目录）：
#   python tools\shot\rasterize-logo.py            # 重新生成
#   python tools\shot\rasterize-logo.py --check    # 只比对是否需要更新

import argparse
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MASTER = os.path.join(ROOT, 'docs', 'logo-lockup.svg')

# 目标位图与尺寸。
#
# 尺寸怎么定的：
# - logo_lockup*.png 沿用 1286x254（现有位图的尺寸，各处按高度缩放显示）
# - logo.png 沿用 1024x1024，但它是**方形图标**（红底 + 白 H，无文字），
#   需要从主图里把图标部分单独取出来再居中
LOCKUPS = [
    ('assets/logo_lockup.png', 1286, 254, None, False),
    ('assets/logo_lockup_dark.png', 1286, 254, '#E9ECF1', False),
]
ICON_PNG = ('assets/logo.png', 1024, 1024)
ICON_DARK_TEXT = '#E9ECF1'  # dark 版字标颜色，实测 (233,236,241)

# Windows 打包图标（.ico）。
#
# 为什么也由这里生成：它和上面的 logo.png 是**同一张方形图标**，只是格式不同 ——
# ico 供 exe 的资源段（windows/runner/Runner.rc 的 IDI_APP_ICON）、安装程序
# （installer.iss 的 SetupIconFile）以及启动画面（main.cpp 的 StartupIcon）使用。
#
# 这里曾经漏掉过它：2026-10-11 那次「位图资源改由矢量图重渲染」更新了
# assets/*.png（修掉了旧图纵向拉伸 8% 的问题），但没重新生成 .ico，于是
# exe 图标和安装包图标一直停留在更早的那版。补上这一项，两者就同样源自主图。
#
# 尺寸档位沿用原来的 6 档（16/32/48/64/128/256），够覆盖资源管理器各视图、
# 任务栏、开始菜单与安装程序的显示需求。
ICON_ICO = 'windows/runner/resources/app_icon.ico'
ICO_SIZES = [16, 32, 48, 64, 128, 256]


def read_master():
    s = io.open(MASTER, encoding='utf-8').read()
    paths = re.findall(r'<path\b[^>]*/>', s)
    if len(paths) != 3:
        raise SystemExit(f'主图里期望 3 条 path，实际 {len(paths)} 条')
    by_fill = {}
    for p in paths:
        fill = re.search(r'fill="(#[0-9A-Fa-f]{6})"', p).group(1).upper()
        by_fill[fill] = p
    for need in ('#ED507E', '#FFFFFF', '#6B96B9'):
        if need not in by_fill:
            raise SystemExit(f'主图里找不到 {need} 的路径')
    return by_fill


def render(svg_text, width, height):
    """用 resvg 渲染成 PIL 图像。

    渲染策略显式指定为几何精度优先：这些位图会被缩放到 16~56px 显示，
    边缘抗锯齿的质量直接决定观感，用默认的 optimize_speed 会明显发虚。
    """
    import resvg_py
    png_bytes = resvg_py.svg_to_bytes(
        svg_string=svg_text,
        width=width,
        height=height,
        shape_rendering='geometric_precision',
        image_rendering='optimize_quality',
    )
    from PIL import Image
    return Image.open(io.BytesIO(bytes(png_bytes))).convert('RGBA')


def build_lockup(by_fill, text_fill):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1286" height="254" '
        'viewBox="0 0 1286 254">\n'
        f'  {by_fill["#ED507E"]}\n'
        f'  {by_fill["#FFFFFF"]}\n'
        f'  {by_fill["#6B96B9"].replace("#6B96B9", text_fill)}\n'
        '</svg>\n'
    )


def build_icon(by_fill):
    """方形图标：只取主图的图标部分，等比缩放到目标尺寸后居中。

    尺寸决策（实测数据）：
    - 主图里图标是 274x236，宽高比 1.166
    - 旧版 logo.png 里是 1024x949，宽高比 1.079 —— 比主图纵向拉伸了约 8%，
      说明旧方形图标是另一份图稿。
    这里**按主图原比例**放置、不做拉伸：字形最正，且与 README / 应用内各处
    同源。因此高度不会占满旧版那个 92.7%，这是预期结果。
    """
    box = (0, 9, 274, 236)   # 图标在主图里的范围，实测
    target = 1024
    scale = target / box[2]
    w = box[2] * scale
    h = box[3] * scale
    tx = (target - w) / 2 - box[0] * scale
    ty = (target - h) / 2 - box[1] * scale
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{target}" height="{target}" '
        f'viewBox="0 0 {target} {target}">\n'
        f'  <g transform="translate({tx:.2f} {ty:.2f}) scale({scale:.6f})">\n'
        f'    {by_fill["#ED507E"]}\n'
        f'    {by_fill["#FFFFFF"]}\n'
        '  </g>\n'
        '</svg>\n'
    )


def build_native_icon_png(by_fill):
    """方形图标的 PIL 图像（1024x1024），供 .ico 使用。

    与写进 assets/logo.png 的是同一个 build_icon 画法，保证 exe 图标、安装包
    图标与应用内看到的方形图标完全一致。
    """
    icon_rel, iw, ih = ICON_PNG
    return render(build_icon(by_fill), iw, ih)


def png_bytes_equivalent(path, img):
    """把渲染结果编码成 PNG 字节，用于和磁盘上的文件比对。"""
    buf = io.BytesIO()
    img.save(buf, format='PNG', optimize=True)
    return buf.getvalue()


def build_ico_bytes(icon_img):
    """由方形图标生成多尺寸 .ico 的字节。

    每一档都从 1024 的母图**独立**降采样，而不是从上一档继续缩 —— 逐级缩小会
    累积重采样误差，16x16 那档会明显发糊。
    """
    from PIL import Image
    buf = io.BytesIO()
    # sizes 交给 Pillow 逐档生成；append_images 不用，它会自己按 sizes 缩。
    icon_img.save(buf, format='ICO', sizes=[(s, s) for s in ICO_SIZES])
    return buf.getvalue()


def ico_frame_digest(data):
    """把 .ico 解码成「各档位像素的摘要」，用于 --check 时的语义比对。

    .ico 是容器格式，同一份图像用不同工具写出的字节流未必一致（Pillow 每次
    写入还可能带时间戳），直接比字节会永远报「需更新」。这里改成比像素。
    """
    import hashlib
    from PIL import Image
    im = Image.open(io.BytesIO(data))
    parts = []
    for size in sorted(im.info.get('sizes', [])):
        frame = im.ico.getimage(size).convert('RGBA')
        parts.append(f'{size[0]}x{size[1]}:' + hashlib.sha256(frame.tobytes()).hexdigest())
    return '\n'.join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true', help='只检查是否需要更新')
    args = ap.parse_args()

    by_fill = read_master()
    jobs = []
    for rel, w, h, text_fill, _ in LOCKUPS:
        jobs.append((rel, build_lockup(by_fill, text_fill or '#6B96B9'), w, h))
    icon_rel, iw, ih = ICON_PNG
    jobs.append((icon_rel, build_icon(by_fill), iw, ih))

    stale = []
    for rel, svg_text, w, h in jobs:
        path = os.path.join(ROOT, rel)
        img = render(svg_text, w, h)
        new_bytes = png_bytes_equivalent(path, img)
        old = open(path, 'rb').read() if os.path.exists(path) else None
        if old is not None and old == new_bytes:
            print(f'一致  {rel}')
            continue
        stale.append(rel)
        if args.check:
            print(f'需更新 {rel}')
        else:
            with open(path, 'wb') as f:
                f.write(new_bytes)
            print(f'已写入 {rel}  ({w}x{h}, {len(new_bytes)/1024:.1f} KB)')

    # 打包图标：与 assets/logo.png 同源的方形图标，只是写成多尺寸 ico。
    # 比对用像素摘要而非字节（见 ico_frame_digest 的说明）。
    ico_path = os.path.join(ROOT, ICON_ICO)
    ico_new = build_ico_bytes(build_native_icon_png(by_fill))
    if os.path.exists(ico_path):
        try:
            same = ico_frame_digest(open(ico_path, 'rb').read()) == ico_frame_digest(ico_new)
        except Exception as exc:                     # 旧文件损坏 / 格式不认识
            print(f'  （现有 {ICON_ICO} 无法解析：{exc}）')
            same = False
    else:
        same = False

    if same:
        print(f'一致  {ICON_ICO}')
    else:
        stale.append(ICON_ICO)
        if args.check:
            print(f'需更新 {ICON_ICO}')
        else:
            with open(ico_path, 'wb') as f:
                f.write(ico_new)
            print(f'已写入 {ICON_ICO}  ({"/".join(str(s) for s in ICO_SIZES)}, {len(ico_new)/1024:.1f} KB)')

    if args.check and stale:
        sys.exit(1)


if __name__ == '__main__':
    main()
