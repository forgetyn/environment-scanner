param(
    [string]$OutputFile = "$HOME\.environment-scanner\reports\environment-scanner-data.json",
    [ValidateSet("quick", "standard", "deep")]
    [string]$ScanMode = ""
)

# v2.2.0 的近期文档采样在 scripts/lib/sample_content.py。
# 本脚本仍只输出计数。Windows 采样未在本机执行，不要把它当成已验证。
$ErrorActionPreference = "Stop"

$configPath = Join-Path $PSScriptRoot "..\config.json"
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $ScanMode) {
    $ScanMode = $config.default_config.scan_depth
    if (-not $ScanMode) { $ScanMode = "deep" }
}

$filtering = $config.features.smart_filtering
$skipDirNames = @($filtering.skip_dir_names)
$skipFileNames = @($filtering.skip_file_names)
$skipSuffixes = @($filtering.skip_file_suffixes)
$skipSubstrings = @($filtering.skip_file_substrings)

function Test-SkipDir {
    param([string]$Name)
    if ($Name.StartsWith(".")) { return $true }
    if ($skipDirNames -contains $Name) { return $true }
    $lowered = $Name.ToLowerInvariant()
    foreach ($part in $skipSubstrings) {
        if ($lowered.Contains([string]$part)) { return $true }
    }
    return $false
}

function Test-SkipFile {
    param([string]$Name)
    if ($skipFileNames -contains $Name) { return $true }
    $suffix = [IO.Path]::GetExtension($Name).ToLowerInvariant()
    if ($skipSuffixes -contains $suffix) { return $true }
    $lowered = $Name.ToLowerInvariant()
    foreach ($part in $skipSubstrings) {
        if ($lowered.Contains([string]$part)) { return $true }
    }
    return $false
}

function Convert-BytesToHuman {
    param([double]$Bytes)
    if ($Bytes -lt 1KB) { return "$([math]::Round($Bytes, 0))B" }
    if ($Bytes -lt 1MB) { return "$([math]::Round($Bytes / 1KB, 1))K" }
    if ($Bytes -lt 1GB) { return "$([math]::Round($Bytes / 1MB, 1))M" }
    if ($Bytes -lt 1TB) { return "$([math]::Round($Bytes / 1GB, 1))G" }
    return "$([math]::Round($Bytes / 1TB, 1))T"
}

$script:warnings = New-Object System.Collections.Generic.List[string]

function Get-ScanFiles {
    param(
        [string]$Path,
        [int]$MaxDepth = -1
    )

    $found = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path)) { return $found }

    function Walk {
        param([string]$Current, [int]$Depth)
        try {
            $entries = Get-ChildItem -LiteralPath $Current -Force -ErrorAction Stop
        } catch {
            $script:warnings.Add("unreadable:$Current")
            return
        }
        foreach ($entry in $entries) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($entry.PSIsContainer) {
                if (Test-SkipDir $entry.Name) { continue }
                if ($MaxDepth -ge 0 -and $Depth -ge $MaxDepth) { continue }
                Walk $entry.FullName ($Depth + 1)
            } elseif (-not (Test-SkipFile $entry.Name)) {
                $found.Add($entry)
            }
        }
    }

    try {
        Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "scan root unreadable: $Path"
        exit 1
    }
    Walk $Path 1
    return $found
}

function Get-ByteTotal {
    param($Files)
    $sum = 0L
    foreach ($file in $Files) { $sum += [int64]$file.Length }
    return $sum
}

$userProfile = [Environment]::GetFolderPath("UserProfile")
$documents = if ($env:ENV_SCANNER_DOCUMENTS) { $env:ENV_SCANNER_DOCUMENTS } else { Join-Path $userProfile "Documents" }
$desktop = if ($env:ENV_SCANNER_DESKTOP) { $env:ENV_SCANNER_DESKTOP } else { Join-Path $userProfile "Desktop" }
$downloads = if ($env:ENV_SCANNER_DOWNLOADS) { $env:ENV_SCANNER_DOWNLOADS } else { Join-Path $userProfile "Downloads" }
$booksDir = if ($env:ENV_SCANNER_BOOKS) { $env:ENV_SCANNER_BOOKS } else { Join-Path $desktop "书籍" }

$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$diskDrive = Split-Path -Path $userProfile -Qualifier
$diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$diskDrive'"
$diskTotal = [double]($diskInfo.Size)
$diskFree = [double]($diskInfo.FreeSpace)
$diskUsed = $diskTotal - $diskFree
$diskPercent = if ($diskTotal -gt 0) { [math]::Round(($diskUsed / $diskTotal) * 100, 2) } else { 0 }

$docFiles = @(Get-ScanFiles -Path $documents)
$markdown = @($docFiles | Where-Object { $_.Extension -eq ".md" })
$recentCutoff = (Get-Date).AddDays(-7)
$recentNotes = @($markdown | Where-Object { $_.LastWriteTime -ge $recentCutoff })
$ebooks = @(Get-ScanFiles -Path $booksDir)
$desktopFiles = @(Get-ScanFiles -Path $desktop -MaxDepth 2)
$desktopDirs = 0
if (Test-Path -LiteralPath $desktop) {
    $desktopDirs = @(Get-ChildItem -LiteralPath $desktop -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-SkipDir $_.Name) }).Count
}
$downloadFiles = @(Get-ScanFiles -Path $downloads)
$documentsBytes = Get-ByteTotal $docFiles
$desktopBytes = Get-ByteTotal @(Get-ScanFiles -Path $desktop)
$downloadBytes = Get-ByteTotal $downloadFiles

$hostname = if ($env:ENV_SCANNER_HOSTNAME_OVERRIDE) { $env:ENV_SCANNER_HOSTNAME_OVERRIDE } else { $env:COMPUTERNAME }

$data = [ordered]@{
    scan_time  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    scan_mode  = $ScanMode
    platform   = "windows"
    system     = [ordered]@{
        os       = $osInfo.Caption
        version  = $osInfo.Version
        arch     = $osInfo.OSArchitecture
        hostname = $hostname
        username = $env:USERNAME
    }
    disk       = [ordered]@{
        total     = Convert-BytesToHuman $diskTotal
        used      = Convert-BytesToHuman $diskUsed
        available = Convert-BytesToHuman $diskFree
        percent   = "$diskPercent%"
    }
    files      = [ordered]@{
        obsidian_notes   = $markdown.Count
        ebooks           = $ebooks.Count
        desktop_dirs     = $desktopDirs
        desktop_files    = $desktopFiles.Count
        recent_notes_7d  = $recentNotes.Count
    }
    storage    = [ordered]@{
        documents = Convert-BytesToHuman $documentsBytes
        desktop   = Convert-BytesToHuman $desktopBytes
        downloads = Convert-BytesToHuman $downloadBytes
    }
    storage_bytes = [ordered]@{
        documents = $documentsBytes
        desktop   = $desktopBytes
        downloads = $downloadBytes
    }
    scan_limits = [ordered]@{
        max_items_per_query = $null
        count_is_total      = $true
    }
    scan_scope = [ordered]@{
        type     = "user_files_only"
        excluded = @("system", "applications", "logs", "cache", "sensitive_dirs")
    }
    scan_warnings = @($script:warnings)
}

$outputDir = Split-Path -Path $OutputFile -Parent
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
Write-Host "Environment Scanner data collection complete"
Write-Host "Output file: $OutputFile"
