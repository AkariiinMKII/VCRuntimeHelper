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

function Remove-TempDirectory {
    param (
        [string]$Path
    )

    if (Test-Path $Path) {
        Write-Host "`nCleaning up temporary files... " -ForegroundColor Yellow -NoNewline
        try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
            Write-Host "done" -ForegroundColor Green
        } catch {
            Write-Host "failed" -ForegroundColor Red
            Write-Host "Please manually delete the temporary directory:"
            Write-Host "`"$Path`""
        }
    } else {
        Write-Host "`nTemporary directory not found, skipping cleanup..." -ForegroundColor Yellow
    }
}

function Get-Aria2Path {
    param (
        [string]$Path,
        [bool]$SystemIs64Bit,
        [bool]$CPUIsARM
    )

    Write-Host "`nPreparing aria2... " -ForegroundColor Yellow -NoNewline
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
        Remove-Item -Path $aria2cZip -Force -ErrorAction SilentlyContinue
        $aria2cPath = (Get-ChildItem -Path $Path -Recurse | Where-Object { $_.Name -like "aria2c.exe" } | Select-Object -First 1).FullName
    }
    if ($aria2cPath) {
        Write-Host "done" -ForegroundColor Green
        Write-Host "Using aria2c at `"$aria2cPath`""
        return $aria2cPath
    } else {
        Write-Host "failed" -ForegroundColor Red
        Write-Host "Falling back to Invoke-WebRequest."
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

function Invoke-FailExit {
    param (
        [string]$TempPath
    )

    Write-Host "failed" -ForegroundColor Red
    if ($TempPath) {
        Remove-TempDirectory -Path $TempPath
    }
    Write-Host "Exiting script execution..." -ForegroundColor Yellow
    exit 1
}

############################################################################
# Main script execution starts here

# Initialize script variables
$RemoteList = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeList.json"
$RemoteInstaller = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeInstaller.ps1"

Write-Host "`nRequesting package list... " -ForegroundColor Yellow -NoNewline

try {
    $PackageList = Invoke-RestMethod -Uri $RemoteList
} catch {
    Invoke-FailExit
}

if (-not [string]::IsNullOrWhiteSpace($PackageList)) {
    Write-Host "done" -ForegroundColor Green
} else {
    Invoke-FailExit
}

$DownloadList = @()
$InstallList = @()
$SuccessList = @()
$FailedList = @()

# Arch-specific packages
# Uncomment to specify packages to install
# $DownloadList += $PackageList."x86"
# $DownloadList += $PackageList."x64"
# $DownloadList += $PackageList."arm64"
# $DownloadList += $PackageList."directx"
# $DownloadList += $PackageList."vstor"

# Determine system environment
[bool]$SystemIs64Bit = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture -like "*64*"
[bool]$CPUIsARM = $Env:PROCESSOR_ARCHITECTURE -like "*ARM*"
$OSVersion = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Version

# Auto generate download list based on system environment
if ($DownloadList.Count -eq 0) {
    Write-Host "`nNo packages specified, generating installation list based on system environment..." -ForegroundColor Yellow
    if ($SystemIs64Bit) {
        if ($CPUIsARM -and ($OSVersion -lt "10.0.22000")) {
            # Add arm64 packages for Windows 10 ARM
            Write-Host "Detected 64-bit system architecture with Windows 10 ARM."
            $DownloadList += $PackageList."arm64"
        } else {
            # Add x64 packages for other x64 systems
            Write-Host "Detected 64-bit system architecture."
            $DownloadList += $PackageList."x64"
        }
    } else {
        Write-Host "Detected 32-bit system architecture."
    }
    # Always add x86 packages
    $DownloadList += $PackageList."x86"

    # Add other packages
    $DownloadList += $PackageList."directx"
    $DownloadList += $PackageList."vstor"
}

# Prepare temporary directory
$TempPath = Join-Path -Path $env:TEMP -ChildPath (("vcrth_", [guid]::NewGuid().ToString()) -join "")
Write-Host "`nPreparing temporary directory... " -ForegroundColor Yellow -NoNewline
New-TempDirectory -Path $TempPath
if (Test-Path -Path $TempPath) {
    Write-Host "done" -ForegroundColor Green
} else {
    Invoke-FailExit
}
Write-Host "Using path `"$TempPath\`""

 # Prepare installer script
$InstallerPath = Join-Path -Path $TempPath -ChildPath "VCRuntimeInstaller.ps1"
Write-Host "`nPreparing installer script... " -ForegroundColor Yellow -NoNewline
try  {
    Invoke-RestMethod -Uri $RemoteInstaller -OutFile $InstallerPath
} catch {
    Invoke-FailExit -TempPath $TempPath
}
Write-Host "done" -ForegroundColor Green

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
    $FileHash = ($Package.hash).ToLower()
    [int]$TryCount = 0

    while ($TryCount -le 3) {
        New-TempDirectory -Path $PackageDir
        if ($TryCount -gt 0) {
            Write-Host "Retry attempt $TryCount/3, downloading... " -ForegroundColor Yellow -NoNewline
        } else {
            Write-Host "Downloading package:  $Name... " -NoNewline
        }

        if ($aria2cPath -And ($TryCount -lt 3)) {
            $aria2cCommand = "& `"$aria2cPath`" --allow-overwrite=true --retry-wait=5 --max-connection-per-server=8 --split=8 --min-split-size=1M --continue=true --quiet=true --dir=`"$PackageDir`" --out=`"$FileName`" `"$PackageUrl`""
            Invoke-Expression $aria2cCommand
            $DownloadSuccess = $($LASTEXITCODE -eq 0)
        } else {
            try {
                Invoke-WebRequest -Uri $PackageUrl -OutFile $FilePath
                $DownloadSuccess = $($LASTEXITCODE -eq 0)
            } catch {
                Write-Host "failed" -ForegroundColor Red
                $TryCount++
                continue
            }
        }

        if ($DownloadSuccess) {
            Write-Host "success" -ForegroundColor Green
        } else {
            Write-Host "failed" -ForegroundColor Red
            $TryCount++
            continue
        }

        Write-Host "Checking file hash :  $Name... " -NoNewline
        $CalculatedHash = (Get-FileHash -Path $FilePath -Algorithm SHA256 | Select-Object -ExpandProperty Hash).ToLower()
        if ($CalculatedHash -eq $FileHash) {
            Write-Host "pass" -ForegroundColor Green
            $InstallList += $Package
            break
        } else {
            Write-Host "failed" -ForegroundColor Red
            $TryCount++
        }
    }
}

# Check download results
if ($InstallList.Count -eq 0) {
    Write-Host "`nAll package downloads failed, skipping installation..." -ForegroundColor Yellow
    Remove-TempDirectory -Path $TempPath
    exit 1
} else {
    Write-Host "`nSuccessfully downloaded " -NoNewline
    Write-Host "$($InstallList.Count) " -ForegroundColor Green -NoNewline
    Write-Host "of $($DownloadList.Count) packages."
}

# Install packages
Write-Host "`nStart installing packages..." -ForegroundColor Yellow

$InstallListPath = Join-Path -Path $TempPath -ChildPath "InstallList.json"
$InstallList | ConvertTo-Json | Set-Content -Path $InstallListPath

Write-Host "`nInstallation requires administrative privileges." -ForegroundColor Yellow
Write-Host "Approve UAC prompt to continue..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
Write-Host "`nDo not close this window until the entire script completes!" -ForegroundColor DarkRed -BackgroundColor Yellow
try {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$InstallerPath`" -Path `"$TempPath`"" -Wait
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Remove-TempDirectory -Path $TempPath
    Write-Host "Exiting script execution..." -ForegroundColor Yellow
    exit 1
}

Write-Host "`nInstallation script finished." -ForegroundColor Yellow

# Check installation results
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
Write-Host "`n============== Installation Summary =============="
Write-Host "Total packages attempted: $($DownloadList.Count)"
Write-Host "Total packages installed: " -NoNewline
Write-Host "$($SuccessList.Count)" -ForegroundColor Green
Write-Host "Total packages failed   : " -NoNewline
Write-Host "$($FailedList.Count)" -ForegroundColor Red
Write-Host "`n=============== Packages Installed ==============="
if ($SuccessList.Count -gt 0) {
    $SuccessList | ForEach-Object { Write-Host "$_" }
} else {
    Write-Host "No packages were installed successfully." -ForegroundColor Red
}
if ($FailedList.Count -gt 0) {
    Write-Host "`n================ Packages Failed ================="
    $FailedList | ForEach-Object { Write-Host "$_" }
} else {
    Write-Host "`nCongratulations! All packages installed successfully!" -ForegroundColor Green
}

# Clean up temporary files
Remove-TempDirectory -Path $TempPath

# Final message before exit
Write-Host "`nScript execution completed." -ForegroundColor Yellow
Write-Host "Press any key to exit..." -ForegroundColor Yellow
$null = [System.Console]::ReadKey($true)
exit 0
