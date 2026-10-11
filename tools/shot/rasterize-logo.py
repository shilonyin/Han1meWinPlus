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


def png_bytes_equivalent(path, img):
    """把渲染结果编码成 PNG 字节，用于和磁盘上的文件比对。"""
    buf = io.BytesIO()
    img.save(buf, format='PNG', optimize=True)
    return buf.getvalue()


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

    if args.check and stale:
        sys.exit(1)


if __name__ == '__main__':
    main()
