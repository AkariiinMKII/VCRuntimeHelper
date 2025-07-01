param (
    [string]$Path
)

$SuccessList = @()

$InstallListPath = Join-Path -Path $Path -ChildPath "InstallList.json"
if (Test-Path -Path $InstallListPath) {
    $InstallList = Get-Content -Path $InstallListPath | ConvertFrom-Json
} else {
    Write-Host "InstallList.json not found. Exiting..." -ForegroundColor Red
    return
}

foreach ($Package in $InstallList) {
    $Name = $Package.friendlyname
    $FileName = ($Package.name, ".exe") -join ""
    $PackageDir = Join-Path -Path $Path -ChildPath $Package.name
    $FilePath = Join-Path -Path $PackageDir -ChildPath $FileName

    Write-Host "Installing package: $Name..." -NoNewline
    try {
        if (-not (Test-Path -Path $FilePath)) {
            Write-Host "error: file not found" -ForegroundColor Red
            continue
        }
        if ($FileName -like "directx*") {
            Start-Process -FilePath $FilePath -ArgumentList "/Q /T:`"$PackageDir`"" -Wait
            $Result = Start-Process -FilePath "$PackageDir\DXSETUP.exe" -ArgumentList "/silent" -Wait -PassThru
        } elseif (($FileName -like "*2005*") -or ($FileName -like "*2008*")) {
            $Result = Start-Process -FilePath $FilePath -ArgumentList "/q" -Wait -PassThru
        } elseif (($FileName -like "*2010*") -or ($FileName -like "vstor*")) {
            $Result = Start-Process -FilePath $FilePath -ArgumentList "/q /norestart" -Wait -PassThru
        } else {
            $Result = Start-Process -FilePath $FilePath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
        }

        if ($Result.ExitCode -eq 0) {
            Write-Host "success" -ForegroundColor Green
            $SuccessList += $Name
        } else {
            Write-Host "failed" -ForegroundColor Red
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}
$SuccessList | ConvertTo-Json | Set-Content -Path (Join-Path -Path $Path -ChildPath "SuccessList.json")
