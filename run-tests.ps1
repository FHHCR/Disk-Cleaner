# run-tests.ps1 - Windows 端自动化测试脚本
# 在 Windows PowerShell 中运行此脚本以测试所有模块
# 使用: powershell -ExecutionPolicy Bypass -File .\run-tests.ps1
#
# ⚠️ 安全说明：
#   清理测试只能操作 TestFiles/ 目录内的文件，不会碰其他文件夹
#   所有清理操作都使用回收站（可恢复）

$ErrorActionPreference = 'Continue'
$script:TestRoot = Join-Path $PSScriptRoot 'TestFiles'
$script:PassCount = 0
$script:FailCount = 0

# ============================================================
# 测试辅助函数
# ============================================================
function Test-Result {
    param([string]$Name, [bool]$Pass, [string]$Detail = '')
    if ($Pass) {
        $script:PassCount++
        Write-Host "  [PASS] $Name" -ForegroundColor Green
    } else {
        $script:FailCount++
        Write-Host "  [FAIL] $Name - $Detail" -ForegroundColor Red
    }
}

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "===== $Title =====" -ForegroundColor Cyan
}

# ============================================================
# 加载模块
# ============================================================
Write-Host "加载模块..." -ForegroundColor Yellow
. (Join-Path $PSScriptRoot 'Modules\Logger.ps1')
. (Join-Path $PSScriptRoot 'Modules\DiskScanner.ps1')
. (Join-Path $PSScriptRoot 'Modules\Cleaner.ps1')
Write-Host "模块加载完成" -ForegroundColor Green

# ============================================================
# 测试 1: Logger 模块
# ============================================================
Write-TestHeader "测试 1: Logger 模块"

$testLogMsg = "测试日志-$(Get-Date -Format 'HHmmss')"
Write-LogEntry -Message $testLogMsg -Type "TEST"
$logContent = Get-Content (Get-LogPath) -ErrorAction SilentlyContinue
$logFound = $logContent | Where-Object { $_ -match $testLogMsg }
Test-Result -Name "Write-LogEntry 写入日志" -Pass ($logFound -ne $null) -Detail "未找到日志记录"
Test-Result -Name "日志文件存在" -Pass (Test-Path (Get-LogPath)) -Detail "日志文件不存在"

# ============================================================
# 测试 2: DiskScanner 模块
# ============================================================
Write-TestHeader "测试 2: DiskScanner 模块"

# 2a: Get-DiskList
$diskList = Get-DiskList
Test-Result -Name "Get-DiskList 返回磁盘" -Pass ($diskList.Count -ge 1) -Detail "未检测到磁盘"

# 2b: Get-CategoryPaths
$catPaths = Get-CategoryPaths -DriveLetter "$env:SystemDrive"
Test-Result -Name "Get-CategoryPaths 返回7个类别" -Pass ($catPaths.Count -eq 7) -Detail "类别数: $($catPaths.Count)"

# 2c: 测试文件扫描（使用 TestFiles 目录）
# 创建测试文件
$testPicsDir = Join-Path $script:TestRoot 'Pictures'
New-Item -Path $testPicsDir -ItemType Directory -Force | Out-Null
$testImg = Join-Path $testPicsDir 'test-photo.jpg'
Set-Content -Path $testImg -Value "fake jpg content" -Encoding UTF8

$scanned = Get-FileByCategory -Category '图片' -Path $testPicsDir
Test-Result -Name "Get-FileByCategory 扫描图片" -Pass ($scanned.Count -ge 1) -Detail "未扫描到图片文件"
Test-Result -Name "扫描结果有正确的Category" -Pass (($scanned | Where-Object { $_.Category -eq '图片' }).Count -ge 1) -Detail "Category 字段不正确"

# ============================================================
# 测试 3: Cleaner 模块（仅限 TestFiles）
# ============================================================
Write-TestHeader "测试 3: Cleaner 模块（仅限 TestFiles）"

# 3a: 创建测试文件用于清理
$testCleanDir = Join-Path $script:TestRoot 'Downloads'
New-Item -Path $testCleanDir -ItemType Directory -Force | Out-Null
$testCleanFile = Join-Path $testCleanDir 'cleanup-test.txt'
Set-Content -Path $testCleanFile -Value "测试清理内容" -Encoding UTF8

# 确保测试文件在 TestFiles 内（安全断言）
if (-not $testCleanFile.StartsWith($script:TestRoot)) {
    Test-Result -Name "安全断言: 测试文件在TestFiles内" -Pass $false -Detail "测试文件路径超出TestFiles!"
    exit 1
}

# 3b: Move-ToRecycleBin
$cleanResults = Move-ToRecycleBin -FilePaths @($testCleanFile)
$successResult = $cleanResults | Where-Object { $_.Status -eq '成功' }
Test-Result -Name "Move-ToRecycleBin 移入回收站" -Pass ($successResult.Count -ge 1) -Detail "清理结果: $($cleanResults | ConvertTo-Json)"

# 3c: 验证文件已移走
$fileStillExists = Test-Path $testCleanFile
Test-Result -Name "文件已从原位置移走" -Pass (-not $fileStillExists) -Detail "文件仍存在: $testCleanFile"

# 3d: 测试不存在的路径
$missingResults = Move-ToRecycleBin -FilePaths @((Join-Path $script:TestRoot 'nonexistent-file.txt'))
$skipResult = $missingResults | Where-Object { $_.Status -eq '跳过' }
Test-Result -Name "不存在路径返回跳过" -Pass ($skipResult.Count -ge 1) -Detail "结果: $($missingResults | ConvertTo-Json)"

# ============================================================
# 测试 4: 安全性验证（确认没碰 TestFiles 以外的文件）
# ============================================================
Write-TestHeader "测试 4: 安全性验证"

# 验证 TestFiles 目录结构仍存在
$dirsExist = @('Downloads', 'Pictures', 'Documents', 'Videos', 'Temp', 'Thumbnails') |
    ForEach-Object { Test-Path (Join-Path $script:TestRoot $_) } |
    Where-Object { $_ }
Test-Result -Name "TestFiles 目录结构完整" -Pass ($dirsExist.Count -eq 6) -Detail "部分目录缺失"

# ============================================================
# 测试结果汇总
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  测试完成" -ForegroundColor Cyan
Write-Host "  通过: $script:PassCount" -ForegroundColor Green
Write-Host "  失败: $script:FailCount" -ForegroundColor $(if ($script:FailCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "==========================================" -ForegroundColor Cyan

if ($script:FailCount -gt 0) {
    Write-Host ""
    Write-Host "❌ 存在失败的测试，请检查上述输出。" -ForegroundColor Red
    exit 1
} else {
    Write-Host ""
    Write-Host "✅ 所有测试通过！" -ForegroundColor Green
    Write-LogEntry -Message "测试全部通过: $($script:PassCount) 项" -Type "TEST"
    exit 0
}
