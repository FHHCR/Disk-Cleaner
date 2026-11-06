# DiskCleaner.ps1 - 主程序入口
# Windows 磁盘清理工具
# 使用 WPF 界面，用户选择磁盘和清理类别，确认后移入回收站

# ============================================================
# 配置
# ============================================================
$script:RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ============================================================
# 加载模块
# ============================================================
. (Join-Path $script:RootDir 'Modules\Logger.ps1')
. (Join-Path $script:RootDir 'Modules\DiskScanner.ps1')
. (Join-Path $script:RootDir 'Modules\Cleaner.ps1')

# ============================================================
# 加载 WPF 程序集
# ============================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName Microsoft.VisualBasic

# ============================================================
# 加载 XAML 界面
# ============================================================
try {
    $xamlPath = Join-Path $script:RootDir 'UI\MainWindow.xaml'
    if (-not (Test-Path $xamlPath)) {
        throw "找不到界面文件: $xamlPath"
    }
    $xaml = Get-Content $xamlPath -Raw -Encoding UTF8
    $window = [System.Windows.Markup.XamlReader]::Parse($xaml)
}
catch {
    Write-LogEntry -Message "加载 XAML 失败: $($_.Exception.Message)" -Type "ERROR"
    [System.Windows.MessageBox]::Show("加载界面失败: $($_.Exception.Message)", "Disk-Cleaner 错误", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    exit 1
}

# ============================================================
# 全局状态
# ============================================================
$script:ScannedFiles = @()   # 扫描到的文件列表

# ============================================================
# 辅助函数
# ============================================================

# 格式化文件大小
function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    else { return "$Bytes B" }
}

# 获取当前选中的清理类别
function Get-SelectedCategories {
    $selected = @()
    if ($window.FindName('ChkDownloads').IsChecked) { $selected += '下载文件' }
    if ($window.FindName('ChkPictures').IsChecked) { $selected += '图片' }
    if ($window.FindName('ChkDocuments').IsChecked) { $selected += '文档' }
    if ($window.FindName('ChkVideos').IsChecked) { $selected += '视频' }
    if ($window.FindName('ChkTemp').IsChecked) { $selected += '临时文件' }
    if ($window.FindName('ChkRecycleBin').IsChecked) { $selected += '回收站' }
    if ($window.FindName('ChkThumbnails').IsChecked) { $selected += '缩略图缓存' }
    return $selected
}

# 更新状态栏
function Update-Status {
    param([string]$Message, [string]$Stats = '')
    $window.FindName('StatusText').Text = $Message
    $window.FindName('StatsText').Text = $Stats
}

# 更新扫描结果表格
function Update-FileGrid {
    param($Files)
    $grid = $window.FindName('FileGrid')
    $grid.ItemsSource = $null
    if ($Files -and $Files.Count -gt 0) {
        # 为每个文件添加 IsSelected 属性（默认未选中）
        $items = $Files | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                SizeKB = [math]::Round($_.Size / 1KB, 1)
                Path = $_.Path
                LastModified = $_.LastModified
                Category = $_.Category
            }
        }
        $grid.ItemsSource = $items
    }
}

# ============================================================
# 事件处理器
# ============================================================

# --- 扫描按钮 ---
$window.FindName('BtnScan').Add_Click({
    try {
        Update-Status -Message "扫描中..." -Stats ""
        Write-LogEntry -Message "开始扫描" -Type "SCAN"

        # 获取选中的磁盘
        $selectedDisk = $window.FindName('DiskListBox').SelectedItem
        if (-not $selectedDisk) {
            [System.Windows.MessageBox]::Show("请先选择一个磁盘。", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            Update-Status -Message "就绪"
            return
        }

        # 获取选中的类别
        $selectedCategories = Get-SelectedCategories
        if ($selectedCategories.Count -eq 0) {
            [System.Windows.MessageBox]::Show("请至少选择一个清理类别。", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            Update-Status -Message "就绪"
            return
        }

        # 扫描所有选中的类别（关联所选磁盘）
        $allFiles = @()
        $categoryPaths = Get-CategoryPaths -DriveLetter $selectedDisk.DriveLetter
        foreach ($category in $selectedCategories) {
            $categoryInfo = $categoryPaths | Where-Object { $_.Name -eq $category }
            if ($categoryInfo) {
                $files = Get-FileByCategory -Category $category -Path $categoryInfo.Path
                $allFiles += $files
            }
        }

        # 更新界面
        Update-FileGrid -Files $allFiles
        $script:ScannedFiles = $allFiles

        # 计算总大小
        $totalSize = ($allFiles | Measure-Object -Property Size -Sum).Sum
        $totalCount = $allFiles.Count

        Update-Status -Message "扫描完成" -Stats "共 $totalCount 个文件，总大小 $(Format-Size -Bytes $totalSize)"
        Write-LogEntry -Message "扫描完成: $totalCount 个文件" -Type "SCAN"
    }
    catch {
        Update-Status -Message "扫描出错: $($_.Exception.Message)"
        Write-LogEntry -Message "扫描出错: $($_.Exception.Message)" -Type "ERROR"
    }
})

# --- 清理按钮 ---
$window.FindName('BtnClean').Add_Click({
    try {
        # 获取选中的文件（通过 DataGrid 复选框 IsSelected）
        $grid = $window.FindName('FileGrid')
        $selectedItems = @($grid.SelectedItems)

        if ($selectedItems.Count -eq 0) {
            [System.Windows.MessageBox]::Show("请先在文件列表中选中要清理的文件（点击行选中，可按住 Ctrl 多选）。", "提示", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            return
        }

        # 检查是否包含回收站类别
        $isRecycleBin = $false
        $recycleBinChk = $window.FindName('ChkRecycleBin')
        if ($recycleBinChk.IsChecked) {
            $isRecycleBin = $true
        }

        # 计算总大小
        $totalSize = 0
        foreach ($item in $selectedItems) {
            $totalSize += ($item.SizeKB * 1KB)
        }

        # 弹窗确认（警告）
        $warningMessage = "⚠️ 警告 - 确认清理`n`n" +
            "您选择了 $($selectedItems.Count) 个文件，总大小 $(Format-Size -Bytes $totalSize)。`n" +
            "此操作将把所选文件**移入回收站**，可通过回收站恢复。`n`n" +
            "确定要继续吗？"

        if ($isRecycleBin) {
            $warningMessage += "`n`n⚠️ 注意：回收站清理是**不可恢复**的！"
        }

        $confirm = [System.Windows.MessageBox]::Show(
            $warningMessage,
            "确认清理",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            Update-Status -Message "已取消清理"
            Write-LogEntry -Message "用户取消了清理操作" -Type "INFO"
            return
        }

        # 执行清理（移入回收站）
        Update-Status -Message "正在清理..." -Stats ""
        Write-LogEntry -Message "开始清理: $($selectedItems.Count) 个文件" -Type "CLEAN"

        $paths = $selectedItems | ForEach-Object { $_.Path }
        $results = Move-ToRecycleBin -FilePaths $paths

        # 统计结果
        $successCount = ($results | Where-Object { $_.Status -eq '成功' }).Count
        $failCount = ($results | Where-Object { $_.Status -eq '失败' }).Count
        $skipCount = ($results | Where-Object { $_.Status -eq '跳过' }).Count

        # 更新状态
        $summary = "清理完成: 成功 $successCount, 失败 $failCount, 跳过 $skipCount"
        Update-Status -Message $summary
        Write-LogEntry -Message $summary -Type "CLEAN"

        # 清理完成后重新扫描
        $window.FindName('BtnScan').RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
    catch {
        Update-Status -Message "清理出错: $($_.Exception.Message)"
        Write-LogEntry -Message "清理出错: $($_.Exception.Message)" -Type "ERROR"
    }
})

# --- 刷新按钮 ---
$window.FindName('BtnRefresh').Add_Click({
    try {
        Update-Status -Message "刷新中..." -Stats ""
        $diskList = Get-DiskList
        $diskListBox = $window.FindName('DiskListBox')
        $diskListBox.ItemsSource = $null
        $diskListBox.ItemsSource = $diskList | ForEach-Object {
            [PSCustomObject]@{
                DriveLetter = $_.DriveLetter
                VolumeLabel = if ($_.VolumeLabel) { $_.VolumeLabel } else { '本地磁盘' }
                FreeSpaceGB = $_.FreeSpaceGB
                TotalSizeGB = $_.TotalSizeGB
                DisplayText = "$($_.DriveLetter)  $($_.FreeSpaceGB) GB 可用"
            }
        }
        Update-Status -Message "就绪"
        Write-LogEntry -Message "磁盘列表刷新完成: $($diskList.Count) 个磁盘" -Type "SCAN"
    }
    catch {
        Update-Status -Message "刷新出错: $($_.Exception.Message)"
        Write-LogEntry -Message "刷新出错: $($_.Exception.Message)" -Type "ERROR"
    }
})

# --- 全选复选框 ---
$window.FindName('ChkSelectAll').Add_Checked({
    $grid = $window.FindName('FileGrid')
    if ($grid.ItemsSource) {
        $grid.SelectAll()
    }
})

$window.FindName('ChkSelectAll').Add_Unchecked({
    $grid = $window.FindName('FileGrid')
    if ($grid.ItemsSource) {
        $grid.UnselectAll()
    }
})

# ============================================================
# 初始化
# ============================================================
Write-LogEntry -Message "Disk-Cleaner 启动" -Type "INFO"

# 加载磁盘列表
$diskList = Get-DiskList
$diskListBox = $window.FindName('DiskListBox')
$diskListBox.ItemsSource = $diskList | ForEach-Object {
    [PSCustomObject]@{
        DriveLetter = $_.DriveLetter
        VolumeLabel = if ($_.VolumeLabel) { $_.VolumeLabel } else { '本地磁盘' }
        FreeSpaceGB = $_.FreeSpaceGB
        TotalSizeGB = $_.TotalSizeGB
        DisplayText = "$($_.DriveLetter)  $($_.FreeSpaceGB) GB 可用"
    }
}

# 默认选中第一个磁盘
if ($diskListBox.Items.Count -gt 0) {
    $diskListBox.SelectedIndex = 0
}

Update-Status -Message "就绪 - 请选择磁盘和清理类别，然后点击扫描"

# ============================================================
# 显示窗口
# ============================================================
$window.ShowDialog() | Out-Null

# 退出时记录日志
Write-LogEntry -Message "Disk-Cleaner 退出" -Type "INFO"
