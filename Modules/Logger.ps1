# Logger.ps1 - 日志模块
# 提供 Write-LogEntry 函数，将操作日志写入 CSV 文件
# 日志格式: Timestamp,Type,Message
# 日志位置: <项目根目录>\logs\cleaner-log.csv

# 获取日志文件路径
function Get-LogPath {
    $logDir = Join-Path $PSScriptRoot '..\logs'
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    return Join-Path $logDir 'cleaner-log.csv'
}

# 写入一条日志
function Write-LogEntry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$true)]
        [ValidateSet('INFO', 'SCAN', 'CLEAN', 'TEST', 'ERROR')]
        [string]$Type
    )

    $logPath = Get-LogPath

    # 如果日志文件不存在，写入表头
    if (-not (Test-Path $logPath)) {
        $header = 'Timestamp,Type,Message'
        Add-Content -Path $logPath -Value $header -Encoding UTF8
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp,$Type,`"$Message`""
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

# 导出模块函数
