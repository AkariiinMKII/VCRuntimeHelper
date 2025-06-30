# $RemoteScript = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeHelper.ps1"
$RemoteList = "https://raw.githubusercontent.com/AkariiinMKII/VCRuntimeHelper/refs/heads/main/VCRuntimeList.json"

$PackageList = Invoke-RestMethod -Uri $RemoteList
$DownloadList = @()
$InstallList = @()
$SuccessList = @()
$FailedList = @()

# Specify architecture-specific packages
# Uncomment to specify packages to install
# $DownloadList += $PackageList."x86"
# $DownloadList += $PackageList."amd64"
# $DownloadList += $PackageList."arm64"

# Determine system architecture
[bool]$SystemIs64Bit = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture -like "*64*"
[bool]$CPUIsARM = $Env:PROCESSOR_ARCHITECTURE -like "*ARM*"

# Auto generate download list based on system architecture
if ($DownloadList.Count -eq 0) {
    if ($SystemIs64Bit -and $CPUIsARM) {
        Write-Host "Detected ARM64 system architecture." -ForegroundColor Yellow
        $DownloadList += $PackageList."arm64"
    } elseif ($SystemIs64Bit) {
        Write-Host "Detected AMD64 system architecture." -ForegroundColor Yellow
        $DownloadList += $PackageList."amd64"
        $DownloadList += $PackageList."x86"
    } else {
        Write-Host "Detected x86 system architecture." -ForegroundColor Yellow
        $DownloadList += $PackageList."x86"
    }
}

$DownloadList += $PackageList."directx"

$TempPath = "$env:TEMP\VCRuntimeHelper"
if (-not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}
Get-ChildItem -Path $TempPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Prepare aria2c command
$aria2cPath = Get-Aria2Command -TempPath $TempPath -SystemIs64Bit $SystemIs64Bit -CPUIsARM $CPUIsARM

# Download and verify packages
Write-Host "`nStart downloading packages..." -ForegroundColor Yellow
foreach ($Package in $DownloadList) {
    $PackageName = $Package.friendlyname
    $FileName = ($Package.name, ".exe") -join ""
    $FilePath = Join-Path -Path $TempPath -ChildPath $FileName
    $PackageUrl = $Package.url
    $FileHash = $Package.hash
    [int]$TryCount = 0

    while ($TryCount -le 3) {
        if ($TryCount -gt 0) {
            Write-Host "Retrying... Attempt $TryCount" -ForegroundColor Yellow
            Get-ChildItem -Path $FilePath -ErrorAction SilentlyContinue | Remove-Item -Force
        }

        Write-Host "Downloading package: $PackageName..." -NoNewline
        if ($aria2cPath -And ($TryCount -lt 3)) {
            $aria2cCommand = "& `"$aria2cPath`" --allow-overwrite=true --retry-wait=5 --max-connection-per-server=8 --split=8 --min-split-size=1M --continue=true --quiet=true --dir=`"$TempPath`" --out=`"$FileName`" `"$PackageUrl`""
            Invoke-Expression $aria2cCommand
            $DownloadSuccess = $($LASTEXITCODE -eq 0)
        } else {
            Invoke-WebRequest -Uri $PackageUrl -OutFile $FilePath
            $DownloadSuccess = $($LASTEXITCODE -eq 0)
        }

        if (-not $DownloadSuccess) {
            Write-Host "failed" -ForegroundColor Red
            $TryCount++
            continue
        } else {
            Write-Host "success" -ForegroundColor Green
        }

        Write-Host "Checking file hash: $PackageName..." -NoNewline
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
Write-Host "`nStart installing packages..." -ForegroundColor Yellow
foreach ($Package in $InstallList) {
    $PackageName = $Package.friendlyname
    $FileName = ($Package.name, ".exe") -join ""
    $FilePath = Join-Path -Path $TempPath -ChildPath $FileName

    Write-Host "Installing package: $PackageName..." -NoNewline
    try {
        if ($FileName -like "directx*") {
            Start-Process -FilePath $FilePath -ArgumentList "/Q /T:`"$TempPath`"" -Wait
            Start-Process -FilePath "$TempPath\DXSETUP.exe" -ArgumentList "/silent" -Wait
        } elseif (($FileName -like "*2005*") -or ($FileName -like "*2008*")) {
            Start-Process -FilePath $FilePath -ArgumentList "/q" -Wait
        } else {
            Start-Process -FilePath $FilePath -ArgumentList "/quiet /norestart" -Wait
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "success" -ForegroundColor Green
            $SuccessList += $PackageName
        } else {
            Write-Host "failed" -ForegroundColor Red
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
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
    Write-Host "All packages installed successfully!" -ForegroundColor Green
}

# Clean up temporary files
if (Test-Path $TempPath) {
    Write-Host "`nCleaning up temporary files..."
    Remove-Item -Path $TempPath -Recurse -Force
}

function Get-Aria2Command {
    param (
        [string]$TempPath,
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
        $aria2cZip = Join-Path -Path $TempPath -ChildPath "aria2c.zip"
        Invoke-WebRequest -Uri $aria2cUrl -OutFile $aria2cZip
        Expand-Archive -Path $aria2cZip -DestinationPath $TempPath -Force
        Remove-Item -Path $aria2cZip -Force
        $aria2cPath = (Get-ChildItem -Path $TempPath -Recurse | Where-Object { $_.Name -like "aria2c.exe" } | Select-Object -First 1).FullName
    }
    if ($aria2cPath) {
        Write-Host "Using aria2c at $aria2cPath"
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
