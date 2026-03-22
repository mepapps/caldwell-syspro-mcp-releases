<#
.SYNOPSIS
    One-liner installer for Caldwell SYSPRO MCP Server.

.DESCRIPTION
    Downloads and installs the Caldwell SYSPRO MCP Server portable deployment.
    Supports latest (stable) and beta channels, and single-file or standard deployment.

.PARAMETER Channel
    Release channel: 'latest' (default) or 'beta'.

.PARAMETER Type
    Deployment type: 'single' (default, one exe) or 'standard' (multi-file).

.PARAMETER InstallDir
    Installation directory. Defaults to $env:LOCALAPPDATA\caldwell-syspro-mcp.

.EXAMPLE
    # Install latest stable (single-file):
    irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1 | iex

    # Install beta channel:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1))) -Channel beta

    # Install standard (multi-file) deployment:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1))) -Type standard

    # Install to custom directory:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1))) -InstallDir C:\MCP
#>
param(
    [ValidateSet('latest', 'beta')]
    [string]$Channel = 'latest',

    [ValidateSet('single', 'standard')]
    [string]$Type = 'single',

    [string]$InstallDir = "C:\Tools\caldwell-syspro-mcp"
)

$ErrorActionPreference = 'Stop'
$repo = 'mepapps/caldwell-syspro-mcp-releases'

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host "   Caldwell SYSPRO MCP Server — Installer" -ForegroundColor Cyan
Write-Host "  ============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Channel:    $Channel" -ForegroundColor White
Write-Host "  Type:       $Type" -ForegroundColor White
Write-Host "  Install to: $InstallDir" -ForegroundColor White
Write-Host ""

# ── Find the right release ──────────────────────────────────────────
Write-Host "  Finding latest $Channel release..." -ForegroundColor Gray

if ($Channel -eq 'latest') {
    # /releases/latest always returns the latest non-prerelease
    $releaseUrl = "https://api.github.com/repos/$repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'caldwell-mcp-installer' }
    } catch {
        Write-Host "  [ERROR] Could not fetch latest release: $_" -ForegroundColor Red
        Write-Host "  Visit https://github.com/$repo/releases to download manually." -ForegroundColor Yellow
        return
    }
} else {
    # For beta, get all releases and pick the first prerelease
    $releasesUrl = "https://api.github.com/repos/$repo/releases"
    try {
        $releases = Invoke-RestMethod -Uri $releasesUrl -Headers @{ 'User-Agent' = 'caldwell-mcp-installer' }
        $release = $releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
        if (-not $release) {
            Write-Host "  [ERROR] No beta releases found." -ForegroundColor Red
            Write-Host "  Use -Channel latest for the stable release." -ForegroundColor Yellow
            return
        }
    } catch {
        Write-Host "  [ERROR] Could not fetch releases: $_" -ForegroundColor Red
        return
    }
}

$tag = $release.tag_name
Write-Host "  Found: $($release.name) ($tag)" -ForegroundColor Green

# ── Find the right asset ────────────────────────────────────────────
$assetPattern = if ($Type -eq 'single') { "*-single-*" } else { "*-standard-*" }
# Fallback: if no type-specific asset, try the generic zip
$asset = $release.assets | Where-Object { $_.name -like $assetPattern -and $_.name -like "*.zip" } | Select-Object -First 1
if (-not $asset) {
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
}

if (-not $asset) {
    Write-Host "  [ERROR] No zip asset found in release $tag" -ForegroundColor Red
    Write-Host "  Visit https://github.com/$repo/releases/tag/$tag to download manually." -ForegroundColor Yellow
    return
}

$downloadUrl = $asset.browser_download_url
$assetName = $asset.name
Write-Host "  Downloading: $assetName" -ForegroundColor Gray

# ── Download ────────────────────────────────────────────────────────
$tempZip = Join-Path $env:TEMP "caldwell-mcp-install-$tag.zip"
$tempExtract = Join-Path $env:TEMP "caldwell-mcp-install-$tag"

try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing
    Write-Host "  [OK] Downloaded ($([math]::Round((Get-Item $tempZip).Length / 1MB, 1)) MB)" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Download failed: $_" -ForegroundColor Red
    return
}

# ── Backup user files ───────────────────────────────────────────────
$userFiles = @('connections.json', 'key-entities.custom.json')
$backups = @{}

if (Test-Path $InstallDir) {
    foreach ($f in $userFiles) {
        $path = Join-Path $InstallDir $f
        if (Test-Path $path) {
            $backupPath = Join-Path $env:TEMP "caldwell-mcp-backup-$f"
            Copy-Item $path $backupPath -Force
            $backups[$f] = $backupPath
            Write-Host "  [OK] Backed up $f" -ForegroundColor Green
        }
    }
}

# ── Extract ─────────────────────────────────────────────────────────
Write-Host "  Extracting..." -ForegroundColor Gray

if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

# Create install directory
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Copy files
Copy-Item -Path "$tempExtract\*" -Destination $InstallDir -Recurse -Force
Write-Host "  [OK] Installed to $InstallDir" -ForegroundColor Green

# ── Restore user files ──────────────────────────────────────────────
foreach ($f in $backups.Keys) {
    Copy-Item $backups[$f] (Join-Path $InstallDir $f) -Force
    Write-Host "  [OK] Restored $f" -ForegroundColor Green
}

# ── Cleanup ─────────────────────────────────────────────────────────
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
foreach ($b in $backups.Values) { Remove-Item $b -Force -ErrorAction SilentlyContinue }

# ── First-time setup ───────────────────────────────────────────────
$connectionsPath = Join-Path $InstallDir 'connections.json'
$samplePath = Join-Path $InstallDir 'connections.sample.json'

if (-not (Test-Path $connectionsPath) -and (Test-Path $samplePath)) {
    Copy-Item $samplePath $connectionsPath
    Write-Host "  [OK] Created connections.json from sample" -ForegroundColor Green
}

# ── Determine exe name ──────────────────────────────────────────────
$exePath = Join-Path $InstallDir 'Caldwell.Syspro.Mcp.Server.exe'
if (-not (Test-Path $exePath)) {
    # Single-file on linux or other platform
    $exePath = Join-Path $InstallDir 'Caldwell.Syspro.Mcp.Server'
}

# ── Done ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   INSTALLED SUCCESSFULLY — $tag ($Type)" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Location: $InstallDir" -ForegroundColor White
Write-Host ""
Write-Host "  NEXT STEPS:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Edit connections.json with your SQL Server connection details" -ForegroundColor White
Write-Host "     $connectionsPath" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Add to your MCP client config:" -ForegroundColor White
Write-Host ""
Write-Host "     Claude Desktop (claude_desktop_config.json):" -ForegroundColor Gray
Write-Host "     {" -ForegroundColor DarkGray
Write-Host "       `"mcpServers`": {" -ForegroundColor DarkGray
Write-Host "         `"caldwell-syspro`": {" -ForegroundColor DarkGray
Write-Host "           `"command`": `"$($exePath -replace '\\', '\\')`"" -ForegroundColor DarkGray
Write-Host "         }" -ForegroundColor DarkGray
Write-Host "       }" -ForegroundColor DarkGray
Write-Host "     }" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. Restart your MCP client" -ForegroundColor White
Write-Host ""
