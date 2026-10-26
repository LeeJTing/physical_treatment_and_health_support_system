# Starts the posture check viewer (development only): http://127.0.0.1:8001
#   powershell -ExecutionPolicy Bypass -File ai_server\run_devtools.ps1
# This PC only; the Cloudflare tunnel points at the AI server (port 8000), never at this.
# Runs from the phone appear when the AI server was started with: run_server.ps1 -DevTools
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
& ".venv\Scripts\python.exe" -m uvicorn devtools.viewer:app --host 127.0.0.1 --port 8001 --workers 1
