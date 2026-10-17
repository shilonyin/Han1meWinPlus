"""点侧栏某个图标，然后抓主窗口画面。

用法：python tools/shot/click-sidebar.py <截图内的 x> <截图内的 y> <输出名>
坐标按 1920x1080 截图内位置给，脚本自己按窗口实际尺寸缩放。
"""

import ctypes
import os
import sys
import time
from ctypes import wintypes

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    user32.SetProcessDPIAware()

OUT = os.path.join("build", "shots")
os.makedirs(OUT, exist_ok=True)

if len(sys.argv) < 4:
    raise SystemExit("用法: click-sidebar.py <x> <y> <name>")
px, py, name = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]


def main_window():
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _):
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(hwnd, buf, 256)
        if buf.value == "Han1meWinPlusWindow" and user32.IsWindowVisible(hwnd):
            rect = wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            found.append(((rect.right - rect.left) * (rect.bottom - rect.top), hwnd, rect))
        return True

    user32.EnumWindows(cb, 0)
    if not found:
        raise SystemExit("找不到窗口")
    found.sort(reverse=True)
    return found[0][1], found[0][2]


def grab(hwnd, rect):
    w, h = rect.right - rect.left, rect.bottom - rect.top
    hdc = user32.GetWindowDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, 2)

    class BIH(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                    ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                    ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                    ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]

    bi = BIH()
    bi.biSize = ctypes.sizeof(BIH)
    bi.biWidth, bi.biHeight = w, -h
    bi.biPlanes, bi.biBitCount = 1, 32
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bi), 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(hwnd, hdc)
    return Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB")


hwnd, rect = main_window()
w, h = rect.right - rect.left, rect.bottom - rect.top
x = rect.left + int(px * w / 1920)
y = rect.top + int(py * h / 1080)
print("窗口", rect.left, rect.top, w, h, "点击", x, y)

user32.SetCursorPos(x, y)
time.sleep(0.2)
user32.mouse_event(0x0002, 0, 0, 0, 0)
user32.mouse_event(0x0004, 0, 0, 0, 0)
time.sleep(2.0)

img = grab(hwnd, rect)
path = os.path.join(OUT, name + ".png")
img.save(path)
print("已保存", path, img.size)
