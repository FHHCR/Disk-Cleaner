# Cleaner.ps1 - 回收站清理模块
# 提供以下函数：
#   Move-ToRecycleBin - 将文件/目录移入回收站（可恢复）
#   Get-RecycleBinStats - 获取回收站当前状态

# 将文件/目录移入回收站（可恢复，使用 Microsoft.VisualBasic.FileIO）
function Move-ToRecycleBin {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$FilePaths,

        [switch]$IsRecycleBinCategory
    )

    # 加载 Microsoft.VisualBasic 程序集（提供回收站 API）
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue

    $results = @()

    foreach ($path in $FilePaths) {
        try {
            if (Test-Path $path -PathType Leaf) {
                # 文件 → 移入回收站（可恢复）
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $path,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
                $results += [PSCustomObject]@{ Path = $path; Status = '成功'; Message = '已移入回收站' }
                Write-LogEntry -Message "清理文件: $path" -Type "CLEAN"
            }
            elseif (Test-Path $path -PathType Container) {
                # 目录 → 移入回收站（可恢复）
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                    $path,
                    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
                )
                $results += [PSCustomObject]@{ Path = $path; Status = '成功'; Message = '已移入回收站' }
                Write-LogEntry -Message "清理目录: $path" -Type "CLEAN"
            }
            else {
                $results += [PSCustomObject]@{ Path = $path; Status = '跳过'; Message = '路径不存在' }
                Write-LogEntry -Message "跳过（不存在）: $path" -Type "ERROR"
            }
        }
        catch {
            $results += [PSCustomObject]@{ Path = $path; Status = '失败'; Message = $_.Exception.Message }
            Write-LogEntry -Message "清理失败: $path - $($_.Exception.Message)" -Type "ERROR"
        }
    }

    return $results
}

# 获取回收站统计信息
function Get-RecycleBinStats {
    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
    try {
        $recycleBin = New-Object -ComObject Shell.Application
        $recycleFolder = $recycleBin.Namespace(0xA)
        $count = 0
        $totalSize = 0
        foreach ($item in $recycleFolder.Items()) {
            $count++
            $size = $recycleFolder.GetDetailsOf($item, 1)
            if ($size -match 'KB') { $totalSize += [double]($size -replace ' KB', '') * 1KB }
            elseif ($size -match 'MB') { $totalSize += [double]($size -replace ' MB', '') * 1MB }
            elseif ($size -match 'GB') { $totalSize += [double]($size -replace ' GB', '') * 1GB }
            elseif ($size -match 'bytes') { $totalSize += [double]($size -replace ' bytes', '') }
        }
        return [PSCustomObject]@{
            Count = $count
            TotalSize = $totalSize
        }
    }
    catch {
        return [PSCustomObject]@{ Count = 0; TotalSize = 0 }
    }
}

# 导出模块函数
