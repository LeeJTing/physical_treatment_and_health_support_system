# Opens a Cloudflare tunnel to the AI server so a phone on mobile data can reach it (Phase 7).
#   powershell -ExecutionPolicy Bypass -File ai_server\run_tunnel.ps1
#
# Without arguments: a QUICK tunnel. Prints a random https://<words>.trycloudflare.com address
# that changes every time; build the app with --dart-define=AI_BASE_URL=<that address>.
# With -Name <tunnel>: a NAMED tunnel with a fixed address on your own domain (set up once with
#   cloudflared tunnel login; cloudflared tunnel create apths; cloudflared tunnel route dns apths api.<domain>).
param([string]$Name = "")
$ErrorActionPreference = "Stop"
$cf = (Get-Command cloudflared -ErrorAction SilentlyContinue).Source
if (-not $cf) { $cf = "C:\Program Files (x86)\cloudflared\cloudflared.exe" }
if (-not (Test-Path $cf)) { Write-Error "cloudflared not found. Install it: winget install --id Cloudflare.cloudflared -e --source winget" }
try { Invoke-RestMethod http://127.0.0.1:8000/health -TimeoutSec 3 | Out-Null }
catch { Write-Warning "The AI server is not answering on port 8000. Start run_server.ps1 first." }
if ($Name) {
    & $cf tunnel --url http://127.0.0.1:8000 run $Name
} else {
    Write-Host "Look for the https://....trycloudflare.com line below; that is the address for the app." -ForegroundColor Green
    & $cf tunnel --url http://127.0.0.1:8000
}
