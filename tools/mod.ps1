#Requires -Version 5.1
<#
.SYNOPSIS
    Dev tooling for the mods in this repo. Each top level folder is an
    independent mod, and every command works on one of them at a time.

.DESCRIPTION
    sync     Mirror a mod into the game's Mods\Packs folder so it can be played.
             Copies only what changed and prunes files the mod no longer ships,
             so a renamed sprite doesn't linger in the install.

    package  Zip a mod for release into dist\, with dev artifacts left out. The
             zip is flat: main.lua and friends sit at the root, which is what
             Modlunky and spelunky.fyi expect when they extract a pack.

    list     Show the mods in this repo and whether each one is synced.

.PARAMETER Mod
    Which mod to act on. Defaults to the mod folder you're standing in, so
    `..\tools\mod.ps1 sync` works from inside Roffto\.

.PARAMETER All
    Act on every mod in the repo instead of just one.

.PARAMETER DryRun
    Print what would happen without touching a single file.

.EXAMPLE
    .\tools\mod.ps1 sync Roffto
    .\tools\mod.ps1 package Roffto
    .\tools\mod.ps1 sync -All -DryRun

.NOTES
    The game is found at the usual Steam location. Set SPELUNKY2_DIR if yours
    lives somewhere else:
        $env:SPELUNKY2_DIR = 'D:\SteamLibrary\steamapps\common\Spelunky 2'
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('sync', 'package', 'list')]
    [string]$Command = 'list',

    [Parameter(Position = 1)]
    [string]$Mod,

    [switch]$All,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Nothing matching these ever reaches the game folder or a release zip. Each
# pattern is matched against a file or directory name anywhere in the mod, so
# 'dist' kills the folder and '*.psd' kills the file. Add your own per mod in a
# .modignore file next to main.lua, one pattern per line.
$DevArtifacts = @(
    '.git', '.gitignore', '.gitattributes', '.modignore'
    '.vscode', '.idea', '.claude'
    'dist', '__pycache__'
    '*.psd', '*.xcf', '*.aseprite', '*.ase', '*.kra', '*.pdn', '*.clip'
    '*.bak', '*.orig', '*.tmp', '*.zip'
    'Thumbs.db', 'desktop.ini', '.DS_Store'
)

# Modlunky writes this into a pack folder, so a sync must never prune it.
$DestKeep = @('mod_info.json')

$DefaultGameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Spelunky 2'

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-GameRoot {
    if ($env:SPELUNKY2_DIR) {
        $dir = $env:SPELUNKY2_DIR
        if (-not (Test-Path -LiteralPath $dir)) {
            throw "SPELUNKY2_DIR points at '$dir', which doesn't exist."
        }
        return $dir
    }
    if (Test-Path -LiteralPath $DefaultGameDir) {
        return $DefaultGameDir
    }
    throw "Can't find Spelunky 2 at '$DefaultGameDir'. Set SPELUNKY2_DIR to your install."
}

function Get-PacksRoot {
    $packs = Join-Path (Get-GameRoot) 'Mods\Packs'
    if (-not (Test-Path -LiteralPath $packs)) {
        if ($DryRun) { return $packs }
        New-Item -ItemType Directory -Path $packs -Force | Out-Null
    }
    return $packs
}

function Get-ModDirs {
    Get-ChildItem -Path (Get-RepoRoot) -Directory |
        Where-Object { $_.Name -notmatch '^\.' -and $_.Name -notin @('tools', 'dist') } |
        Sort-Object Name
}

function Resolve-Mod {
    param([string]$Name)

    $mods = @(Get-ModDirs)
    $known = "Known mods:`n  " + (($mods | ForEach-Object { $_.Name }) -join "`n  ")

    if ($Name) {
        $hit = @($mods | Where-Object { $_.Name -ieq $Name })
        if ($hit.Count -eq 0) { throw "No mod folder named '$Name'. $known" }
        return $hit[0]
    }

    # No name given, so use the mod folder we're standing in.
    $cwd = (Get-Location).Path.TrimEnd('\').ToLower()
    foreach ($m in $mods) {
        $path = $m.FullName.TrimEnd('\').ToLower()
        if ($cwd -eq $path -or $cwd.StartsWith($path + '\')) { return $m }
    }
    throw "Name a mod, or run this from inside one. $known"
}

function Get-IgnorePatterns {
    param([System.IO.DirectoryInfo]$ModDir)

    $patterns = $DevArtifacts
    $ignoreFile = Join-Path $ModDir.FullName '.modignore'
    if (Test-Path -LiteralPath $ignoreFile) {
        $extra = Get-Content -LiteralPath $ignoreFile |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }
        $patterns = $patterns + $extra
    }
    return $patterns
}

# Relative paths of everything the mod actually ships.
function Get-ModFiles {
    param([System.IO.DirectoryInfo]$ModDir)

    $patterns = Get-IgnorePatterns $ModDir
    $root = $ModDir.FullName

    Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1)
        $keep = $true
        foreach ($segment in ($rel -split '\\')) {
            foreach ($pattern in $patterns) {
                if ($segment -like $pattern) { $keep = $false; break }
            }
            if (-not $keep) { break }
        }
        if ($keep) { $rel }
    }
}

function Get-SkippedCount {
    param([System.IO.DirectoryInfo]$ModDir, [int]$Kept)

    $total = @(Get-ChildItem -LiteralPath $ModDir.FullName -Recurse -File -Force).Count
    return $total - $Kept
}

# Version out of the meta block, for naming the zip. Level only mods have no
# main.lua, and go out unversioned.
function Get-ModVersion {
    param([System.IO.DirectoryInfo]$ModDir)

    $main = Join-Path $ModDir.FullName 'main.lua'
    if (-not (Test-Path -LiteralPath $main)) { return $null }

    $match = Select-String -LiteralPath $main -Pattern 'version\s*=\s*[''"]([^''"]+)[''"]' | Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value }
    return $null
}

function Copy-Tracked {
    param([string]$Source, [string]$Destination)

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Sync-Mod {
    param([System.IO.DirectoryInfo]$ModDir)

    $files = @(Get-ModFiles $ModDir)
    if ($files.Count -eq 0) {
        throw "'$($ModDir.Name)' has nothing to sync."
    }

    $dest = Join-Path (Get-PacksRoot) $ModDir.Name
    Write-Host "$($ModDir.Name) -> $dest" -ForegroundColor Cyan

    if (-not $DryRun -and -not (Test-Path -LiteralPath $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }

    $copied = 0
    foreach ($rel in $files) {
        $src = Join-Path $ModDir.FullName $rel
        $dst = Join-Path $dest $rel

        if (Test-Path -LiteralPath $dst) {
            $a = Get-Item -LiteralPath $src
            $b = Get-Item -LiteralPath $dst
            if ($a.Length -eq $b.Length -and $a.LastWriteTimeUtc -eq $b.LastWriteTimeUtc) { continue }
        }

        Write-Host "  + $rel" -ForegroundColor Green
        if (-not $DryRun) { Copy-Tracked -Source $src -Destination $dst }
        $copied++
    }

    # Prune anything the mod no longer ships, so a renamed sprite or a deleted
    # script doesn't keep running in the install.
    $removed = 0
    if (Test-Path -LiteralPath $dest) {
        $wanted = @{}
        foreach ($rel in $files) { $wanted[$rel.ToLower()] = $true }

        Get-ChildItem -LiteralPath $dest -Recurse -File -Force | ForEach-Object {
            if ($DestKeep -contains $_.Name) { return }
            $rel = $_.FullName.Substring($dest.Length + 1)
            if (-not $wanted.ContainsKey($rel.ToLower())) {
                Write-Host "  - $rel" -ForegroundColor DarkYellow
                if (-not $DryRun) { Remove-Item -LiteralPath $_.FullName -Force }
                $removed++
            }
        }

        if (-not $DryRun) {
            Get-ChildItem -LiteralPath $dest -Recurse -Directory -Force |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object {
                    if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
                        Remove-Item -LiteralPath $_.FullName -Force
                    }
                }
        }
    }

    $skipped = Get-SkippedCount -ModDir $ModDir -Kept $files.Count
    $summary = "  $($files.Count) file(s) in sync, $copied updated, $removed pruned"
    if ($skipped -gt 0) { $summary += ", $skipped dev artifact(s) left behind" }
    Write-Host $summary -ForegroundColor DarkGray
}

function New-ModPackage {
    param([System.IO.DirectoryInfo]$ModDir)

    $files = @(Get-ModFiles $ModDir)
    if ($files.Count -eq 0) {
        throw "'$($ModDir.Name)' has nothing to package."
    }

    $version = Get-ModVersion $ModDir
    $name = $ModDir.Name -replace '\s+', '-'
    if ($version) { $zipName = "$name-$version.zip" } else { $zipName = "$name.zip" }

    $distDir = Join-Path (Get-RepoRoot) 'dist'
    $zip = Join-Path $distDir $zipName

    Write-Host "$($ModDir.Name) -> $zip" -ForegroundColor Cyan
    foreach ($rel in $files) { Write-Host "  + $rel" -ForegroundColor Green }

    $skipped = Get-SkippedCount -ModDir $ModDir -Kept $files.Count
    $summary = "  $($files.Count) file(s)"
    if ($skipped -gt 0) { $summary += ", $skipped dev artifact(s) left out" }
    Write-Host $summary -ForegroundColor DarkGray

    if ($DryRun) { return }

    if (-not (Test-Path -LiteralPath $distDir)) {
        New-Item -ItemType Directory -Path $distDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

    # Written entry by entry rather than with Compress-Archive, which on
    # PowerShell 5.1 separates paths with backslashes. Python reads those as a
    # file called "Data\Levels\abzu.lvl" instead of a folder, which breaks
    # Modlunky and spelunky.fyi on any mod that ships a Data folder.
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

    $archive = [System.IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        foreach ($rel in $files) {
            $entry = $rel -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive,
                (Join-Path $ModDir.FullName $rel),
                $entry,
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Show-Mods {
    $packs = Join-Path (Get-GameRoot) 'Mods\Packs'
    foreach ($m in Get-ModDirs) {
        $files = @(Get-ModFiles $m)
        $synced = Test-Path -LiteralPath (Join-Path $packs $m.Name)
        if ($synced) { $mark = 'synced' } else { $mark = '      ' }
        Write-Host ("  {0}  {1,-20} {2} file(s)" -f $mark, $m.Name, $files.Count)
    }
    Write-Host ''
    Write-Host "  packs: $packs" -ForegroundColor DarkGray
}

if ($Command -eq 'list') {
    Show-Mods
    return
}

if ($All) {
    $targets = @(Get-ModDirs)
} else {
    $targets = @(Resolve-Mod -Name $Mod)
}

foreach ($target in $targets) {
    if ($Command -eq 'sync') {
        Sync-Mod -ModDir $target
    } else {
        New-ModPackage -ModDir $target
    }
}

if ($DryRun) {
    Write-Host ''
    Write-Host 'Dry run: nothing was written.' -ForegroundColor Yellow
}
