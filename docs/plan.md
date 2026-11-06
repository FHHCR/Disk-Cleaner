# Disk-Cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 PowerShell + WPF 构建一个 Windows 磁盘清理工具，用户自主选择磁盘和清理类别，确认后将文件移入回收站。

**Architecture:** 采用模块化设计，分为日志模块（Logger）、磁盘扫描模块（DiskScanner）、清理模块（Cleaner）、WPF界面（MainWindow.xaml）、主程序入口（DiskCleaner.ps1）。主程序加载各模块并协调 WPF 界面事件。

**Tech Stack:** PowerShell 5.1+, WPF (Windows Presentation Foundation), .NET Framework 内置组件, Microsoft.VisualBasic.FileIO.FileSystem（回收站API）

**Spec:** `docs/design.md`

## Global Constraints

- PowerShell 5.1+（`powershell.exe`，非 pwsh）
- WPF 通过 `Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase` 加载
- 回收站操作使用 `Microsoft.VisualBasic.FileIO.FileSystem.DeleteFile/DeleteDirectory`，`RecycleOption.SendToRecycleBin`
- 所有清理操作必须经用户确认，程序不擅自清理
- 测试清理只能操作 `TestFiles/` 目录内文件，不能动其他文件夹
- 界面语言：中文
- 日志格式：CSV

## Review Focus

1. **用户取消确认对话框** → 程序不得执行任何清理操作，状态栏显示"已取消"
2. **清理时文件被占用/锁定** → 跳过该文件并记录错误，不中止整个操作
3. **磁盘无可用空间或无法访问** → 显示友好错误，不崩溃
4. **选择的清理类别路径不存在** → 显示"0 个文件，无需清理"，不报错
5. **清理完成后** → 状态栏显示成功/失败统计，刷新扫描结果

---

### Task 1: 日志模块 Logger.ps1

**Files:**
- Create: `Modules/Logger.ps1`
- Test: `logs/test-log.log`（通过手动调用验证）

**Interfaces:**
- Consumes: 无
- Produces:
  - `Write-LogEntry -Message <string> -Type <string>` — 写入一条日志（Type: SCAN/CLEAN/INFO/ERROR）
  - `Get-LogPath` — 返回日志文件路径

- [ ] **Step 1: 创建 Logger.ps1 模块**

实现 `Write-LogEntry` 函数：
- 日志文件路径：`$PSScriptRoot\..\logs\cleaner-log.csv`
- 日志格式：CSV，字段 `Timestamp,Type,Message`
- 如果日志目录不存在，自动创建
- 如果日志文件不存在，自动写入表头
- 使用 `Add-Content -Encoding UTF8` 追加写入

- [ ] **Step 2: 测试日志写入**

Run: `powershell -Command ". .\Modules\Logger.ps1; Write-LogEntry -Message '测试日志' -Type 'INFO'; Get-Content .\logs\cleaner-log.csv"`
Expected: 日志文件包含一行 `INFO` 测试日志记录

- [ ] **Step 3: 验证日志模块**

Run: `powershell -Command ". .\Modules\Logger.ps1; Write-LogEntry -Message '测试完成' -Type 'TEST'; Get-Content .\logs\cleaner-log.csv | Select-Object -Last 2"`
Expected: 最后一行包含 "测试完成" 和 "TEST"

---

### Task 2: 磁盘扫描模块 DiskScanner.ps1

**Files:**
- Create: `Modules/DiskScanner.ps1`

**Interfaces:**
- Consumes: `Write-LogEntry`（来自 Task 1）
- Produces:
  - `Get-DiskList` — 返回所有可用磁盘（@($driveLetter, $volumeLabel, $totalSize, $freeSpace)）
  - `Get-FileByCategory -Category <string> -Path <string>` — 按类别扫描文件，返回文件列表
  - `Get-CategoryPaths -Disk <string>` — 返回指定磁盘上各类别的路径映射

- [ ] **Step 1: 实现 `Get-DiskList` 函数**

```powershell
function Get-DiskList {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [PSCustomObject]@{
            DriveLetter = $_.DeviceID
            VolumeLabel = $_.VolumeName
            TotalSizeGB = [math]::Round($_.Size / 1GB, 2)
            FreeSpaceGB = [math]::Round($_.FreeSpace / 1GB, 2)
        }
    }
}
```

- [ ] **Step 2: 实现 `Get-CategoryPaths` 函数**

定义类别与默认路径的映射：
- 下载文件: `$env:USERPROFILE\Downloads`
- 图片: `$env:USERPROFILE\Pictures`
- 文档: `$env:USERPROFILE\Documents`
- 视频: `$env:USERPROFILE\Videos`
- 临时文件: `$env:TEMP`
- 回收站: `$env:SystemDrive\$Recycle.Bin`（仅枚举，不直接清理文件）
- 缩略图缓存: `$env:LOCALAPPDATA\Microsoft\Windows\Explorer`

返回: `@( @{Name='下载文件'; Path='...'; Extensions=@('*')}, ... )`

- [ ] **Step 3: 实现 `Get-FileByCategory` 函数**

```powershell
function Get-FileByCategory {
    param([string]$Category, [string]$Path)
    
    if (-not (Test-Path $Path)) { return @() }
    
    $extensions = switch ($Category) {
        '图片' { @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico', '.tiff') }
        '文档' { @('.doc', '.docx', '.pdf', '.txt', '.xls', '.xlsx', '.ppt', '.pptx', '.md', '.csv') }
        '视频' { @('.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm') }
        default { @('*') }  # 下载文件、临时文件、缩略图缓存：全部文件
    }
    
    Get-ChildItem -Path $Path -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object {
            if ($extensions -eq @('*')) { $true }
            else { $extensions -contains $_.Extension.ToLower() }
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
}
```

- [ ] **Step 4: 测试磁盘枚举**

Run: `powershell -Command ". .\Modules\DiskScanner.ps1; Get-DiskList | Format-Table"`
Expected: 返回至少 1 个磁盘（C:），包含 DriveLetter, TotalSizeGB, FreeSpaceGB

- [ ] **Step 5: 测试类别路径映射**

Run: `powershell -Command ". .\Modules\DiskScanner.ps1; Get-CategoryPaths | Format-Table"`
Expected: 返回 7 个类别（下载文件、图片、文档、视频、临时文件、回收站、缩略图缓存），每个有 Name 和 Path

- [ ] **Step 6: 测试文件扫描（在 TestFiles 中创建测试文件）**

先创建测试文件：
```powershell
# 在 TestFiles 各子目录创建测试文件
New-Item -Path .\TestFiles\Downloads\test.zip -ItemType File -Force
New-Item -Path .\TestFiles\Pictures\test.jpg -ItemType File -Force
New-Item -Path .\TestFiles\Documents\test.pdf -ItemType File -Force
```

Run: `powershell -Command ". .\Modules\DiskScanner.ps1; Get-FileByCategory -Category '图片' -Path '.\TestFiles\Pictures' | Format-Table"`
Expected: 返回至少 1 个文件，Name=test.jpg，Category=图片

---

### Task 3: 清理模块 Cleaner.ps1

**Files:**
- Create: `Modules/Cleaner.ps1`

**Interfaces:**
- Consumes: `Write-LogEntry`（来自 Task 1）
- Produces:
  - `Move-ToRecycleBin -FilePaths <string[]> -IsRecycleBinCategory <bool>` — 将文件移入回收站，返回结果对象
  - `Test-RecycleBinRestore` — 验证文件是否可恢复（通过检查回收站是否收到文件）

- [ ] **Step 1: 实现 `Move-ToRecycleBin` 函数**

```powershell
function Move-ToRecycleBin {
    param([string[]]$FilePaths, [switch]$IsRecycleBinCategory)
    
    Add-Type -AssemblyName Microsoft.VisualBasic
    
    $results = @()
    foreach ($path in $FilePaths) {
        try {
            if (Test-Path $path -PathType Leaf) {
                # 文件 → 移入回收站（可恢复）
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                    $path,
                    'OnlyErrorDialogs',
                    'SendToRecycleBin'
                )
                $results += [PSCustomObject]@{ Path = $path; Status = '成功'; Message = '已移入回收站' }
                Write-LogEntry -Message "清理文件: $path" -Type "CLEAN"
            }
            elseif (Test-Path $path -PathType Container) {
                # 目录 → 移入回收站（可恢复）
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
                    $path,
                    'OnlyErrorDialogs',
                    'SendToRecycleBin'
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
```

- [ ] **Step 2: 测试清理模块（仅限 TestFiles 目录）**

创建测试文件到 `TestFiles/Downloads/`：
```powershell
New-Item -Path .\TestFiles\Downloads\cleanup-test.txt -ItemType File -Force
Set-Content -Path .\TestFiles\Downloads\cleanup-test.txt -Value "测试清理内容"
```

Run: `powershell -Command ". .\Modules\Logger.ps1; . .\Modules\Cleaner.ps1; Move-ToRecycleBin -FilePaths @('.\TestFiles\Downloads\cleanup-test.txt') | Format-Table"`
Expected: 返回 Status=成功，Message=已移入回收站；测试文件不存在于原位置；日志有记录

- [ ] **Step 3: 验证文件已移入回收站（不在原位置）**

Run: `powershell -Command "Test-Path .\TestFiles\Downloads\cleanup-test.txt"`
Expected: False（文件已从原位置移走）

- [ ] **Step 4: 测试文件不存在时跳过**

Run: `powershell -Command ". .\Modules\Logger.ps1; . .\Modules\Cleaner.ps1; Move-ToRecycleBin -FilePaths @('.\TestFiles\nonexistent.txt') | Format-Table"`
Expected: 返回 Status=跳过，Message=路径不存在

- [ ] **Step 5: 测试文件被占用时记录错误**

创建一个被占用的文件（用 PowerShell 打开文件流保持占用）：
```powershell
# 在测试中模拟：创建一个文件然后尝试删除（用另一个进程占用）
# 实际测试：尝试删除一个正在被本脚本打开的文件
$testFile = ".\TestFiles\locked-test.txt"
New-Item -Path $testFile -ItemType File -Force
$stream = [System.IO.File]::Open($testFile, 'Open', 'Read', 'None')  # 保持占用
Move-ToRecycleBin -FilePaths @($testFile) | Format-Table
$stream.Close()
```
Expected: 返回 Status=失败 或 跳过，日志记录错误，脚本不崩溃

---

### Task 4: WPF 界面 MainWindow.xaml

**Files:**
- Create: `UI/MainWindow.xaml`

**Interfaces:**
- Consumes: 无（XAML 仅定义界面结构）
- Produces:
  - XAML 定义：主窗口布局、磁盘列表、类别复选框、扫描按钮、清理按钮、文件表格、状态栏
  - 事件处理器由主程序（DiskCleaner.ps1）绑定

- [ ] **Step 1: 编写 XAML 主窗口布局**

窗口包含以下区域（自上而下）：
1. 顶部标题："Disk-Cleaner - Windows 磁盘清理工具"
2. 磁盘选择区：ListBox（显示磁盘，含盘符、卷标、容量）
3. 类别选择区：CheckBox 列表（7 个类别）
4. 操作按钮区："扫描"、"清理选中文件"、"刷新"
5. 文件列表区：DataGrid（列：文件名、大小、路径、修改时间、类别）
6. 状态栏："就绪"

关键 XAML 结构（简化）：
```xml
<Window ...>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>  <!-- 标题 -->
      <RowDefinition Height="Auto"/>  <!-- 磁盘+类别 -->
      <RowDefinition Height="Auto"/>  <!-- 按钮 -->
      <RowDefinition Height="*"/>     <!-- 文件列表 -->
      <RowDefinition Height="Auto"/>  <!-- 状态栏 -->
    </Grid.RowDefinitions>
    
    <!-- 标题 -->
    <TextBlock Text="Disk-Cleaner - Windows 磁盘清理工具" FontSize="18" FontWeight="Bold"/>
    
    <!-- 磁盘选择 -->
    <GroupBox Header="选择磁盘">
      <ListBox x:Name="DiskListBox" DisplayMemberPath="DriveLetter"/>
    </GroupBox>
    
    <!-- 类别选择 -->
    <GroupBox Header="选择清理类别">
      <StackPanel>
        <CheckBox x:Name="ChkDownloads" Content="下载文件"/>
        <CheckBox x:Name="ChkPictures" Content="图片"/>
        <!-- ... -->
      </StackPanel>
    </GroupBox>
    
    <!-- 按钮 -->
    <StackPanel Orientation="Horizontal">
      <Button x:Name="BtnScan" Content="扫描" Width="80"/>
      <Button x:Name="BtnClean" Content="清理选中文件" Width="120"/>
      <Button x:Name="BtnRefresh" Content="刷新" Width="80"/>
    </StackPanel>
    
    <!-- 文件列表 -->
    <DataGrid x:Name="FileGrid" AutoGenerateColumns="False">
      <DataGrid.Columns>
        <DataGridTextColumn Header="文件名" Binding="{Binding Name}"/>
        <DataGridTextColumn Header="大小" Binding="{Binding Size}"/>
        <DataGridTextColumn Header="路径" Binding="{Binding Path}"/>
        <DataGridTextColumn Header="修改时间" Binding="{Binding LastModified}"/>
        <DataGridTextColumn Header="类别" Binding="{Binding Category}"/>
      </DataGrid.Columns>
    </DataGrid>
    
    <!-- 状态栏 -->
    <StatusBar>
      <TextBlock x:Name="StatusText" Text="就绪"/>
    </StatusBar>
  </Grid>
</Window>
```

- [ ] **Step 2: 验证 XAML 可解析**

Run: `powershell -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.Markup.XamlReader]::Load([System.Xml.XmlReader]::Create('.\UI\MainWindow.xaml'))"`
Expected: 成功加载，无 XAML 解析错误

---

### Task 5: 主程序入口 DiskCleaner.ps1

**Files:**
- Create: `DiskCleaner.ps1`

**Interfaces:**
- Consumes:
  - `Get-DiskList`, `Get-FileByCategory`, `Get-CategoryPaths`（Task 2）
  - `Move-ToRecycleBin`（Task 3）
  - `Write-LogEntry`（Task 1）
  - `MainWindow.xaml`（Task 4）
- Produces: 可运行的程序

- [ ] **Step 1: 编写主程序入口**

主程序职责：
1. 加载模块（Logger, DiskScanner, Cleaner）
2. 加载 XAML 界面
3. 绑定事件处理器
4. 初始化：加载磁盘列表
5. 启动 WPF 窗口

关键逻辑：
```powershell
# 事件：扫描
$BtnScan.Add_Click({
    # 获取选中的磁盘和类别
    # 调用 Get-CategoryPaths 和 Get-FileByCategory
    # 显示文件列表和统计
})

# 事件：清理
$BtnClean.Add_Click({
    # 获取选中文件
    # 弹窗确认（警告 + 数量 + 大小）
    # 用户确认后调用 Move-ToRecycleBin
})

# 事件：刷新
$BtnRefresh.Add_Click({
    # 重新加载磁盘列表
})
```

- [ ] **Step 2: 验证程序语法**

Run: `powershell -Command "[System.Management.Automation.PSParser]::Tokenize((Get-Content .\DiskCleaner.ps1 -Raw), [ref]$null) | Out-Null; 'Syntax OK'"`
Expected: 输出 "Syntax OK"，无语法错误

- [ ] **Step 3: 测试程序启动（可选，GUI 需要桌面环境）**

在测试环境中，验证 WPF 窗口能创建：
```powershell
# 仅验证加载，不实际显示窗口
powershell -Command "
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
\$xaml = Get-Content .\UI\MainWindow.xaml -Raw
\$window = [System.Windows.Markup.XamlReader]::Parse(\$xaml)
\$window.Title
"
```
Expected: 输出窗口标题 "Disk-Cleaner - Windows 磁盘清理工具"

---

### Task 6: 集成测试（仅 TestFiles）

**Files:**
- Test: `TestFiles/`（创建测试文件）
- Test: `docs/test-log.md`（测试日志）

**Interfaces:**
- Consumes: 所有模块

- [ ] **Step 1: 创建集成测试文件**

在 `TestFiles/` 下创建模拟用户目录：
```
TestFiles/
├── Downloads/
│   ├── test.zip        (10 KB)
│   ├── report.pdf      (5 KB)
│   └── photo.jpg       (3 KB)
├── Pictures/
│   ├── wallpaper.jpg   (8 KB)
│   └── screenshot.png  (2 KB)
├── Documents/
│   ├── notes.txt       (1 KB)
│   └── budget.xlsx     (6 KB)
├── Videos/
│   └── movie.mp4       (20 KB)
├── Temp/
│   └── temp1.tmp       (4 KB)
└── Thumbnails/
    └── thumb.db        (2 KB)
```

- [ ] **Step 2: 集成测试 - 扫描**

Run: `powershell -Command ". .\Modules\DiskScanner.ps1; Get-FileByCategory -Category '图片' -Path '.\TestFiles\Pictures' | Format-Table"`
Expected: 扫描到 Pictures 目录的图片文件

- [ ] **Step 3: 集成测试 - 清理（移入回收站）**

Run: `powershell -Command ". .\Modules\Logger.ps1; . .\Modules\Cleaner.ps1; Move-ToRecycleBin -FilePaths @('.\TestFiles\Downloads\test.zip') | Format-Table"`
Expected: Status=成功，文件从 TestFiles/Downloads 移除

- [ ] **Step 4: 验证清理后文件不存在**

Run: `powershell -Command "Test-Path .\TestFiles\Downloads\test.zip"`
Expected: False

- [ ] **Step 5: 编写测试日志到 docs/test-log.md**

记录：测试时间、测试内容、预期结果、实际结果、通过/失败

---

### Task 7: 编写 README.md

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: 所有已完成的模块和文档

- [ ] **Step 1: 编写 README.md**

内容：
1. 产品简介
2. 功能特性
3. 系统要求
4. 部署方法（如何放置文件、如何运行）
5. 使用方法（详细步骤）
6. 注意事项（安全警告）
7. 目录结构
8. 常见问题

- [ ] **Step 2: 验证 README 完整性**

手动检查：README 包含使用方法、部署方法、注意事项，格式正确。

---

### 执行顺序与依赖

```
Task 1 (Logger) ──→ Task 2 (DiskScanner) ──→ Task 4 (XAML)
      │                    │                       │
      └───────────→ Task 3 (Cleaner) ←────────────┘
                              │
                         Task 5 (Main)
                              │
                         Task 6 (Integration Test)
                              │
                         Task 7 (README)
```

任务1→2→3→4 可部分并行（1 是 2、3 的前提；4 独立），5 依赖 1-4，6 依赖 5，7 依赖全部。
