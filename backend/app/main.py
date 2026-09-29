import logging

from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .ratelimit import RateLimit
from .routers import account, auth, care, content, dashboard, sathi, sync

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


def create_app() -> FastAPI:
    s = get_settings()
    app = FastAPI(
        title="NEURO-SATHI API",
        version="0.1.0",
        description="Cognitive care, memory assistance and caregiver monitoring for elderly users in North-East India.",
        docs_url=None if s.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if s.is_production else "/openapi.json",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=s.cors_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type"],
    )
    for r in (auth.router, account.router, sync.router, care.router, care.files_router, dashboard.router,
              content.router, content.admin, sathi.router):
        app.include_router(r)

    @app.get("/health", dependencies=[Depends(RateLimit("default"))], tags=["ops"])
    def health() -> dict:
        return {"status": "ok"}

    @app.middleware("http")
    async def security_headers(request, call_next):  # noqa: ANN001, ANN202
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Cache-Control", "no-store")
        if s.is_production:
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        return response

    return app


app = create_app()
