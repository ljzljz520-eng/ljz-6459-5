"""离子氮化批次管理 API。"""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from .api import batches, lab, telemetry
from .deps import build_container
from .services.batch_service import DomainError


def create_app(db_path: str | None = None) -> FastAPI:
    app = FastAPI(title="Ion Nitriding Batch API", version="1.0.0")
    app.state.c = build_container(db_path)
    app.include_router(batches.router, prefix="/api/v1")
    app.include_router(telemetry.router, prefix="/api/v1")
    app.include_router(lab.router, prefix="/api/v1")

    @app.exception_handler(DomainError)
    async def domain_error(_: Request, exc: DomainError) -> JSONResponse:
        status = 404 if exc.code.endswith("NOT_FOUND") else 409
        return JSONResponse(
            status_code=status, content={"code": exc.code, "detail": exc.message}
        )

    @app.get("/api/v1/health")
    def health() -> dict:
        return {"ok": True}

    return app


app = create_app()
