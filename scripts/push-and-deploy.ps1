#Requires -Version 5.1
<#
.SYNOPSIS
  Push main to GitHub, wait for GHCR image build, then update Azure Container Apps.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\push-and-deploy.ps1
#>
[CmdletBinding()]
param(
  [int]$WaitSeconds = 180,
  [string]$ResourceGroup = "phixem-rg",
  [string]$ContainerApp = "phixem",
  [string]$ImageRepository = "ghcr.io/jasonandrewwakeman/phixem"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$env:Path = @(
  "C:\Program Files\Git\cmd"
  "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
  $env:Path
) -join ";"

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $name"
  }
}

Assert-Command git
Assert-Command az

$branch = (git branch --show-current).Trim()
if ($branch -ne "main") {
  throw "This script deploys from main (GitHub Actions only builds main). Current branch: $branch"
}

$status = git status --porcelain
if ($status) {
  Write-Host "Uncommitted changes are present. Only commits already on main will be pushed:"
  git status -sb
  Write-Host ""
}

Write-Host "Pushing origin main..."
git push origin main
$sha = (git rev-parse HEAD).Trim()
$image = "${ImageRepository}:${sha}"

Write-Host "Waiting $WaitSeconds seconds for GitHub Actions to build $image ..."
Start-Sleep -Seconds $WaitSeconds

Write-Host "Updating Azure Container App $ContainerApp ..."
az containerapp update `
  --name $ContainerApp `
  --resource-group $ResourceGroup `
  --image $image

Write-Host "Revision status:"
az containerapp revision list --name $ContainerApp --resource-group $ResourceGroup -o table

$fqdn = az containerapp show --name $ContainerApp --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv
Write-Host "App: https://$fqdn/"
Write-Host "Done."
