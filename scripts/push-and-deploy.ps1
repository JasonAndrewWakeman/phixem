#Requires -Version 5.1
<#
.SYNOPSIS
  Push main to GitHub, wait until the Deploy workflow publishes the image, then update ACA.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\push-and-deploy.ps1
#>
[CmdletBinding()]
param(
  [Alias("WaitSeconds")]
  [int]$TimeoutSeconds = 900,
  [int]$PollSeconds = 20,
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

$remote = (git remote get-url origin).Trim()
if ($remote -notmatch "github.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)") {
  throw "Could not parse GitHub owner/repo from origin: $remote"
}
$owner = $Matches.owner
$repo = $Matches.repo
$runsUrl = "https://api.github.com/repos/$owner/$repo/actions/workflows/deploy.yml/runs?head_sha=$sha&per_page=5"

Write-Host "Waiting for GitHub Actions Deploy to finish for $sha ..."
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$conclusion = $null
$htmlUrl = $null

while ([DateTime]::UtcNow -lt $deadline) {
  $json = curl.exe -sS -H "Accept: application/vnd.github+json" $runsUrl
  $payload = $json | ConvertFrom-Json
  $run = @($payload.workflow_runs) | Select-Object -First 1

  if ($run) {
    $htmlUrl = $run.html_url
    Write-Host ("  {0} status={1} conclusion={2}" -f (Get-Date -Format HH:mm:ss), $run.status, $run.conclusion)
    if ($run.status -eq "completed") {
      $conclusion = $run.conclusion
      break
    }
  } else {
    Write-Host ("  {0} waiting for workflow run to appear..." -f (Get-Date -Format HH:mm:ss))
  }

  Start-Sleep -Seconds $PollSeconds
}

if (-not $conclusion) {
  throw "Timed out waiting for Deploy workflow. Check $htmlUrl"
}

if ($conclusion -ne "success") {
  throw "Deploy workflow $conclusion. Image was not published. See $htmlUrl"
}

Write-Host "Updating Azure Container App $ContainerApp with $image ..."
az containerapp update `
  --name $ContainerApp `
  --resource-group $ResourceGroup `
  --image $image

Write-Host "Revision status:"
az containerapp revision list --name $ContainerApp --resource-group $ResourceGroup -o table

$fqdn = az containerapp show --name $ContainerApp --resource-group $ResourceGroup --query "properties.configuration.ingress.fqdn" -o tsv
Write-Host "App: https://$fqdn/"
Write-Host "Done."
