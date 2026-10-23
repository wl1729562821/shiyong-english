# Installs the Windows release build as a desktop app:
#   1. copies build\windows\x64\runner\Release\ to D:\<app name>\
#   2. creates shortcuts on the Desktop and in the Start menu
#   3. writes release\<app name>-Windows.zip (copy it to another PC, unzip, run the exe)
#   4. removes the install / shortcuts / zip of the old name (the app used to be
#      called "lv xing ying yu 25 tian"); learning data lives in %APPDATA% and the
#      app imports it from the old folder on first start, so nothing is lost
# Run after: flutter build windows --release
# Usage: powershell -ExecutionPolicy Bypass -File tool\install_windows.ps1 [-InstallRoot D:\]
# Keep this file ASCII: Windows PowerShell 5.1 reads BOM-less UTF-8 as GBK,
# so the Chinese app names are built from char codes.

param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallRoot = 'D:\'
)
$ErrorActionPreference = 'Stop'

# "shi yong ying yu" (practical English)
$name = -join @([char]0x5B9E, [char]0x7528, [char]0x82F1, [char]0x8BED)
# old name: "lv xing ying yu 25 tian"
$oldName = -join @([char]0x65C5, [char]0x884C, [char]0x82F1, [char]0x8BED, '25', [char]0x5929)

$source = Join-Path $Root 'build\windows\x64\runner\Release'
$exeName = 'travel_english.exe'
if (-not (Test-Path (Join-Path $source $exeName))) {
    throw "Release build not found in $source - run: flutter build windows --release"
}
# only a copy running from a folder we are about to replace or delete blocks the install
$replaced = @((Join-Path $InstallRoot $name), (Join-Path $InstallRoot $oldName))
$blocking = Get-Process -Name 'travel_english' -ErrorAction SilentlyContinue |
    Where-Object { $p = $_.Path; $replaced | Where-Object { $p -and $p.StartsWith($_ + '\') } }
if ($blocking) {
    throw "The app is running from $($blocking[0].Path). Close it first, then run this script again."
}

# 1. copy (replace the old install, the learning progress lives in %APPDATA%, not here)
$dest = Join-Path $InstallRoot $name
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $dest -Recurse
$exe = Join-Path $dest $exeName
Write-Output "installed: $exe"

# 2. shortcuts
$shell = New-Object -ComObject WScript.Shell
$desc = [string]::Concat($name, ' - English for everyday life and travel')
$linkDirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
foreach ($dir in $linkDirs) {
    $lnk = $shell.CreateShortcut((Join-Path $dir ($name + '.lnk')))
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $dest
    $lnk.IconLocation = "$exe,0"
    $lnk.Description = $desc
    $lnk.Save()
    Write-Output "shortcut: $(Join-Path $dir ($name + '.lnk'))"
}

# 3. zip for other computers
$zipDir = Join-Path $Root 'release'
New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
$zip = Join-Path $zipDir ($name + '-Windows.zip')
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $dest -DestinationPath $zip
Write-Output "zip: $zip ($([Math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"

# 4. remove what the old name left behind (exact paths only)
$oldItems = @(
    (Join-Path $InstallRoot $oldName),
    (Join-Path $zipDir ($oldName + '-Windows.zip'))
) + ($linkDirs | ForEach-Object { Join-Path $_ ($oldName + '.lnk') })
foreach ($old in $oldItems) {
    if (Test-Path -LiteralPath $old) {
        Remove-Item -LiteralPath $old -Recurse -Force
        Write-Output "removed old: $old"
    }
}
