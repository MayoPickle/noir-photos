import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import get_settings
from app.db.session import engine
from app.models import Base
from app.routers import account, auth, collections, files, search_index, sharing, sync
from app.storage import storage

logging.basicConfig(level=logging.INFO)

settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    if settings.auto_create_tables:
        Base.metadata.create_all(bind=engine)
    storage.ensure_bucket()
    yield


app = FastAPI(
    title="Noir Photos API",
    version="0.1.0",
    description="Metadata and object broker for an end-to-end encrypted photo library.",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(account.router)
app.include_router(collections.router)
app.include_router(files.router)
app.include_router(search_index.router)
app.include_router(sharing.router)
app.include_router(sync.router)
