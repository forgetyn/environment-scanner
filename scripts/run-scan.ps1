# Environment Scanner v4.3.0 - Windows 原生证据收集入口
# 未实机验证：编写时开发机没有 PowerShell / pwsh，本文件只经过人工逐行审查，没有在 Windows 上执行。
# 编码：UTF-8 with BOM，避免 Windows PowerShell 5.1 按系统 ANSI 误读中文。
# 只读扫描。不依赖 Git Bash。五个阶段调用与 run-scan.sh 相同的 Python 库。
# 解释器由 find-python.ps1 选择。有能用的系统 Python 就用它，否则解压工具自带的运行环境。用户不用另装 Python。
# 用法: .\scripts\run-scan.ps1 [quick|standard|deep] [额外文档路径...]
# 多路径环境变量 ENV_SCANNER_INSIGHT_DOCS 用分号分隔（冒号会切开盘符）。

param(
    [string]$ScanMode = "",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraDocs
)

$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ScriptDir
$ConfigFile = Join-Path $RepoRoot "config.json"

if ([string]::IsNullOrWhiteSpace($ScanMode)) {
    $ScanMode = "deep"
    if (Test-Path -LiteralPath $ConfigFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($ConfigFile)
            $cfg = $raw | ConvertFrom-Json
            $configured = [string]$cfg.default_config.scan_depth
            if (-not [string]::IsNullOrWhiteSpace($configured)) {
                $ScanMode = $configured
            }
        } catch {
            $ScanMode = "deep"
        }
    }
}

if ($ScanMode -notin @("quick", "standard", "deep")) {
    Write-Host "⚠️ 未知扫描模式: $ScanMode，回退到 deep"
    $ScanMode = "deep"
}

. (Join-Path $ScriptDir "find-python.ps1")
$Python = Find-ScannerPython
if (-not $Python) {
    exit 1
}

function Invoke-Py {
    param([Parameter(Mandatory = $true)][string[]]$PyArgs)
    & $script:Python @PyArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

$OutputDir = $env:ENV_SCANNER_OUTPUT_DIR
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $HOME ".environment-scanner\reports"
}

$Timestamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
$DataFile = Join-Path $OutputDir "environment-scanner-data-$Timestamp.json"
$SamplesFile = Join-Path $OutputDir "environment-scanner-samples-$Timestamp.json"
$AppsFile = Join-Path $OutputDir "environment-scanner-apps-$Timestamp.json"
$EvidenceFile = Join-Path $OutputDir "environment-scanner-evidence-$Timestamp.json"
$EvidenceReportFile = Join-Path $OutputDir "environment-scanner-evidence-report-$Timestamp.html"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Host "🦞 Environment Scanner v4.3.0"
Write-Host "================================"
Write-Host "扫描模式: $ScanMode"
Write-Host "输出目录: $OutputDir"
Write-Host ""

Write-Host "📊 阶段 1/5: 收集计数和体积..."
Invoke-Py -PyArgs @(
    (Join-Path $ScriptDir "lib\scan_collect.py"),
    "--output", $DataFile,
    "--mode", $ScanMode
)

Write-Host ""
$DocArgs = @()
if (-not [string]::IsNullOrEmpty($env:ENV_SCANNER_INSIGHT_DOCS)) {
    # 与 run-scan.sh 一致：分号分隔。空段丢掉，避免多出一个空路径。
    foreach ($part in ($env:ENV_SCANNER_INSIGHT_DOCS -split ';')) {
        if (-not [string]::IsNullOrEmpty($part)) {
            $DocArgs += $part
        }
    }
}
if ($ExtraDocs) {
    $DocArgs += $ExtraDocs
}

Write-Host "📄 阶段 2/5: 采样近期文档..."
$sampleArgs = @(
    (Join-Path $ScriptDir "lib\sample_content.py"),
    "--output", $SamplesFile,
    "--mode", $ScanMode
)
if ($DocArgs.Count -gt 0) {
    $sampleArgs += "--explicit"
    $sampleArgs += $DocArgs
}
Invoke-Py -PyArgs $sampleArgs

Write-Host ""
Write-Host "📱 阶段 3/5: 收集应用清单（只读名字）..."
Invoke-Py -PyArgs @(
    (Join-Path $ScriptDir "lib\app_inventory.py"),
    "--output", $AppsFile
)

$KbArgs = @()
Write-Host ""
Write-Host "📚 阶段 4/5: 发现知识库与自述文档（只读，可用 ENV_SCANNER_KB_DISCOVER=0 关闭）..."
if ($env:ENV_SCANNER_KB_DISCOVER -ne "0") {
    $KbFile = Join-Path $OutputDir "environment-scanner-kb-$Timestamp.json"
    Invoke-Py -PyArgs @(
        (Join-Path $ScriptDir "lib\kb_discover.py"),
        "--output", $KbFile
    )
    $KbArgs = @("--kb", $KbFile)
} else {
    Write-Host "ℹ️ 知识库发现已关闭。"
}

Write-Host ""
Write-Host "🧾 阶段 5/5: 汇总证据并生成证据报告..."
$evidenceArgs = @(
    (Join-Path $ScriptDir "lib\evidence_pack.py"),
    "--data", $DataFile,
    "--samples", $SamplesFile,
    "--apps", $AppsFile
)
if ($KbArgs.Count -gt 0) {
    $evidenceArgs += $KbArgs
}
$evidenceArgs += @("--output", $EvidenceFile)
Invoke-Py -PyArgs $evidenceArgs

$TemplateFile = Join-Path $RepoRoot "templates\final-report.html"
Invoke-Py -PyArgs @(
    (Join-Path $ScriptDir "lib\judgment.py"),
    "render",
    $EvidenceFile,
    $TemplateFile,
    $EvidenceReportFile
)

foreach ($artifact in @($DataFile, $SamplesFile, $AppsFile, $EvidenceFile, $EvidenceReportFile)) {
    if (-not (Test-Path -LiteralPath $artifact) -or (Get-Item -LiteralPath $artifact).Length -eq 0) {
        Write-Host "❌ 错误: 产物生成不完整: $artifact"
        exit 1
    }
}

Write-Host ""
Write-Host "✅ 证据文件: $EvidenceFile"
Write-Host "✅ 证据报告: $EvidenceReportFile"
Write-Host "ℹ️ 下一步: 由会话 AI 只读上面的证据文件，按 SKILL.md 的判断准则写"
Write-Host "   $(Join-Path $OutputDir "environment-scanner-judgment-$Timestamp.json")"
Write-Host "   再运行 powershell -File scripts/generate-final-report.ps1 <evidence> <judgment> <output.html>"
Write-Host "ℹ️ 证据收集和最终报告都不需要另装 Python，也不需要 Git Bash。"
Write-Host "ℹ️ 扫描根目录中的用户文件不会被修改。"
