#
# bootstrap.ps1
# Bootstraps a local kind Kubernetes cluster with a local container registry.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
#
[CmdletBinding()]
param(
    [string]$Name = $(if ($env:CLUSTER_NAME) { $env:CLUSTER_NAME } else { 'durag-local' }),
    [ValidateRange(1, 65535)]
    [int]$HttpPort = $(if ($env:HTTP_PORT) { [int]$env:HTTP_PORT } else { 8088 }),
    [ValidateRange(1, 65535)]
    [int]$HttpsPort = $(if ($env:HTTPS_PORT) { [int]$env:HTTPS_PORT } else { 8443 }),
    [switch]$WithIngress
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BaseConfig = Join-Path $ScriptDir 'kind-config.yaml'
$RegistryName = if ($env:REG_NAME) { $env:REG_NAME } else { 'kind-registry' }
$RegistryPort = if ($env:REG_PORT) { [int]$env:REG_PORT } else { 5001 }
if ($RegistryPort -lt 1 -or $RegistryPort -gt 65535) {
    throw "REG_PORT must be between 1 and 65535; received $RegistryPort."
}
if ($env:WITH_INGRESS -eq 'true') {
    $WithIngress = $true
}

Write-Host '======================================================'
Write-Host '    durag Day-0: Bootstrapping Local kind Cluster     '
Write-Host '    OS:         Windows'
Write-Host "    Cluster:    $Name"
Write-Host "    Registry:   localhost:$RegistryPort ($RegistryName)"
Write-Host "    Ingress:    http://localhost:$HttpPort / https://localhost:$HttpsPort"
Write-Host '======================================================'

& (Join-Path $ScriptDir 'install-prereqs.ps1')

$BinDir = Join-Path $HOME '.local\bin'
if (($env:PATH -split ';') -notcontains $BinDir) {
    $env:PATH = "$BinDir;$env:PATH"
}

$Clusters = & kind get clusters 2>$null
if (($LASTEXITCODE -eq 0) -and ($Clusters -contains $Name)) {
    Write-Host "[!] Cluster '$Name' already exists."
    Write-Host "    To delete and recreate it, run: kind delete cluster --name $Name"
    Write-Host "    Switching context to kind-$Name..."
    & kubectl config use-context "kind-$Name"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to switch kubectl context.' }
    return
}

Write-Host "[*] Ensuring local container registry '$RegistryName' is running on port $RegistryPort..."
$RegistryRunning = & docker inspect -f '{{.State.Running}}' $RegistryName 2>$null
if ($LASTEXITCODE -ne 0 -or $RegistryRunning -ne 'true') {
    if ($LASTEXITCODE -eq 0) {
        & docker rm -f $RegistryName
        if ($LASTEXITCODE -ne 0) { throw 'Failed to remove the stopped registry container.' }
    }
    & docker run -d --restart=always -p "127.0.0.1:${RegistryPort}:5000" --network bridge --name $RegistryName registry:2
    if ($LASTEXITCODE -ne 0) { throw 'Failed to start the local registry container.' }
    Write-Host "[+] Local registry started at localhost:$RegistryPort"
} else {
    Write-Host "[+] Local registry '$RegistryName' is already running at localhost:$RegistryPort"
}

$RenderedConfig = Join-Path ([IO.Path]::GetTempPath()) "kind-config-$([guid]::NewGuid().ToString('N')).yaml"
try {
    $Config = [IO.File]::ReadAllText($BaseConfig)
    $Config = $Config.Replace('hostPort: 8088', "hostPort: $HttpPort")
    $Config = $Config.Replace('hostPort: 8443', "hostPort: $HttpsPort")
    $Config = $Config.Replace('http://kind-registry:5000', "http://${RegistryName}:5000")
    [IO.File]::WriteAllText($RenderedConfig, $Config, [System.Text.UTF8Encoding]::new($false))

    Write-Host "[*] Creating kind cluster '$Name' with HTTP hostPort=$HttpPort, HTTPS hostPort=$HttpsPort..."
    & kind create cluster --name $Name --config $RenderedConfig
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the kind cluster.' }
} finally {
    Remove-Item -LiteralPath $RenderedConfig -Force -ErrorAction SilentlyContinue
}

& kubectl label nodes -l durag.io/node-type node-role.kubernetes.io/worker='' --overwrite *> $null

Write-Host '[*] Connecting registry container to kind network...'
$KindNetwork = & docker inspect -f '{{json .NetworkSettings.Networks.kind}}' $RegistryName 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Failed to inspect the local registry container network.' }
if ($KindNetwork.Trim() -eq 'null') {
    & docker network connect kind $RegistryName
    if ($LASTEXITCODE -ne 0) { throw "Failed to connect '$RegistryName' to the kind network." }
    Write-Host "[+] Registry connected to 'kind' network"
} else {
    Write-Host "[+] Registry already connected to 'kind' network"
}

$RegistryConfig = @"
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-system
data:
  localRegistryHosting.v1: |
    host: "localhost:$RegistryPort"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
"@
$RegistryConfigPath = Join-Path ([IO.Path]::GetTempPath()) "local-registry-hosting-$([guid]::NewGuid().ToString('N')).yaml"
try {
    [IO.File]::WriteAllText($RegistryConfigPath, $RegistryConfig, [System.Text.UTF8Encoding]::new($false))
    & kubectl apply -f $RegistryConfigPath
    if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the local registry ConfigMap.' }
} finally {
    Remove-Item -LiteralPath $RegistryConfigPath -Force -ErrorAction SilentlyContinue
}

if ($WithIngress) {
    Write-Host '[*] Deploying ingress-nginx controller for kind...'
    & kubectl apply -f 'https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml'
    if ($LASTEXITCODE -ne 0) { throw 'Failed to deploy ingress-nginx.' }
    Write-Host '[*] Waiting for ingress-nginx controller pod to be ready (timeout 120s)...'
    & kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Ingress pod is still starting up in the background.' }
}

Write-Host ''
Write-Host '======================================================'
Write-Host '    Kind Cluster Bootstrap Completed Successfully!   '
Write-Host '======================================================'
& kubectl cluster-info --context "kind-$Name"
if ($LASTEXITCODE -ne 0) { throw 'Failed to retrieve cluster information.' }
Write-Host ''
Write-Host 'Nodes in cluster:'
& kubectl get nodes -o wide
if ($LASTEXITCODE -ne 0) { throw 'Failed to list cluster nodes.' }
Write-Host ''
Write-Host "Local container registry: localhost:$RegistryPort"
Write-Host 'To push images to the local registry for durag:'
Write-Host "  docker build -t localhost:$RegistryPort/durag:<tag> ."
Write-Host "  docker push localhost:$RegistryPort/durag:<tag>"
Write-Host ''
Write-Host 'Ingress host mappings:'
Write-Host "  HTTP:  http://localhost:$HttpPort"
Write-Host "  HTTPS: https://localhost:$HttpsPort"
Write-Host ''
Write-Host "Kubectl context set to: kind-$Name"
