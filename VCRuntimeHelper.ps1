# Requires -Version 5.1

# This script is designed to help install various Visual C++ Redistributable Packages
# It will download the necessary packages, verify their integrity, and install them.

# This script requires administrative privileges to run.
# Make sure you trust the source of this script before executing.

# Prepare the functions
function New-TempDirectory {
    param (
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    } else {
        Get-ChildItem -Path $Path | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-Aria2Path {
    param (
        [string]$Path,
        [bool]$SystemIs64Bit,
        [bool]$CPUIsARM
    )

    Write-Host "`nPreparing aria2..." -ForegroundColor Yellow
    if (Get-Command "aria2c" -ErrorAction SilentlyContinue) {
        $aria2cPath = (Get-Command "aria2c").Source
    } else {
        $aria2cUrls = Get-GitHubDownloadUrl -Uri "https://api.github.com/repos/aria2/aria2/releases/latest"
        if ($SystemIs64Bit -and (-not $CPUIsARM)) {
            $aria2cUrl = $aria2cUrls | Where-Object { $_ -like "*win-64bit*" }
        } elseif ($CPUIsARM) {
            Write-Host "Skip for ARM64."
        } else {
            $aria2cUrl = $aria2cUrls | Where-Object { $_ -like "*win-32bit*" }
        }
        $aria2cZip = Join-Path -Path $Path -ChildPath "aria2c.zip"
        Invoke-WebRequest -Uri $aria2cUrl -OutFile $aria2cZip
        Expand-Archive -Path $aria2cZip -DestinationPath $Path -Force
        Remove-Item -Path $aria2cZip -Force
        $aria2cPath = (Get-ChildItem -Path $Path -Recurse | Where-Object { $_.Name -like "aria2c.exe" } | Select-Object -First 1).FullName
    }
    if ($aria2cPath) {
        Write-Host "Using aria2c in $aria2cPath"
        return $aria2cPath
    }
}

function Get-GitHubDownloadUrl {
    param (
        [string]$Uri
    )

    $response = Invoke-RestMethod -Uri $Uri
    $UrlList = @()
    foreach ($asset in $response.assets) {
        $UrlList += $asset.browser_download_url
    }
    return $UrlList
}

# Main script execution starts here

$RemoteList = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeList.json"
$RemoteInstaller = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeInstaller.ps1"

$PackageList = Invoke-RestMethod -Uri $RemoteList
$DownloadList = @()
$InstallList = @()
$SuccessList = @()
$FailedList = @()

# Specify architecture-specific packages
# Uncomment to specify packages to install
# $DownloadList += $PackageList."x86"
# $DownloadList += $PackageList."x64"
# $DownloadList += $PackageList."arm64"

# Determine system architecture
[bool]$SystemIs64Bit = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture -like "*64*"
[bool]$CPUIsARM = $Env:PROCESSOR_ARCHITECTURE -like "*ARM*"

# Auto generate download list based on system architecture
if ($DownloadList.Count -eq 0) {
    if ($SystemIs64Bit) {
        Write-Host "Detected x64 system architecture." -ForegroundColor Yellow
        $DownloadList += $PackageList."x64"
        $DownloadList += $PackageList."x86"
    } else {
        Write-Host "Detected x86 system architecture." -ForegroundColor Yellow
        $DownloadList += $PackageList."x86"
    }
}

$DownloadList += $PackageList."directx"

# Prepare temporary directory
$TempPath = Join-Path -Path $env:TEMP -ChildPath (("vcrth_", [guid]::NewGuid().ToString()) -join "")
Write-Host "`nPreparing temporary directory..." -ForegroundColor Yellow
Write-Host "Using path $TempPath"
New-TempDirectory -Path $TempPath

# Prepare aria2c command
$aria2cPath = Get-Aria2Path -Path $TempPath -SystemIs64Bit $SystemIs64Bit -CPUIsARM $CPUIsARM

# Download and verify packages
Write-Host "`nStart downloading packages..." -ForegroundColor Yellow
foreach ($Package in $DownloadList) {
    $Name = $Package.friendlyname
    $FileName = ($Package.name, ".exe") -join ""
    $PackageDir = Join-Path -Path $TempPath -ChildPath $Package.name
    $FilePath = Join-Path -Path $PackageDir -ChildPath $FileName
    $PackageUrl = $Package.url
    $FileHash = $Package.hash
    [int]$TryCount = 0

    while ($TryCount -le 3) {
        New-TempDirectory -Path $PackageDir
        if ($TryCount -gt 0) {
            Write-Host "Retrying... attempt $TryCount" -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host "Downloading package: $Name..." -NoNewline
        }

        if ($aria2cPath -And ($TryCount -lt 3)) {
            $aria2cCommand = "& `"$aria2cPath`" --allow-overwrite=true --retry-wait=5 --max-connection-per-server=8 --split=8 --min-split-size=1M --continue=true --quiet=true --dir=`"$PackageDir`" --out=`"$FileName`" `"$PackageUrl`""
            Invoke-Expression $aria2cCommand
            $DownloadSuccess = $($LASTEXITCODE -eq 0)
        } else {
            Invoke-WebRequest -Uri $PackageUrl -OutFile $FilePath
            $DownloadSuccess = $($LASTEXITCODE -eq 0)
        }

        if ($DownloadSuccess) {
            Write-Host "success" -ForegroundColor Green
        } else {
            Write-Host "failed" -ForegroundColor Red
            $TryCount++
            continue
        }

        Write-Host "Checking file hash: $Name..." -NoNewline
        $CalculatedHash = (Get-FileHash -Path $FilePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash).ToLower()
        if ($CalculatedHash -eq $FileHash) {
            Write-Host "passed" -ForegroundColor Green
            $InstallList += $Package
            break
        } else {
            Write-Host "failed" -ForegroundColor Red
            $TryCount++
        }
    }
}

# Install packages
if ($InstallList.Count -eq 0) {
    Write-Host "No packages to install, passing..." -ForegroundColor Yellow
    exit
} else {
    Write-Host "`nStart installing packages..." -ForegroundColor Yellow
}

$InstallListPath = Join-Path -Path $TempPath -ChildPath "InstallList.json"
$InstallList | ConvertTo-Json | Set-Content -Path $InstallListPath

$InstallerPath = Join-Path -Path $TempPath -ChildPath "VCRuntimeInstaller.ps1"
Invoke-RestMethod -Uri $RemoteInstaller -OutFile $InstallerPath
Write-Host "Approve UAC prompt to continue installation." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" -Path `"$TempPath`"" -Wait

$SuccessListPath = Join-Path -Path $TempPath -ChildPath "SuccessList.json"
if (Test-Path -Path $SuccessListPath) {
    $SuccessList = Get-Content -Path $SuccessListPath | ConvertFrom-Json
}

foreach ($Package in $DownloadList) {
    if ($Package.friendlyname -notin $SuccessList) {
        $FailedList += $Package.friendlyname
    }
}

# Output installation summary
Write-Host "`n================ Installation Summary ================"
Write-Host "Total packages attempted: $($DownloadList.Count)"
Write-Host "Total packages installed: $($SuccessList.Count)"
Write-Host "Total packages failed: $($FailedList.Count)"
Write-Host "`n================ Packages Installed ================"
if ($SuccessList.Count -gt 0) {
    $SuccessList | ForEach-Object { Write-Host "$_" }
} else {
    Write-Host "No packages were installed successfully." -ForegroundColor Red
}
if ($FailedList.Count -gt 0) {
    Write-Host "`n================ Packages Failed ================"
    $FailedList | ForEach-Object { Write-Host "$_" }
} else {
    Write-Host "`nAll packages installed successfully!" -ForegroundColor Green
}

# Clean up temporary files
if (Test-Path $TempPath) {
    Write-Host "`nCleaning up temporary files..." -NoNewline
    Remove-Item -Path $TempPath -Recurse -Force

    if ($LASTEXITCODE -eq 0) {
        Write-Host "done" -ForegroundColor Green
    } else {
        Write-Host "failed" -ForegroundColor Red
        Write-Host "Please manually delete the temporary directory."
    }
}
