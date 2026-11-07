# Starts the AI server on this PC (Phase 7).
#   powershell -ExecutionPolicy Bypass -File ai_server\run_server.ps1
# One worker, so the pose model and chatbot rules load once. Listens on localhost only;
# the phone reaches it through the Cloudflare tunnel (run_tunnel.ps1), never directly.
#   -DevTools: keep every /pose request (video, body points, step-by-step trace) in dev_runs\ for the
#   posture viewer (run_devtools.ps1). Development only: never with real patients' videos.
#   -Dev: accept the test token 'dev-token' (the app built with USE_FAKES=true). Never with a tunnel open.
param([switch]$DevTools, [switch]$Dev)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
if ($DevTools) { $env:DEV_TOOLS = "true"; Write-Host "DEV_TOOLS on: /pose requests are kept in dev_runs\" }
if (-not (Test-Path ".venv\Scripts\python.exe")) {
    Write-Error "No .venv here. Create it first: python -m venv .venv; .venv\Scripts\python -m pip install -r requirements.txt"
}
if ($Dev) { $env:DEV_AUTH_BYPASS = "true"; Write-Warning "-Dev: 'dev-token' is accepted. Do not open a tunnel." }
if (-not (Test-Path ".env")) {
    Write-Warning "No .env: no Supabase key is set, so real logins are refused. Use -Dev for the fakes build."
}
& ".venv\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1
