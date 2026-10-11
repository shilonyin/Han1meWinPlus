# 从主矢量图派生 assets 下的锁标变体
#
# 主文件是 docs/logo-lockup.svg（README 顶部那张），assets 下的变体都由它生成，
# 保证各处用的是同一份字形，不会各画各的。
#
# 为什么要脚本而不是手工存几个文件：三个变体之间只有几何差异（图标缩小、文字平移），
# 把这些数字固化下来，以后换主图只要重跑一次，不会漏掉某一个变体。
#
# 用法（仓库根目录）：
#   python tools\shot\make-logo-variants.py
#   python tools\shot\make-logo-variants.py --check   # 只比对是否已是最新，不写盘

import argparse
import io
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
MASTER = os.path.join(ROOT, 'docs', 'logo-lockup.svg')
OUT_DIR = os.path.join(ROOT, 'assets')

# --- compact 变体的几何参数 ---
#
# 这两个数字是从现有的 assets/logo_lockup_compact.png 上量出来的：
#   主图（1286x254）  图标 x0..273 y9..244（274x236）   文字 x336..1285 y75..179（950x105）
#   compact（1161x159）图标 x0..171 y6..152（172x147）  文字 x211..1160 y27..131（950x105）
# 文字尺寸两者完全一致（都是 950x105），说明 compact 只缩小了图标、文字没动，
# 所以文字用纯平移、图标用等比缩放即可，不需要重新描摹（描摹会毁掉曲线质量）。
ICON_SCALE = 0.626      # 172/274 ≈ 0.628、147/235.5 ≈ 0.624，取中间值
ICON_TRANSLATE_Y = 0.13  # 主图图标顶边 9.38 * 0.626 = 5.87，要对齐到 6
TEXT_DX = -125.0         # 211 - 336
TEXT_DY = -48.0          # 27 - 75
COMPACT_W, COMPACT_H = 1161, 159


def read_master():
    """解析主图，按填充色分出图标（红底 + 白 H）与文字三块。"""
    s = io.open(MASTER, encoding='utf-8').read()
    paths = re.findall(r'<path\b[^>]*/>', s)
    if len(paths) != 3:
        raise SystemExit(f'主图里期望 3 条 path，实际 {len(paths)} 条；结构变了，请先核对')
    by_fill = {}
    for p in paths:
        fill = re.search(r'fill="(#[0-9A-Fa-f]{6})"', p).group(1).upper()
        by_fill[fill] = p
    for need in ('#ED507E', '#FFFFFF', '#6B96B9'):
        if need not in by_fill:
            raise SystemExit(f'主图里找不到 {need} 的路径')
    return by_fill


def build_light(by_fill):
    """完整版：与主图一致。"""
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1286" height="254" '
        'viewBox="0 0 1286 254">\n'
        f'  {by_fill["#ED507E"]}\n'
        f'  {by_fill["#FFFFFF"]}\n'
        f'  {by_fill["#6B96B9"]}\n'
        '</svg>\n'
    )


def build_compact(by_fill):
    """紧凑版：图标缩小、文字平移，给标题栏用（图标:字标 = 1.5:1）。"""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{COMPACT_W}" height="{COMPACT_H}" '
        f'viewBox="0 0 {COMPACT_W} {COMPACT_H}">\n'
        f'  <g transform="translate(0 {ICON_TRANSLATE_Y}) scale({ICON_SCALE})">\n'
        f'    {by_fill["#ED507E"]}\n'
        f'    {by_fill["#FFFFFF"]}\n'
        '  </g>\n'
        f'  <g transform="translate({TEXT_DX} {TEXT_DY})">\n'
        f'    {by_fill["#6B96B9"]}\n'
        '  </g>\n'
        '</svg>\n'
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true',
                    help='只检查文件是否与生成结果一致，不写盘')
    args = ap.parse_args()

    by_fill = read_master()
    targets = {
        os.path.join(OUT_DIR, 'logo_lockup.svg'): build_light(by_fill),
        os.path.join(OUT_DIR, 'logo_lockup_compact.svg'): build_compact(by_fill),
    }

    stale = []
    for path, content in targets.items():
        name = os.path.relpath(path, ROOT)
        old = io.open(path, encoding='utf-8').read() if os.path.exists(path) else None
        if old == content:
            print(f'一致  {name}')
            continue
        stale.append(name)
        if args.check:
            print(f'过期  {name}')
        else:
            io.open(path, 'w', encoding='utf-8', newline='\n').write(content)
            print(f'已写入 {name}')

    if args.check and stale:
        sys.exit(1)


if __name__ == '__main__':
    main()
