# Build the side-by-side Windows x64 self-hosted desktop app.
#
# This script does not clone the repository and does not download a second
# copy of it. Run it from an already extracted source tree. It also does not
# register the official Explorer thumbnail CLSID, does not take file
# associations, and does not publish a release.
#
# Verified host for the cross build that produced the shipped installer:
#   Node.js 24.22.2
#   pnpm 11.1.1
#   rustc 1.99.1 (MSRV in Cargo.toml is 1.90)
#   @tauri-apps/cli 2.11.4
#   target x86_64-pc-windows-msvc
# Native Windows link uses the installed VS 2022 C++ tools. The Linux cross
# build used cargo-xwin 0.23.1 instead of MSVC 14.44.35207; do not treat those
# as the same toolchain.
#
# Cargo still fetches the localsend git dependency while compiling. That is
# not a clone of this repository. Git has to be on PATH for a native rebuild.
# The prebuilt installer does not need Git, Node, or a clone.

$ErrorActionPreference = 'Stop'

$NodeVersion = '24.22.2'
$PnpmVersion = '11.1.1'
$RustVersion = '1.99.1'
$RustTarget = 'x86_64-pc-windows-msvc'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AppDir = Join-Path $RepoRoot 'apps\readest-app'
Set-Location $RepoRoot

function Fail([string]$Message) {
  Write-Error $Message
  exit 1
}

foreach ($required in @(
    'packages\foliate-js\package.json',
    'packages\tauri\crates\tauri\Cargo.toml',
    'packages\simplecc-wasm\dist\web\simplecc_wasm.js',
    'packages\js-mdict\package.json',
    'apps\readest-app\src-tauri\plugins\tauri-plugin-turso\Cargo.toml',
    'apps\readest-app\src-tauri\plugins\tauri-plugin-webview-upgrade\Cargo.toml'
  )) {
  if (-not (Test-Path (Join-Path $RepoRoot $required))) {
    Fail "Missing $required. This tree was not extracted with its submodules. The script will not clone them."
  }
}

function Ensure-Node {
  $current = $null
  if (Get-Command node -ErrorAction SilentlyContinue) {
    $current = (& node -v).Trim().TrimStart('v')
  }
  if ($current -eq $NodeVersion) { return }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "Node.js $NodeVersion is required (found '$current'). Install https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-x64.msi"
  }
  Write-Host "Installing Node.js $NodeVersion with winget"
  & winget install --id OpenJS.NodeJS.LTS --exact --version $NodeVersion --scope user --accept-package-agreements --accept-source-agreements
  if ($LASTEXITCODE -ne 0) {
    Fail "winget could not install Node.js $NodeVersion. Install https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-x64.msi and re-run."
  }
  $machineNode = Join-Path $env:ProgramFiles 'nodejs'
  $userNode = Join-Path $env:LOCALAPPDATA 'Programs\nodejs'
  if (Test-Path (Join-Path $userNode 'node.exe')) { $env:Path = "$userNode;$env:Path" }
  elseif (Test-Path (Join-Path $machineNode 'node.exe')) { $env:Path = "$machineNode;$env:Path" }
  $current = (& node -v).Trim().TrimStart('v')
  if ($current -ne $NodeVersion) {
    Fail "node is $current after install; expected $NodeVersion. Open a new terminal so PATH refreshes."
  }
}

function Ensure-Rust {
  if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Fail 'rustup is not on PATH. The machine was described as having rustup installed.'
  }
  & rustup toolchain install $RustVersion --profile minimal
  & rustup target add $RustTarget --toolchain $RustVersion
  $hostTriple = 'x86_64-pc-windows-msvc'
  $toolchainBin = Join-Path $env:USERPROFILE ".rustup\toolchains\$RustVersion-$hostTriple\bin"
  if (-not (Test-Path (Join-Path $toolchainBin 'cargo.exe'))) {
    Fail "cargo.exe was not found at $toolchainBin"
  }
  # Session PATH only. Does not change rustup's default toolchain.
  $env:Path = "$toolchainBin;$env:Path"
  $actual = & rustc --version
  if ($actual -notmatch [regex]::Escape($RustVersion)) {
    Fail "rustc is '$actual'; expected $RustVersion. PATH was not prepended with $toolchainBin."
  }
}

function Show-Msvc {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) {
    Fail "vswhere.exe is missing. Install VS 2022 Build Tools with the C++ workload."
  }
  $install = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $install) { Fail 'VS 2022 C++ x64 tools were not found.' }
  $msvcRoot = Join-Path ($install | Select-Object -First 1) 'VC\Tools\MSVC'
  $toolsets = @(Get-ChildItem $msvcRoot -Directory | Select-Object -ExpandProperty Name)
  Write-Host "MSVC toolsets: $($toolsets -join ', ')"
  if ($toolsets -notcontains '14.44.35207') {
    Write-Host 'WARNING: MSVC 14.44.35207 was the reported installed toolset. cargo will use whichever VS 2022 toolset it discovers.'
  }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Fail 'git is not on PATH. A native rebuild fetches the localsend crate by git rev. This script does not clone Readest; install Git only so Cargo can fetch that dependency, or use the prebuilt installer instead.'
}

Ensure-Node
Ensure-Rust
Show-Msvc

& corepack enable
& corepack prepare "pnpm@$PnpmVersion" --activate
$pnpmActual = & pnpm -v
if ($pnpmActual.Trim() -ne $PnpmVersion) {
  Fail "pnpm is $pnpmActual; expected $PnpmVersion"
}

$env:NEXT_PUBLIC_SELF_HOSTED = 'true'
$env:NEXT_PUBLIC_APP_PLATFORM = 'tauri'
# Leave supabase / API / quota unset unless the operator exported them.
# Unset means the public client defaults already in apps/readest-app/.env.
# Those defaults do not grant a paid plan.

& pnpm install --frozen-lockfile
if ($LASTEXITCODE -ne 0) { Fail 'pnpm install failed' }
& pnpm --filter @readest/readest-app setup-vendors
if ($LASTEXITCODE -ne 0) { Fail 'setup-vendors failed' }

Set-Location $AppDir
& node .\node_modules\@tauri-apps\cli\tauri.js build `
  --config src-tauri\tauri.selfhosted.windows.json `
  --target $RustTarget `
  --bundles nsis
if ($LASTEXITCODE -ne 0) { Fail 'tauri build failed' }

Write-Host 'Build finished.'
Write-Host "exe: $RepoRoot\target\$RustTarget\release\readest-selfhosted.exe"
Write-Host "nsis: $RepoRoot\target\$RustTarget\release\bundle\nsis\"
