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

# ── DevHub integration prompt (skip on re-install if already configured) ─
$appSettingsPath = Join-Path $InstallDir 'appsettings.json'
$promptForDevHub = $true
if (Test-Path $appSettingsPath) {
    try {
        $existing = Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        if ($existing.DevHub -and $existing.DevHub.ApiKey) {
            $promptForDevHub = $false
            Write-Host "  [OK] DevHub already configured (user: $($existing.DevHub.UserName))" -ForegroundColor Green
        }
    } catch { /* fall through to prompt */ }
}

if ($promptForDevHub -and -not $env:CI -and [Environment]::UserInteractive) {
    Write-Host ""
    Write-Host "  ── DevHub integration ──────────────────────────────────────" -ForegroundColor Cyan
    Write-Host "  DevHub stores your shared playbooks and team-wide connections" -ForegroundColor Gray
    Write-Host "  centrally. Skip this if you don't have a DevHub API key yet —" -ForegroundColor Gray
    Write-Host "  the server will run in local-only mode and you can configure" -ForegroundColor Gray
    Write-Host "  DevHub later by editing appsettings.json." -ForegroundColor Gray
    Write-Host ""

    $apiKey = Read-Host "  DevHub API key (leave blank to skip)"
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $defaultUser = ""
        try {
            $defaultUser = (& whoami /upn 2>$null).Trim()
        } catch { $defaultUser = "" }
        if ([string]::IsNullOrWhiteSpace($defaultUser) -or -not $defaultUser.Contains('@')) {
            try { $defaultUser = (& git config --get user.email 2>$null).Trim() } catch { $defaultUser = "" }
        }
        $userPrompt = if ([string]::IsNullOrWhiteSpace($defaultUser)) {
            "  DevHub username (UPN/email)"
        } else {
            "  DevHub username (UPN/email) [default: $defaultUser]"
        }
        $userName = Read-Host $userPrompt
        if ([string]::IsNullOrWhiteSpace($userName)) { $userName = $defaultUser }
        $baseUrl = Read-Host "  DevHub base URL [default: https://devhub.caldwell.app]"
        if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = 'https://devhub.caldwell.app' }

        # Merge into appsettings.json. Preserves whatever else is in there.
        $settings = if (Test-Path $appSettingsPath) {
            Get-Content $appSettingsPath -Raw | ConvertFrom-Json
        } else { [PSCustomObject]@{} }
        if (-not $settings.DevHub) {
            $settings | Add-Member -MemberType NoteProperty -Name DevHub -Value ([PSCustomObject]@{}) -Force
        }
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name BaseUrl -Value $baseUrl -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name ApiKey -Value $apiKey -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name UserName -Value $userName -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name EnablePlaybookSync -Value $true -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name EnableConnectionSync -Value $true -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name CacheTtlSeconds -Value 60 -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name RequestTimeoutSeconds -Value 8 -Force
        $settings.DevHub | Add-Member -MemberType NoteProperty -Name OfflineModeBehavior -Value 'FallbackToLocal' -Force

        $settings | ConvertTo-Json -Depth 10 | Set-Content $appSettingsPath -Encoding UTF8
        Write-Host "  [OK] DevHub configured for $userName" -ForegroundColor Green
        Write-Host "  [INFO] Local connections.json + playbooks/ will auto-import to DevHub on next start." -ForegroundColor Gray
    } else {
        Write-Host "  [INFO] Skipping DevHub setup. Edit appsettings.json later to enable it." -ForegroundColor Yellow
    }
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
