# Environment Scanner v4.3.0 - Windows 最终报告
# 先校验 AI 判断，通过后渲染最终报告，再用系统默认程序打开。
# 未在真实 Windows 上执行。编码：UTF-8 BOM，CRLF。不需要 Git Bash，也不需要用户另装 Python。
# 用法: powershell -File scripts/generate-final-report.ps1 <evidence.json> <judgment.json> <output.html>

param(
    [string]$EvidenceFile = "",
    [string]$JudgmentFile = "",
    [string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($EvidenceFile) -or [string]::IsNullOrWhiteSpace($JudgmentFile) -or [string]::IsNullOrWhiteSpace($OutputFile)) {
    Write-Host "用法: powershell -File scripts/generate-final-report.ps1 <evidence.json> <judgment.json> <output.html>"
    exit 1
}

$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ScriptDir
$TemplateFile = Join-Path $RepoRoot "templates\final-report.html"

foreach ($required in @($EvidenceFile, $JudgmentFile, $TemplateFile)) {
    if (-not (Test-Path -LiteralPath $required)) {
        Write-Host "❌ 文件不存在: $required"
        exit 1
    }
}

. (Join-Path $ScriptDir "find-python.ps1")
$Python = Find-ScannerPython
if (-not $Python) { exit 1 }

$JudgmentPy = Join-Path $ScriptDir "lib\judgment.py"
& $Python $JudgmentPy validate $EvidenceFile $JudgmentFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Python $JudgmentPy render $EvidenceFile $JudgmentFile $TemplateFile $OutputFile
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Python (Join-Path $ScriptDir "lib\open_report.py") $OutputFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ 报告已生成，但没有自动打开。请手动打开: $OutputFile"
}
