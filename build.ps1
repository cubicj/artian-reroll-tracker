$ErrorActionPreference = "Stop"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptPath "Artian Reroll Tracker"
$destination = Join-Path $scriptPath "..\..\Games\MonsterHunterWilds\Mods\Artian Reroll Tracker.zip"

Write-Host "=== Artian Reroll Tracker Build Script ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source:      $source" -ForegroundColor Yellow
Write-Host "Destination: $destination" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $source)) {
    Write-Host "Error: Source folder not found!" -ForegroundColor Red
    exit 1
}

if (Test-Path $destination) {
    Write-Host "Removing existing zip file..." -ForegroundColor Gray
    Remove-Item $destination -Force
}

Write-Host "Creating zip file..." -ForegroundColor Green
Write-Host ""

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::Open($destination, 'Create')

$fileCount = 0
Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
    $relativePath = $_.FullName.Substring((Get-Item $source).Parent.FullName.Length + 1)
    $entry = $relativePath.Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry) | Out-Null
    Write-Host "  [+] $entry" -ForegroundColor DarkGray
    $fileCount++
}

$zip.Dispose()

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "Total files: $fileCount" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open Fluffy Mod Manager" -ForegroundColor White
Write-Host "  2. Press F5 to refresh" -ForegroundColor White
Write-Host "  3. Check mod -> Apply" -ForegroundColor White
Write-Host "  4. Test in game (Insert key -> Artian Reroll Tracker)" -ForegroundColor White
Write-Host ""
