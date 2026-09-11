# ==============================================================================
# Script: push-docker-ghcr.ps1
# Push local Docker image to GitHub Container Registry (ghcr.io)
# ==============================================================================

param (
    [string]$GitHubUsername = "prasath-10",
    [string]$ImageTag = "latest"
)

Write-Host "=== Push to GitHub Container Registry (GHCR) ===" -ForegroundColor Cyan
Write-Host "Target: ghcr.io/$GitHubUsername/migrant-clinic-backend:$ImageTag" -ForegroundColor Yellow

Write-Host "`nStep 1: Tagging local Docker image..." -ForegroundColor Green
docker tag migrant-clinic-backend:latest "ghcr.io/$GitHubUsername/migrant-clinic-backend:$ImageTag"

Write-Host "`nStep 2: Authenticate with GitHub Packages" -ForegroundColor Green
Write-Host "Note: You need a GitHub Personal Access Token (classic) with 'write:packages' scope." -ForegroundColor Gray
Write-Host "Generate token at: https://github.com/settings/tokens/new?scopes=write:packages,read:packages,delete:packages" -ForegroundColor Cyan

$token = Read-Host "Enter your GitHub Personal Access Token (or press Ctrl+C to cancel)" -AsSecureString
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token)
$plainToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

$plainToken | docker login ghcr.io -u $GitHubUsername --password-stdin

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nStep 3: Pushing Docker image to GitHub..." -ForegroundColor Green
    docker push "ghcr.io/$GitHubUsername/migrant-clinic-backend:$ImageTag"
    Write-Host "`n[SUCCESS] Image successfully published to GitHub Container Registry!" -ForegroundColor Green
    Write-Host "View your package at: https://github.com/$GitHubUsername?tab=packages" -ForegroundColor Cyan
} else {
    Write-Host "`n[ERROR] Docker login failed. Please verify your GitHub PAT token has 'write:packages' scope." -ForegroundColor Red
}
