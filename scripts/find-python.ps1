# 选出扫描要用的 Python。点源后调用 Find-ScannerPython，返回解释器绝对路径。
# 顺序：ENV_SCANNER_PYTHON → 已解压的私有运行环境 → 系统解释器 → 解压工具自带的压缩包。
# 未在真实 Windows 上执行。编码：UTF-8 BOM，CRLF。
# 测试可设 ENV_SCANNER_IGNORE_SYSTEM_PYTHON=1、ENV_SCANNER_RUNTIME_HOME、ENV_SCANNER_VENDOR_DIR。

function Test-ScannerPython {
    param([string]$Bin)
    if ([string]::IsNullOrWhiteSpace($Bin)) { return $false }
    if ($Bin -match '(?i)WindowsApps') { return $false }
    if (-not (Test-Path -LiteralPath $Bin -PathType Leaf)) { return $false }
    try {
        & $Bin -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-ScannerPlatformId {
    if ($env:OS -ne "Windows_NT") { return $null }
    $arch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) { $arch = $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        "AMD64" { return "windows-amd64" }
        "ARM64" { return "windows-arm64" }
        default { return $null }
    }
}

function Read-ScannerManifest {
    param([string]$VendorDir)
    $path = Join-Path $VendorDir "manifest.txt"
    $result = @{ Version = ""; Row = $null }
    if (-not (Test-Path -LiteralPath $path)) { return $result }
    foreach ($raw in [System.IO.File]::ReadAllLines($path)) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $parts = $line -split '\s+'
        if ($parts[0] -eq "version" -and $parts.Length -ge 2) {
            $result.Version = $parts[1]
        }
    }
    return $result
}

function Get-ScannerManifestRow {
    param([string]$VendorDir, [string]$PlatformId)
    $path = Join-Path $VendorDir "manifest.txt"
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    foreach ($raw in [System.IO.File]::ReadAllLines($path)) {
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $parts = $line -split '\s+'
        if ($parts.Length -ge 5 -and $parts[0] -eq $PlatformId) {
            return @{
                Sha = $parts[1].ToLowerInvariant()
                File = $parts[2]
                Relative = $parts[3]
                Strip = $parts[4]
            }
        }
    }
    return $null
}

function Repair-EmbeddablePth {
    param([string]$Dest)
    $files = @(Get-ChildItem -LiteralPath $Dest -Filter "python*._pth" -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        $zipName = $file.Name -replace '\._pth$', '.zip'
        $text = $zipName + "`r`n.`r`n`r`nimport site`r`n"
        [System.IO.File]::WriteAllText($file.FullName, $text)
    }
}

function Find-PrivatePython {
    param([string]$RuntimeHome, [string]$PlatformId, [string]$Version, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Version) -or [string]::IsNullOrWhiteSpace($Relative)) { return $null }
    $dest = Join-Path $RuntimeHome $PlatformId
    $marker = Join-Path $dest "VERSION"
    $bin = Join-Path $dest $Relative
    if (-not (Test-Path -LiteralPath $marker)) { return $null }
    $found = ([System.IO.File]::ReadAllText($marker)).Trim()
    if ($found -ne $Version) { return $null }
    if (Test-ScannerPython $bin) { return $bin }
    return $null
}

function Expand-PrivatePython {
    param(
        [string]$VendorDir,
        [string]$RuntimeHome,
        [string]$PlatformId
    )
    $manifest = Read-ScannerManifest $VendorDir
    $row = Get-ScannerManifestRow $VendorDir $PlatformId
    if ($null -eq $row) {
        Write-Host "这台电脑没有可用的 Python，工具里也没有 $PlatformId 的运行环境。"
        return $null
    }
    $archive = Join-Path $VendorDir $row.File
    if (-not (Test-Path -LiteralPath $archive)) {
        Write-Host "运行环境压缩包不存在: $($row.File)"
        return $null
    }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $row.Sha) {
        Write-Host "运行环境压缩包校验失败，没有解压: $($row.File)"
        return $null
    }
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($null -eq $tar) { $tar = Get-Command tar -ErrorAction SilentlyContinue }
    if ($null -eq $tar) {
        Write-Host "系统里没有 tar，无法解压自带的 Python。"
        return $null
    }
    if (-not (Test-Path -LiteralPath $RuntimeHome)) {
        New-Item -ItemType Directory -Path $RuntimeHome | Out-Null
    }
    $tmp = Join-Path $RuntimeHome (".extract-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    if ($row.Strip -eq "0") {
        & $tar.Source -xzf $archive -C $tmp *> $null
    } else {
        & $tar.Source -xzf $archive -C $tmp --strip-components="$($row.Strip)" *> $null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "运行环境解压失败: $($row.File)"
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return $null
    }
    Repair-EmbeddablePth $tmp
    [System.IO.File]::WriteAllText((Join-Path $tmp "VERSION"), $manifest.Version + "`n")
    $dest = Join-Path $RuntimeHome $PlatformId
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    Move-Item -LiteralPath $tmp -Destination $dest
    $bin = Join-Path $dest ($row.Relative -replace '/', '\')
    if (-not (Test-ScannerPython $bin)) {
        Write-Host "解压后的 Python 无法运行: $bin"
        return $null
    }
    return $bin
}

function Find-SystemPython {
    foreach ($name in @("python3", "python")) {
        $cmds = @(Get-Command $name -All -ErrorAction SilentlyContinue)
        foreach ($cmd in $cmds) {
            if ($null -eq $cmd -or [string]::IsNullOrWhiteSpace($cmd.Source)) { continue }
            if (Test-ScannerPython $cmd.Source) { return $cmd.Source }
        }
    }
    return $null
}

function Find-ScannerPython {
    $vendor = $env:ENV_SCANNER_VENDOR_DIR
    if ([string]::IsNullOrWhiteSpace($vendor)) {
        $vendor = Join-Path (Split-Path -Parent $PSScriptRoot) "runtime\vendor"
    }
    $runtimeHome = $env:ENV_SCANNER_RUNTIME_HOME
    if ([string]::IsNullOrWhiteSpace($runtimeHome)) {
        $runtimeHome = Join-Path $env:USERPROFILE ".environment-scanner\runtime"
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ENV_SCANNER_PYTHON)) {
        if (Test-ScannerPython $env:ENV_SCANNER_PYTHON) { return $env:ENV_SCANNER_PYTHON }
        Write-Host "ENV_SCANNER_PYTHON 指向的程序不能用: $($env:ENV_SCANNER_PYTHON)"
        return $null
    }

    $platformId = Get-ScannerPlatformId
    if ([string]::IsNullOrWhiteSpace($platformId)) {
        Write-Host "这个系统没有自带的运行环境。"
        return $null
    }

    $manifest = Read-ScannerManifest $vendor
    $row = Get-ScannerManifestRow $vendor $platformId
    $relative = ""
    if ($null -ne $row) { $relative = $row.Relative }
    $existing = Find-PrivatePython $runtimeHome $platformId $manifest.Version $relative
    if ($existing) { return $existing }

    if ($env:ENV_SCANNER_IGNORE_SYSTEM_PYTHON -ne "1") {
        $system = Find-SystemPython
        if ($system) { return $system }
    }

    return Expand-PrivatePython $vendor $runtimeHome $platformId
}

if ($MyInvocation.InvocationName -ne '.') {
    $chosen = Find-ScannerPython
    if (-not $chosen) { exit 1 }
    Write-Output $chosen
}
