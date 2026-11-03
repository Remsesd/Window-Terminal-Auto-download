#Requires -Version 5.1
<#
  setup-winterm.ps1
  Modernize the Windows 10 terminal: Windows Terminal + PowerShell 7 + Oh My Posh.

  Usage (normal user shell):
      powershell -ExecutionPolicy Bypass -File .\setup-winterm.ps1

  Optional: run from an elevated prompt if a package insists on machine scope.
  Safe to re-run: existing profile/settings are backed up and the profile block
  is not duplicated.
#>

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$Message) Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor DarkGray }

Write-Host 'Windows Terminal setup for Windows 10' -ForegroundColor Green

# --- 0. OS check ---------------------------------------------------------
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 18362) {
    Write-Warning "Windows build $build is older than 18362 (1903). Windows Terminal is not supported. Update Windows first."
    return
}
Write-Note "Windows build: $build (OK)"

# --- 1. winget -----------------------------------------------------------
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning 'winget not found. Install "App Installer" from the Microsoft Store, then re-run this script.'
    return
}

# --- 2. packages ---------------------------------------------------------
$packages = @(
    'Microsoft.WindowsTerminal',
    'Microsoft.PowerShell',
    'JanDeDobbeleer.OhMyPosh',
    'ajeetdsouza.zoxide',
    'junegunn.fzf',
    'eza-community.eza',
    'sharkdp.bat',
    'sharkdp.fd',
    'BurntSushi.ripgrep.MSVC',
    'dandavison.delta',
    'JesseDuffield.lazygit',
    'gerardog.gsudo'
)

foreach ($id in $packages) {
    Write-Step "Install $id"
    winget install --id $id -e --accept-package-agreements --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Note $_ }
}

# Refresh PATH so tools installed just now are visible in this session.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

# --- 3. Nerd Font --------------------------------------------------------
Write-Step 'Install JetBrainsMono Nerd Font'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        oh-my-posh font install JetBrainsMono
    } catch {
        Write-Warning "Font install failed: $($_.Exception.Message)"
    }
} else {
    Write-Warning 'oh-my-posh not on PATH yet. Close this window, open PowerShell 7 once, then run: oh-my-posh font install JetBrainsMono'
}

# --- 4. Execution policy ------------------------------------------------
Write-Step 'Allow local profile scripts (CurrentUser = RemoteSigned)'
try {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
} catch {
    Write-Warning "Could not set execution policy: $($_.Exception.Message)"
}
$pwshExe = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
if (Test-Path $pwshExe) {
    & $pwshExe -NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" 2>&1 | Out-Null
}

# --- 5. PowerShell 7 profile --------------------------------------------
Write-Step 'Configure PowerShell 7 profile'
$profileDir  = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
$profileFile = Join-Path $profileDir 'Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$markerStart = '# >>> winterm-setup >>>'

$block = @'
# >>> winterm-setup >>>
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding           = [System.Text.UTF8Encoding]::new()

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $theme = if ($env:POSH_THEMES_PATH) { Join-Path $env:POSH_THEMES_PATH 'tokyonight_storm.omp.json' }
    if ($theme -and (Test-Path $theme)) {
        oh-my-posh init pwsh --config $theme | Invoke-Expression
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}

if (Get-Module -ListAvailable PSReadLine) {
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView
    } catch {
        try { Set-PSReadLineOption -PredictionSource History } catch { }
    }
    try {
        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    } catch { }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init pwsh --cmd cd | Out-String) })
}

if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    New-Alias -Name ls -Value eza -Option AllScope
}
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    New-Alias -Name cat -Value bat -Option AllScope
}
# <<< winterm-setup <<<
'@

if (Test-Path $profileFile) {
    $existing = Get-Content $profileFile -Raw
    if ($existing -match [regex]::Escape($markerStart)) {
        Write-Note "Setup block already present; leaving $profileFile untouched."
    } else {
        Copy-Item $profileFile "$profileFile.bak" -Force
        Add-Content -Path $profileFile -Value "`r`n$block"
        Write-Note "Appended setup block to $profileFile (backup: $profileFile.bak)."
    }
} else {
    Set-Content -Path $profileFile -Value $block -Encoding UTF8
    Write-Note "Created $profileFile."
}

# --- 6. Windows Terminal appearance defaults ----------------------------
Write-Step 'Tune Windows Terminal appearance defaults'
$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

$defaultsBlock = @'
"defaults": {
    "font": { "face": "JetBrainsMono Nerd Font", "size": 11 },
    "useAcrylic": false,
    "opacity": 100,
    "historySize": 5000,
    "copyOnSelect": true
}
'@

if (Test-Path $wtSettings) {
    Copy-Item $wtSettings "$wtSettings.bak" -Force
    $raw = Get-Content $wtSettings -Raw

    $rx = [regex]::new('"defaults"\s*:\s*\{\s*\}')
    $updated = $rx.Replace($raw, $defaultsBlock, 1)

    if ($updated -ne $raw) {
        [System.IO.File]::WriteAllText($wtSettings, $updated, $utf8NoBom)
        Write-Note 'Applied appearance tweaks (backup: settings.json.bak).'
    } else {
        Write-Note 'settings.json already has custom defaults; left untouched. Edit manually if you want the tweaks.'
    }
} else {
    $template = @"
{
    "`$schema": "https://aka.ms/terminal-profiles-schema",
    "profiles": {
    $defaultsBlock
    }
}
"@
    $wtDir = Split-Path $wtSettings -Parent
    New-Item -ItemType Directory -Force -Path $wtDir | Out-Null
    [System.IO.File]::WriteAllText($wtSettings, $template, $utf8NoBom)
    Write-Note 'Windows Terminal has not run yet; created a minimal settings.json with tuned defaults.'
}

# --- 7. Done ------------------------------------------------------------
Write-Host ''
Write-Host 'Done. Next steps:' -ForegroundColor Green
Write-Host '  1. Open Windows Terminal (Start menu -> "Terminal").'
Write-Host '  2. Settings > Startup > Default profile > choose "PowerShell 7".'
Write-Host '  3. Open a new PowerShell 7 tab: you should see the Oh My Posh prompt.'
Write-Host '  Docs: https://learn.microsoft.com/windows/terminal/'
