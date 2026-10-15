# 本地演练 CI 里「Replace artifacts with signed ones」那一步的逻辑。
# 用真实文件搭一个假的 signed/ 目录，验证：
#   1) 两个同名 exe 能被正确区分（不会取错）
#   2) 缺文件时能报错而不是静默通过
#   3) 重打包 zip 后里面确实是新的 exe
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'h1-sign-dryrun'
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $root | Out-Null

# 搭一个仿真的构建产物树
New-Item -ItemType Directory -Path "$root\build\windows\x64\runner\Release" -Force | Out-Null
Set-Content "$root\build\Han1meWinPlus-Setup.exe" 'UNSIGNED-SETUP' -NoNewline
Set-Content "$root\build\windows\x64\runner\Release\han1me_win_plus.exe" 'UNSIGNED-MAIN' -NoNewline
Set-Content "$root\build\windows\x64\runner\Release\flutter_windows.dll" 'DLL' -NoNewline

# 仿 SignPath 返回：故意把安装包放在**后面**，看逻辑是否会取错第一个
New-Item -ItemType Directory -Path "$root\signed" -Force | Out-Null
Set-Content "$root\signed\han1me_win_plus.exe" 'SIGNED-MAIN' -NoNewline
Set-Content "$root\signed\Han1meWinPlus-Setup.exe" 'SIGNED-SETUP' -NoNewline

Push-Location $root
try {
    $signedFiles = Get-ChildItem 'signed' -Filter '*.exe' -Recurse -File
    Write-Host "  signed 目录里找到 $($signedFiles.Count) 个 exe: $($signedFiles.Name -join ', ')"
    if ($signedFiles.Count -ne 2) { throw '预期的两个 exe 没找到' }

    function Take-Signed([string]$fileName) {
        $hit = $signedFiles | Where-Object { $_.Name -eq $fileName } | Select-Object -First 1
        if (-not $hit) { throw "签名产物里找不到 $fileName" }
        return $hit.FullName
    }

    Copy-Item (Take-Signed 'Han1meWinPlus-Setup.exe') 'build\Han1meWinPlus-Setup.exe' -Force
    Copy-Item (Take-Signed 'han1me_win_plus.exe') 'build\windows\x64\runner\Release\han1me_win_plus.exe' -Force

    Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'build\Han1meWinPlus-windows-x64.zip' -Force

    # 断言：对上了才算通过
    $a = Get-Content 'build\Han1meWinPlus-Setup.exe' -Raw
    $b = Get-Content 'build\windows\x64\runner\Release\han1me_win_plus.exe' -Raw
    Write-Host "  安装包内容: $a"
    Write-Host "  主程序内容: $b"
    if ($a -ne 'SIGNED-SETUP') { throw "安装包没被替换，实际是 $a" }
    if ($b -ne 'SIGNED-MAIN') { throw "主程序没被替换，实际是 $b" }

    # zip 里应当是签过的主程序
    Expand-Archive 'build\Han1meWinPlus-windows-x64.zip' -DestinationPath "$root\unzip" -Force
    $c = Get-Content "$root\unzip\han1me_win_plus.exe" -Raw
    Write-Host "  zip 内主程序内容: $c"
    if ($c -ne 'SIGNED-MAIN') { throw "zip 里还是未签名的主程序，实际是 $c" }
    Write-Host "  zip 里还有 dll: $(Test-Path "$root\unzip\flutter_windows.dll")"

    # 缺文件必须报错
    $threw = $false
    try { Take-Signed 'not-there.exe' | Out-Null } catch { $threw = $true }
    Write-Host "  缺文件时是否抛错: $threw"
    if (-not $threw) { throw '缺文件没有报错' }

    Write-Host ''
    Write-Host '  演练全部通过'
}
finally { Pop-Location; Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
