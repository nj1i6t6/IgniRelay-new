#requires -version 5.1
<#
.SYNOPSIS
  安裝 IgniRelay git pre-commit hook（強制兩段式 commit 流程）。

.DESCRIPTION
  將 tool/hooks/pre-commit 複製到 .git/hooks/pre-commit 並設可執行。
  跑一次即可；換機器或 fresh clone 後重跑一次。

  hook 規則見 tool/hooks/pre-commit 檔首註解。
  概要：功能 commit 後必須緊接 "docs: STATUS entry" commit 補 STATUS.md，
  否則後續 commit 被 hook 擋下，直到補完 STATUS 為止。

.EXAMPLE
  pwsh -File tool/install-hooks.ps1
  powershell -ExecutionPolicy Bypass -File tool/install-hooks.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (git rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) {
  Write-Error '不在 git 倉庫內。請在 IgniRelay repo 根目錄執行。'
  exit 1
}

$src = Join-Path $repoRoot 'tool\hooks\pre-commit'
$dstDir = Join-Path $repoRoot '.git\hooks'
$dst = Join-Path $dstDir 'pre-commit'

if (-not (Test-Path -LiteralPath $src)) {
  Write-Error "找不到 hook 來源：$src"
  exit 1
}
if (-not (Test-Path -LiteralPath $dstDir)) {
  Write-Error "找不到 .git/hooks 目錄：$dstDir（這真的是 git 倉庫嗎？）"
  exit 1
}

# 複製（覆蓋既有 pre-commit）
Copy-Item -LiteralPath $src -Destination $dst -Force

# 確保換行為 LF（sh 腳本 CRLF 會解析失敗）
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($dst, $utf8NoBom)
$content = $content -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($dst, $content, $utf8NoBom)

# 清除可能殘留的 PENDING 標記（避免舊狀態卡住）
$pending = Join-Path $repoRoot '.git\STATUS_PENDING'
if (Test-Path -LiteralPath $pending) {
  Remove-Item -LiteralPath $pending -Force
  Write-Host '已清除殘留的 .git/STATUS_PENDING 標記。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '========================================================' -ForegroundColor Green
Write-Host ' IgniRelay pre-commit hook 安裝完成' -ForegroundColor Green
Write-Host '========================================================' -ForegroundColor Green
Write-Host ' 安裝位置：.git\hooks\pre-commit' -ForegroundColor Green
Write-Host ''
Write-Host ' 流程規矩（兩段式 commit）：' -ForegroundColor Cyan
Write-Host '  1. 功能 commit：git commit -m "[任務] 描述"' -ForegroundColor White
Write-Host '     → hook 放行並標記 STATUS_PENDING' -ForegroundColor White
Write-Host '  2. 補 STATUS：更新 STATUS.md（append entry + 覆寫 Current State 段）' -ForegroundColor White
Write-Host '     → git add STATUS.md' -ForegroundColor White
Write-Host '     → git commit -m "docs: STATUS entry — <任務> DONE @ <hash>"' -ForegroundColor White
Write-Host '     → hook 放行並清除 PENDING' -ForegroundColor White
Write-Host ''
Write-Host ' 若跳過第2步，下次 commit 會被擋下直到補完 STATUS。' -ForegroundColor Yellow
Write-Host '========================================================' -ForegroundColor Green
Write-Host ''
