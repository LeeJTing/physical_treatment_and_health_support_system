"""AI Server for APTHS (Table 4.2.4). Stateless: it never reads or writes
Supabase. Every result goes back to the app, which stores it.

Run (dev):  uvicorn app.main:app --reload --port 8000
Run (PC):   uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1
"""
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .config import get_settings
from .routers import chat, health, pose, recommend

app = FastAPI(title="APTHS AI Server", version=get_settings().api_version)

app.include_router(health.router)
app.include_router(recommend.router)
app.include_router(chat.router)
app.include_router(pose.router)


# Error contract read by ApiClient: {"error": {"code": ..., "message": ...}}
@app.exception_handler(HTTPException)
async def http_error(_: Request, exc: HTTPException):
    code = {401: "unauthorised", 404: "not_found", 422: "invalid_request"}.get(exc.status_code, "error")
    return JSONResponse(status_code=exc.status_code, content={"error": {"code": code, "message": str(exc.detail)}})


@app.exception_handler(RequestValidationError)
async def validation_error(_: Request, exc: RequestValidationError):
    return JSONResponse(status_code=422, content={"error": {"code": "invalid_request", "message": str(exc.errors()[:3])}})
