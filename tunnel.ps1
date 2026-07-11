$ErrorActionPreference = "Stop"

Write-Host "Life Conference App LiveKit + Cloudflare Tunnels Startup"
Write-Host "================================================="

# 1. Download cloudflared if it doesn't exist
$cloudflaredPath = ".\cloudflared.exe"
if (-not (Test-Path $cloudflaredPath)) {
    Write-Host "Downloading cloudflared (Cloudflare Tunnels)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $cloudflaredPath
    Write-Host "Download complete." -ForegroundColor Green
}

# 2. Start LiveKit Server
Write-Host "Starting LiveKit Server on port 7880..." -ForegroundColor Green
$livekit = Start-Process -NoNewWindow -PassThru -FilePath "livekit-server" -ArgumentList "--dev"

# 3. Start FastAPI Token Server
Write-Host "Starting FastAPI Token Server on port 8000..." -ForegroundColor Green
$fastapi = Start-Process -NoNewWindow -PassThru -FilePath "python" -ArgumentList "-m uvicorn main:app --port 8000"

Start-Sleep -Seconds 2

# 4. Start Cloudflare Tunnels
Write-Host "Starting Cloudflare Tunnels..." -ForegroundColor Green
Write-Host "Wait a few seconds for the URLs to appear below..." -ForegroundColor Cyan

# We pipe stderr to stdout and grep for the trycloudflare.com URL
$cfApp = Start-Process -NoNewWindow -PassThru -FilePath $cloudflaredPath -ArgumentList "tunnel --url http://localhost:8000" -RedirectStandardError "cf_app.log"
$cfLiveKit = Start-Process -NoNewWindow -PassThru -FilePath $cloudflaredPath -ArgumentList "tunnel --url http://localhost:7880" -RedirectStandardError "cf_livekit.log"

Start-Sleep -Seconds 5

Write-Host "`n--- YOUR CLOUDFLARE URLS ---" -ForegroundColor Yellow

$appUrl = Select-String -Path cf_app.log -Pattern "https://.*\.trycloudflare\.com" | Select-Object -First 1
if ($appUrl) {
    Write-Host "APP URL: $($appUrl.Matches.Value)" -ForegroundColor Green
} else {
    Write-Host "APP URL: (Still generating, check cf_app.log)" -ForegroundColor Red
}

$rtcUrl = Select-String -Path cf_livekit.log -Pattern "https://.*\.trycloudflare\.com" | Select-Object -First 1
if ($rtcUrl) {
    Write-Host "RTC URL: $($rtcUrl.Matches.Value)" -ForegroundColor Green
} else {
    Write-Host "RTC URL: (Still generating, check cf_livekit.log)" -ForegroundColor Red
}

Write-Host "----------------------------`n" -ForegroundColor Yellow

try {
    while ($true) {
        if ($livekit.HasExited) { Write-Host "LiveKit crashed!" -ForegroundColor Red }
        if ($fastapi.HasExited) { Write-Host "FastAPI crashed!" -ForegroundColor Red }
        if ($cfApp.HasExited) { Write-Host "Cloudflare App tunnel crashed!" -ForegroundColor Red }
        if ($cfLiveKit.HasExited) { Write-Host "Cloudflare LiveKit tunnel crashed!" -ForegroundColor Red }
        Start-Sleep -Seconds 5
    }
}
finally {
    Write-Host "Cleaning up processes..." -ForegroundColor Yellow
    Stop-Process -Id $livekit.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $fastapi.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $cfApp.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $cfLiveKit.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Done." -ForegroundColor Green
}
