"""抓播放窗口的画面，确认底部控制条与暂停标记的观感。

离屏抓取（PrintWindow + PW_RENDERFULLCONTENT），不要求窗口在前台。
用法：python tools/shot/snap-play-window.py [输出名]
"""

import ctypes
import os
import sys
import time
from ctypes import wintypes

from PIL import Image

try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

PW_RENDERFULLCONTENT = 2


def find_play_window():
    """播放窗口与主窗口同名，靠窗口尺寸挑：主窗口通常更宽。"""
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _):
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, buf, 256)
        if buf.value != "Han1meWinPlusWindow":
            return True
        if not user32.IsWindowVisible(hwnd):
            return True
        r = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        found.append((hwnd, r.right - r.left, r.bottom - r.top))
        return True

    user32.EnumWindows(cb, 0)
    return found


def grab(hwnd, w, h):
    hdc = user32.GetWindowDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, PW_RENDERFULLCONTENT)

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [
            ("biSize", wintypes.DWORD),
            ("biWidth", wintypes.LONG),
            ("biHeight", wintypes.LONG),
            ("biPlanes", wintypes.WORD),
            ("biBitCount", wintypes.WORD),
            ("biCompression", wintypes.DWORD),
            ("biSizeImage", wintypes.DWORD),
            ("biXPelsPerMeter", wintypes.LONG),
            ("biYPelsPerMeter", wintypes.LONG),
            ("biClrUsed", wintypes.DWORD),
            ("biClrImportant", wintypes.DWORD),
        ]

    bi = BITMAPINFOHEADER()
    bi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.biWidth = w
    bi.biHeight = -h  # 负值 = 自顶向下
    bi.biPlanes = 1
    bi.biBitCount = 32
    bi.biCompression = 0

    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bi), 0)

    img = Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB")

    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(hwnd, hdc)
    return img


name = sys.argv[1] if len(sys.argv) > 1 else "play"
wins = find_play_window()
if not wins:
    raise SystemExit("找不到 Han1meWinPlusWindow 窗口，先启动应用")

for hwnd, w, h in wins:
    print("窗口 hwnd=%s %dx%d" % (hwnd, w, h))

hwnd, w, h = max(wins, key=lambda x: x[1] * x[2])
# 真实鼠标移动唤出控制条（MouseRegion.onHover），不需要点击、不需要前台。
cx, cy = 900, 500
for dx in range(0, 40, 8):
    user32.SetCursorPos(cx + dx, cy)
    time.sleep(0.03)
time.sleep(0.35)

os.makedirs("build/theme-transition", exist_ok=True)
out = "build/theme-transition/%s.png" % name
grab(hwnd, w, h).save(out)
print("已保存", out)
