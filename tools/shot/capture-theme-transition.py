"""点一下侧栏的主题按钮，连拍窗口画面，看过渡是不是硬边界。

用法：python tools/shot/capture-theme-transition.py
输出：build/theme-transition/frame-XX.png
"""

import ctypes
import os
import time
from ctypes import wintypes

from PIL import ImageGrab

# 让本进程按物理像素思考，GetWindowRect / SetCursorPos 都走物理坐标。
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    ctypes.windll.user32.SetProcessDPIAware()

user32 = ctypes.windll.user32

OUT = os.path.join("build", "theme-transition")
os.makedirs(OUT, exist_ok=True)

hwnd = user32.FindWindowW("Han1meWinPlusWindow", None)
if not hwnd:
    raise SystemExit("找不到主窗口，先启动应用")

rect = wintypes.RECT()
user32.GetWindowRect(hwnd, ctypes.byref(rect))
left, top, right, bottom = rect.left, rect.top, rect.right, rect.bottom
print("窗口:", left, top, right, bottom, "尺寸:", right - left, bottom - top)

# 侧栏主题按钮（太阳）的位置。1920x1080 窗口下实测中心在截图内 (52, 900)，
# 其余按钮等比推算，所以按窗口尺寸缩放。
x = left + int(52 * (right - left) / 1920)
y = top + int(900 * (bottom - top) / 1080)
print("点击:", x, y)

user32.SetCursorPos(x, y)
time.sleep(0.15)
user32.mouse_event(0x0002, 0, 0, 0, 0)  # 左键按下
user32.mouse_event(0x0004, 0, 0, 0, 0)  # 左键抬起

t0 = time.perf_counter()
frames = []
for i in range(24):
    img = ImageGrab.grab(bbox=(left, top, right, bottom), all_screens=True)
    frames.append((time.perf_counter() - t0, img))

print("抓帧:", len(frames), "总耗时: %.0f ms" % ((time.perf_counter() - t0) * 1000))
for i, (t, img) in enumerate(frames):
    img.save(os.path.join(OUT, "frame-%02d.png" % i))
    print("  frame-%02d  t=%4.0f ms" % (i, t * 1000))

# 侧栏底色取样：过渡期间这里最能看出有没有变灰。
print("\n侧栏底色（截图内 x=10, y=400）：")
for i, (t, img) in enumerate(frames):
    r, g, b = img.convert("RGB").getpixel((10, 400))
    print("  frame-%02d  t=%4.0f ms  rgb(%3d,%3d,%3d)" % (i, t * 1000, r, g, b))

# 整帧统计：如果过渡是透明度混合，中途会出现大量「低饱和中灰」像素；
# 圆形揭示的交界是硬边界，像素要么接近旧底色、要么接近新底色，中灰极少。
print("\n每帧的「中灰像素」占比（RGB 三通道极差 <12 且亮度在 90..165）：")
for i, (t, img) in enumerate(frames):
    small = img.convert("RGB").resize((320, 180))
    px = list(small.getdata())
    grayish = sum(1 for r, g, b in px if max(r, g, b) - min(r, g, b) < 12 and 90 <= (r + g + b) / 3 <= 165)
    print("  frame-%02d  t=%4.0f ms  %5.2f%%" % (i, t * 1000, grayish * 100.0 / len(px)))
