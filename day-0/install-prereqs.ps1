#
# install-prereqs.ps1
# Installs or verifies Docker, kubectl, Helm, and kind.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
#
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$KindVersion = if ($env:KIND_VERSION) { $env:KIND_VERSION } else { 'v0.33.0' }
$BinDir = Join-Path $HOME '.local\bin'
$BinDirWasOnPath = ($env:PATH -split ';') -contains $BinDir
if (-not $BinDirWasOnPath) {
    $env:PATH = "$BinDir;$env:PATH"
}
$Architecture = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) {
    $Architecture = $env:PROCESSOR_ARCHITEW6432
}

switch -Regex ($Architecture) {
    '^(AMD64|x64)$' { $Arch = 'amd64'; break }
    '^(ARM64)$' { $Arch = 'arm64'; break }
    default { throw "[-] Unsupported Windows architecture: $Architecture" }
}

Write-Host "=== [durag / day-0] Checking prerequisites (windows/$Arch) ==="

$DockerCommand = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue
if (-not $DockerCommand) {
    Write-Host '[!] Docker CLI not found. Installing Docker Desktop with winget...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw '[-] Cannot install Docker Desktop automatically because winget is unavailable. Install Docker Desktop from https://www.docker.com/products/docker-desktop and rerun this script.'
    }

    & winget install --id Docker.DockerDesktop --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "[-] Docker Desktop installation failed (winget exit code $LASTEXITCODE). Retry from an elevated PowerShell session or install Docker Desktop manually."
    }

    $DockerCliPath = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'
    if (Test-Path (Join-Path $DockerCliPath 'docker.exe')) {
        $env:PATH = "$DockerCliPath;$env:PATH"
    }
    $DockerCommand = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue
    if (-not $DockerCommand) {
        throw '[-] Docker Desktop was installed, but docker.exe is not available in PATH. Restart PowerShell and rerun the bootstrap.'
    }
}

$DockerExe = $DockerCommand.Source
$DockerInfoReady = $false
& $DockerExe info *> $null
if ($LASTEXITCODE -eq 0) {
    $DockerInfoReady = $true
} else {
    $DockerDesktopPath = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $DockerDesktopPath) {
        Write-Host '[*] Starting Docker Desktop...'
        Start-Process -FilePath $DockerDesktopPath
        Write-Host '[*] Waiting for the Docker engine to become ready (up to 5 minutes)...'
        for ($Attempt = 0; $Attempt -lt 60; $Attempt++) {
            Start-Sleep -Seconds 5
            & $DockerExe info *> $null
            if ($LASTEXITCODE -eq 0) {
                $DockerInfoReady = $true
                break
            }
        }
    }
}
if (-not $DockerInfoReady) {
    throw '[-] Docker CLI is installed, but the Docker engine is not available. Start Docker Desktop and ensure its Linux container engine is running, then rerun the bootstrap. A Windows restart or WSL 2 setup may be required after first installation.'
}
Write-Host "[+] Docker is operational ($(& $DockerExe --version))"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "[!] kubectl not found. Installing to $BinDir..."
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $KubectlVersion = (Invoke-RestMethod -Uri 'https://dl.k8s.io/release/stable.txt').Trim()
    $KubectlPath = Join-Path $BinDir 'kubectl.exe'
    Invoke-WebRequest -UseBasicParsing -Uri "https://dl.k8s.io/release/$KubectlVersion/bin/windows/$Arch/kubectl.exe" -OutFile $KubectlPath
    Write-Host "[+] kubectl $KubectlVersion installed to $KubectlPath"
} else {
    Write-Host "[+] kubectl is available"
}

if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Helm not found. Installing to $BinDir..."
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $HelmRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/helm/helm/releases/latest'
    $HelmVersion = $HelmRelease.tag_name -replace '^v', ''
    $HelmArchive = Join-Path ([IO.Path]::GetTempPath()) ("helm-$([guid]::NewGuid().ToString('N')).zip")
    $ExtractDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "https://get.helm.sh/helm-$HelmVersion-windows-$Arch.zip" -OutFile $HelmArchive
        Expand-Archive -LiteralPath $HelmArchive -DestinationPath $ExtractDir
        Copy-Item -LiteralPath (Join-Path $ExtractDir "windows-$Arch\helm.exe") -Destination (Join-Path $BinDir 'helm.exe') -Force
    } finally {
        Remove-Item -LiteralPath $HelmArchive, $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[+] Helm $($HelmRelease.tag_name) installed to $(Join-Path $BinDir 'helm.exe')"
} else {
    Write-Host '[+] Helm is available'
}

if (-not (Get-Command kind -ErrorAction SilentlyContinue)) {
    if ($Arch -ne 'amd64') {
        throw '[-] kind does not provide a Windows ARM64 binary. Install kind from a supported environment or use Windows x64.'
    }
    Write-Host "[*] Downloading kind $KindVersion to $BinDir..."
    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $KindPath = Join-Path $BinDir 'kind.exe'
    Invoke-WebRequest -UseBasicParsing -Uri "https://kind.sigs.k8s.io/dl/$KindVersion/kind-windows-amd64" -OutFile $KindPath
    Write-Host "[+] kind installed to $KindPath"
} else {
    Write-Host '[+] kind is already installed'
}

if (-not $BinDirWasOnPath) {
    Write-Host "[!] Added $BinDir to PATH for this PowerShell session. Add it to your user PATH to persist it."
}

Write-Host "=== [durag / day-0] All prerequisites satisfied! ==="
