# DiskScanner.ps1 - 磁盘和文件扫描模块
# 提供以下函数：
#   Get-DiskList - 枚举所有可用磁盘（固定磁盘）
#   Get-CategoryPaths - 返回各类别的路径映射
#   Get-FileByCategory - 按类别扫描文件

# 枚举所有可用磁盘（固定磁盘，DriveType=3）
function Get-DiskList {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            DriveLetter = $_.DeviceID
            VolumeLabel = $_.VolumeName
            TotalSizeGB = if ($_.Size) { [math]::Round($_.Size / 1GB, 2) } else { 0 }
            FreeSpaceGB = if ($_.FreeSpace) { [math]::Round($_.FreeSpace / 1GB, 2) } else { 0 }
        }
    }
}

# 返回各类别的路径映射（与所选磁盘关联）
# 如果磁盘是系统盘（通常 C:），使用用户主目录的标准路径
# 如果磁盘是其他盘，扫描该磁盘上的用户目录（如果存在）
function Get-CategoryPaths {
    param(
        [string]$DriveLetter = "$env:SystemDrive"
    )

    $driveRoot = if ($DriveLetter -match '^[A-Za-z]:$') { $DriveLetter + '\' } else { $DriveLetter }

    # 判断是否系统盘（通常 C:）
    $isSystemDrive = ($DriveLetter -eq "$env:SystemDrive")

    # 确定用户目录基准路径
    if ($isSystemDrive) {
        $baseUserDir = $env:USERPROFILE
        $baseLocalAppData = $env:LOCALAPPDATA
        $tempDir = $env:TEMP
        $recyclePath = Join-Path $driveRoot '$Recycle.Bin'
    }
    else {
        # 非系统盘：尝试在该磁盘上找用户目录，否则用盘根目录
        $baseUserDir = Join-Path $driveRoot "Users\$env:USERNAME"
        if (-not (Test-Path $baseUserDir)) {
            $baseUserDir = $driveRoot
        }
        $baseLocalAppData = Join-Path $baseUserDir 'AppData\Local'
        $tempDir = Join-Path $driveRoot 'Temp'
        $recyclePath = Join-Path $driveRoot '$Recycle.Bin'
    }

    $categories = @(
        [PSCustomObject]@{ Name = '下载文件'; Path = (Join-Path $baseUserDir 'Downloads'); Extensions = @('*') },
        [PSCustomObject]@{ Name = '图片'; Path = (Join-Path $baseUserDir 'Pictures'); Extensions = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff') },
        [PSCustomObject]@{ Name = '文档'; Path = (Join-Path $baseUserDir 'Documents'); Extensions = @('.doc', '.docx', '.pdf', '.txt', '.xls', '.xlsx', '.ppt', '.pptx', '.md', '.csv') },
        [PSCustomObject]@{ Name = '视频'; Path = (Join-Path $baseUserDir 'Videos'); Extensions = @('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm') },
        [PSCustomObject]@{ Name = '临时文件'; Path = $tempDir; Extensions = @('*') },
        [PSCustomObject]@{ Name = '回收站'; Path = $recyclePath; Extensions = @('*') },
        [PSCustomObject]@{ Name = '缩略图缓存'; Path = (Join-Path $baseLocalAppData 'Microsoft\Windows\Explorer'); Extensions = @('.db') }
    )
    return $categories
}

# 按类别扫描文件
function Get-FileByCategory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Category,

        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # 路径不存在时返回空数组
    if (-not (Test-Path $Path)) {
        return @()
    }

    # 获取该类别的扩展名过滤
    $categoryInfo = Get-CategoryPaths | Where-Object { $_.Name -eq $Category }
    $extensions = if ($categoryInfo) { $categoryInfo.Extensions } else { @('*') }

    # 扫描文件
    $files = Get-ChildItem -Path $Path -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object {
            if ($extensions -contains '*') {
                $true
            } else {
                $extensions -contains $_.Extension.ToLower()
            }
        } |
        ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Size = $_.Length
                Path = $_.FullName
                LastModified = $_.LastWriteTime
                Category = $Category
            }
        } |
        Sort-Object Size -Descending

    return $files
}

# 导出模块函数
