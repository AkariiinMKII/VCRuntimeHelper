$PackageList = Get-Content .\VCRuntimeList.json | ConvertFrom-Json

$TempPath = Join-Path -Path $env:TEMP -ChildPath (("vcrh_phu_", [guid]::NewGuid().ToString()) -join "")
if (-Not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}
Get-ChildItem -Path $TempPath | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

[int]$HashChanges = 0

$Redists = $PackageList | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name

$Redists | ForEach-Object {
    $PackageList.$_ | ForEach-Object {
        $FileName = ($_.name, ".exe") -join ""
        $FilePath = Join-Path -Path $TempPath -ChildPath $FileName
        Write-Host "`nDownloading $FileName..." -ForegroundColor Yellow
        if (-Not (Test-Path $FilePath)) {
            if (Get-Command "aria2c" -ErrorAction SilentlyContinue) {
                # Use aria2c for downloading if available
                $aria2cPath = (Get-Command "aria2c").Source
                & $aria2cPath -x 8 -s 8 -k 1M -d $TempPath -o $FileName $_.url --console-log-level=warn
            } else {
                # Fallback to Invoke-WebRequest
                Invoke-WebRequest -Uri $_.url -OutFile $FilePath
            }
        }
        $NewHash = ((Get-FileHash $FilePath).Hash).ToLower()
        Write-Host "Hash value: " -ForegroundColor Yellow -NoNewline
        Write-Host "$NewHash" -ForegroundColor Green
        if ($NewHash -eq $_.hash) {
            Write-Host "No changes detected, skipping update..." -ForegroundColor Yellow
        } else {
            Write-Host "Changes detected, updating hash..." -ForegroundColor Green
            $_.hash = $NewHash
            $HashChanges++
        }
    }
}

if ($HashChanges -eq 0) {
    Write-Host "`nNo hash changes detected, skipping update..." -ForegroundColor Yellow
} else {
    Write-Host "`n$HashChanges " -ForegroundColor Green -NoNewline
    Write-Host "hash changes detected, updating package list..." -ForegroundColor Yellow
    $PackageList | ConvertTo-Json | Set-Content .\VCRuntimeList.json
}

Write-Host "`nCleaning up temporary files..." -ForegroundColor Yellow
Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
