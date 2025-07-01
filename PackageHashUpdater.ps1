$PackageList = Get-Content .\VCRuntimeList.json | ConvertFrom-Json

$TempPath = "$env:TEMP\VCRuntimeHelper"
if (-Not (Test-Path $TempPath)) {
    New-Item -Path $TempPath -ItemType Directory | Out-Null
}
Get-ChildItem -Path $TempPath -Recurse | Remove-Item -Force -ErrorAction SilentlyContinue

"x86", "x64", "arm64", "directx" | ForEach-Object {
    $PackageList.$_ | ForEach-Object {
        $FileName = ($_.name, ".exe") -join ""
        $FilePath = Join-Path -Path $TempPath -ChildPath $FileName
        if (-Not (Test-Path $FilePath)) {
            Invoke-WebRequest -Uri $_.url -OutFile $FilePath
        }
        $_.hash = ((Get-FileHash $FilePath).Hash).ToLower()
    }
}

$PackageList | ConvertTo-Json | Set-Content .\VCRuntimeList.json

Remove-Item -Path $TempPath -Recurse -Force -ErrorAction SilentlyContinue
