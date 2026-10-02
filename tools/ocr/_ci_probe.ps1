# 临时测试文件：用于验证 CI 审查工作流能跑通并给出有意义的意见
# 这个文件在验证结束后会被删除，不会合并进 win 分支。

function Get-CacheSize {
    param([string]$Path)

    # 递归统计目录大小
    $total = 0
    Get-ChildItem $Path -Recurse -File | ForEach-Object {
        $total += $_.Length
    }
    return $total
}

function Remove-OldCache {
    param([string]$Path, [int]$KeepDays = 30)

    $cutoff = (Get-Date).AddDays(-$KeepDays)
    Get-ChildItem $Path -Recurse -File | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force
}
