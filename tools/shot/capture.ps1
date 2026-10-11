# 应用窗口截图工具 —— 用 PrintWindow 抓窗口本身，不受遮挡与 DPI 影响
#
# 用法（在仓库根目录执行）：
#   .\tools\shot\capture.ps1 -Out docs\screenshots\appearance.png
#   .\tools\shot\capture.ps1 -Out out.png -ProcessName han1me_win_plus
#   .\tools\shot\capture.ps1 -List        # 只列出候选窗口
#
# 为什么不用 CopyFromScreen：本机 DPI 是 150%，GetWindowRect 返回逻辑坐标，
# CopyFromScreen 却按物理像素取景，两者一叠加就会把窗口外的桌面一起截进来。
# PrintWindow 让窗口自己渲染到内存 DC，坐标由系统换算，天然避开这个坑。

[CmdletBinding()]
param(
    [string]$Out,
    [string]$ProcessName = 'han1me_win_plus',
    [switch]$List,
    # 目标逻辑尺寸，默认沿用仓库现有截图的 1280x720 构图
    [int]$Width = 1280,
    [int]$Height = 720
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not ('Win' -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
}

function Get-AppWindow {
    param([string]$Name)
    $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 }
    if (-not $procs) { throw "没有找到带主窗口的进程：$Name" }
    return $procs | Select-Object -First 1
}

if ($List) {
    Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | ForEach-Object {
        $r = New-Object Win+RECT
        $hasWin = $_.MainWindowHandle -ne 0
        if ($hasWin) { [Win]::GetWindowRect($_.MainWindowHandle, [ref]$r) | Out-Null }
        $physW = if ($hasWin) { $r.Right - $r.Left } else { 0 }
        $physH = if ($hasWin) { $r.Bottom - $r.Top } else { 0 }
        $scale = if ($hasWin) { [Win]::GetDpiForWindow($_.MainWindowHandle) / 96.0 } else { 1 }
        [PSCustomObject]@{
            PID       = $_.Id
            Title     = $_.MainWindowTitle
            '物理尺寸' = if ($hasWin) { "${physW}x${physH}" } else { '-' }
            '逻辑尺寸' = if ($hasWin) { "$([int][Math]::Round($physW / $scale))x$([int][Math]::Round($physH / $scale))" } else { '-' }
        }
    } | Format-Table -AutoSize
    return
}

if (-not $Out) { throw '必须指定 -Out，或用 -List 只看窗口列表' }

$proc = Get-AppWindow -Name $ProcessName
$handle = $proc.MainWindowHandle

# 最小化状态下 PrintWindow 抓不到内容，先还原
if ([Win]::IsIconic($handle)) {
    [Win]::ShowWindow($handle, 9) | Out-Null
    Start-Sleep -Milliseconds 600
}
[Win]::SetForegroundWindow($handle) | Out-Null
Start-Sleep -Milliseconds 400

$rect = New-Object Win+RECT
[Win]::GetWindowRect($handle, [ref]$rect) | Out-Null
# 注意：GetWindowRect 返回的已经是**物理像素**（本机 150% DPI 下实测如此），
# 不要再乘 DPI 系数，否则会抓歪——这是踩过的坑。
$physW = $rect.Right - $rect.Left
$physH = $rect.Bottom - $rect.Top

$dpi = [Win]::GetDpiForWindow($handle)
$scale = $dpi / 96.0
$logicalW = [int][Math]::Round($physW / $scale)
$logicalH = [int][Math]::Round($physH / $scale)

# 尺寸与目标构图不符时只提示，不擅自改窗口（改窗口会丢掉用户当前的浏览状态）
if ($logicalW -ne $Width -or $logicalH -ne $Height) {
    Write-Warning "窗口逻辑尺寸是 ${logicalW}x${logicalH}，与预期的 ${Width}x${Height} 不一致；构图会与 README 现有规格不同。"
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$bmp = New-Object System.Drawing.Bitmap $physW, $physH
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
try {
    $ok = [Win]::PrintWindow($handle, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
} finally {
    $g.ReleaseHdc($hdc)
}

if (-not $ok) {
    $g.Dispose(); $bmp.Dispose()
    throw 'PrintWindow 调用失败'
}

$ext = [System.IO.Path]::GetExtension($Out).ToLowerInvariant()
$fmt = if ($ext -eq '.jpg' -or $ext -eq '.jpeg') {
    [System.Drawing.Imaging.ImageFormat]::Jpeg
} else {
    [System.Drawing.Imaging.ImageFormat]::Png
}
$bmp.Save($Out, $fmt)
$g.Dispose(); $bmp.Dispose()

$size = [math]::Round((Get-Item $Out).Length / 1KB)
Write-Output "已保存 $Out  (${physW}x${physH} 物理, ${logicalW}x${logicalH} 逻辑 @ ${dpi}dpi, ${size} KB)"
