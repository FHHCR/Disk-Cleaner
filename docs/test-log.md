# Disk-Cleaner 测试日志

**日期**: 2026-11-06
**测试环境**: 静态验证（Linux 沙箱）+ Windows 端测试脚本

---

## 测试说明

由于开发沙箱为 Linux 环境（无法直接运行 Windows PowerShell），测试采用**双轨方案**：

1. **静态验证**（已在开发环境完成）：语法检查、逻辑模拟、结构验证
2. **Windows 端测试**（需用户在 Windows PowerShell 中运行）：真实的磁盘枚举、回收站操作

> **Windows 端测试方法**：
> ```
> powershell -ExecutionPolicy Bypass -File .\run-tests.ps1
> ```
> 该脚本只操作 `TestFiles/` 目录，不会触碰其他文件夹。所有清理操作均移入回收站（可恢复）。

---

## 测试记录

### 一、静态验证（已完成）

| # | 测试项 | 方法 | 结果 | 详情 |
|---|--------|------|------|------|
| S1 | Logger.ps1 语法 | ps_check.py 静态检查 | ✅ 通过 | 语法 OK，函数 Get-LogPath, Write-LogEntry 定义正确 |
| S2 | Logger CSV 格式 | Python 模拟 | ✅ 通过 | CSV 可解析，表头正确，INFO/TEST 类型正确 |
| S3 | DiskScanner.ps1 语法 | ps_check.py 静态检查 | ✅ 通过 | 语法 OK，3 个函数定义正确 |
| S4 | DiskScanner 类别映射 | Python 模拟 | ✅ 通过 | 7 个类别，名称正确 |
| S5 | DiskScanner 扩展名过滤 | Python 模拟 | ✅ 通过 | 图片过滤 .jpg/.png，文档过滤 .pdf/.docx |
| S6 | Cleaner.ps1 语法 | ps_check.py 静态检查 | ✅ 通过 | 语法 OK，2 个函数定义正确 |
| S7 | Cleaner 状态管理 | Python 模拟 | ✅ 通过 | 成功/跳过/批量处理逻辑正确 |
| S8 | MainWindow.xaml 结构 | XML 解析 | ✅ 通过 | XML 有效，15 个关键控件全部存在 |
| S9 | DiskCleaner.ps1 语法 | ps_check.py 静态检查 | ✅ 通过 | 语法 OK，4 个辅助函数定义正确 |
| S10 | run-tests.ps1 语法 | ps_check.py 静态检查 | ✅ 通过 | 语法 OK，测试辅助函数正确 |
| S11 | 最终文件完整性 | 文件存在性检查 | ✅ 通过 | 10 个核心文件全部存在 |
| S12 | 最终全量语法验证 | ps_check.py 全部验证 | ✅ 通过 | 5 个 .ps1 文件语法全部 OK |

### 二、Windows 端测试（待用户运行）

| # | 测试项 | 方法 | 预期结果 | 状态 |
|---|--------|------|----------|------|
| W1 | Write-LogEntry 写入日志 | run-tests.ps1 | 日志文件存在且有记录 | ⏳ 待运行 |
| W2 | Get-DiskList 返回磁盘 | run-tests.ps1 | 至少 1 个磁盘 | ⏳ 待运行 |
| W3 | Get-CategoryPaths 返回7类别 | run-tests.ps1 | 7 个类别 | ⏳ 待运行 |
| W4 | Get-FileByCategory 扫描图片 | run-tests.ps1 | 扫描到 TestFiles 内图片 | ⏳ 待运行 |
| W5 | Move-ToRecycleBin 移入回收站 | run-tests.ps1 | Status=成功，文件移走 | ⏳ 待运行 |
| W6 | 文件已从原位置移走 | run-tests.ps1 | Test-Path 返回 False | ⏳ 待运行 |
| W7 | 不存在路径返回跳过 | run-tests.ps1 | Status=跳过 | ⏳ 待运行 |
| W8 | TestFiles 目录结构完整 | run-tests.ps1 | 6 个子目录存在 | ⏳ 待运行 |
| W9 | 安全断言：不碰 TestFiles 外 | run-tests.ps1 | 无越界操作 | ⏳ 待运行 |

---

## 清理测试安全约束

✅ **测试只操作 `TestFiles/` 目录**（由 run-tests.ps1 中的路径断言强制保证）

✅ **所有清理操作使用回收站**（`RecycleOption.SendToRecycleBin`，可恢复）

✅ **单个文件失败不中止操作**（try-catch 记录错误继续）

---

## 已知限制

1. **回收站清理**（清空回收站类别）是 Windows 的限制：回收站内的文件在清空时不可恢复，界面已标注 ⚠️
2. **缩略图缓存**（thumbcache_*.db）可能被 Explorer 锁定，清理时会跳过并记录错误
3. **临时文件**可能被其他进程占用，清理时会跳过并记录错误

---

## 修复记录：UTF-8 BOM 编码问题（2026-11-06）

### 问题描述

用户运行 `DiskCleaner.ps1` 报语法错误：
```
表达式或语句中包含意外的标记"}"
表达式或语句中包含意外的标记"ChkThumbnails').IsChecked) { $selected += '缂╃暐鍥剧紦瀛?"
```

### 根因分析

- 所有 `.ps1` 文件为 **UTF-8 编码但无 BOM**
- Windows PowerShell 5.1 对无 BOM 文件使用系统 ANSI 代码页（中文系统 = GBK）解析
- UTF-8 中文字符在 GBK 解析下变成乱码（如"缩略图缓存"→"缂╃暐鍥剧紦瀛"）
- 乱码导致引号错乱、块结构破坏，引发语法错误

### 修复方案

给所有 `.ps1` 文件添加 **UTF-8 BOM**（`EF BB BF`），让 Windows PowerShell 5.1 正确识别为 UTF-8。

### 验证

| # | 验证项 | 结果 |
|---|--------|------|
| F1 | 5 个 .ps1 文件均添加 BOM | ✅ 通过 |
| F2 | 中文内容读回完整（下载/图片/文档/视频/缩略图缓存等） | ✅ 通过 |
| F3 | 语法检查器全部通过 | ✅ 通过 |
| F4 | 深度结构检查（314 行，所有 {} 匹配、引号闭合） | ✅ 通过 |
| F5 | 用户报错行（54/64/66/93/100/106/109/113）现在显示正确中文 | ✅ 通过 |

### 修复后用户操作

在 Windows PowerShell 中重新运行：
```powershell
powershell -ExecutionPolicy Bypass -File .\DiskCleaner.ps1
```

---

## 修复记录：Export-ModuleMember 错误（2026-11-06）

### 问题描述

用户运行报错：
```
Export-ModuleMember : 只能从模块内调用 Export-ModuleMember cmdlet。
所在位置 Modules\Logger.ps1:40 字符: 1
+ Export-ModuleMember -Function Write-LogEntry, Get-LogPath
```

### 根因分析

- `Export-ModuleMember` 是 `.psm1` 模块（真正模块文件）专用的 cmdlet
- 本项目使用 `.ps1` 文件 + 点源加载（`. .\Modules\Logger.ps1`），函数已自动在当前作用域可用
- 点源加载 `.ps1` 时不需要也不允许 `Export-ModuleMember`

### 修复方案

移除 3 个模块文件中的 `Export-ModuleMember` 行（Logger.ps1、DiskScanner.ps1、Cleaner.ps1）。

### 验证

| # | 验证项 | 结果 |
|---|--------|------|
| F6 | 3 个模块文件移除 Export-ModuleMember | ✅ 通过 |
| F7 | 语法检查器全部通过 | ✅ 通过 |
| F8 | BOM 保留 | ✅ 通过 |
| F9 | 所有函数定义完整（7 个函数） | ✅ 通过 |

### 修复后用户操作

在 Windows PowerShell 中重新运行：
```powershell
powershell -ExecutionPolicy Bypass -File .\DiskCleaner.ps1
```

---

## 修复记录：XAML 解析错误（2026-11-06）

### 问题描述

用户运行报错：
```
加载界面失败: 使用"1"个参数调用"Parse"时发生异常:""设置属性
"System.Windows.Controls.ItemsControl.ItemTemplate"时引发了异常。",行号为"45"
```

### 根因分析

1. **DisplayMemberPath 与 ItemTemplate 冲突**：`ListBox` 同时设置了 `DisplayMemberPath="DisplayText"` 和 `<ListBox.ItemTemplate>`。WPF 中 `ItemsControl` 这两个属性互斥，同时设置会抛异常。
2. **StringFormat 含空格**：`StringFormat=可用 {0} GB` 和 `StringFormat=yyyy-MM-dd HH:mm` 中的空格会导致 XAML 标记扩展解析问题。

### 修复方案

1. 移除 `DisplayMemberPath`（保留 ItemTemplate）
2. 修正 StringFormat 写法为 `StringFormat={}{0:N2} GB` 和 `StringFormat={}{0:yyyy-MM-dd HH:mm}`
3. 将清理选择机制从复选框（IsSelected）改为 DataGrid 原生行选中（SelectedItems），因为 `[PSCustomObject]` 不支持 INotifyPropertyChanged，复选框绑定不可靠

### 验证

| # | 验证项 | 结果 |
|---|--------|------|
| F10 | XAML XML 解析 OK | ✅ 通过 |
| F11 | 15 个控件全部存在 | ✅ 通过 |
| F12 | 无 DisplayMemberPath/ItemTemplate 冲突 | ✅ 通过 |
| F13 | 无带空格的 StringFormat | ✅ 通过 |
| F14 | 5 个 .ps1 语法全部通过 | ✅ 通过 |
| F15 | BOM 全部保留（6 文件） | ✅ 通过 |
| F16 | 深度结构检查（300 行，{} 匹配） | ✅ 通过 |

### 修复后用户操作

在 Windows PowerShell 中重新运行：
```powershell
powershell -ExecutionPolicy Bypass -File .\DiskCleaner.ps1
```
