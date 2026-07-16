from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import settings
from .database import Base, engine
from .routers import auth, faces, sessions, ws

Base.metadata.create_all(bind=engine)

app = FastAPI(title="TogetherSnap API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/media", StaticFiles(directory=settings.storage_dir), name="media")

app.include_router(auth.router)
app.include_router(sessions.router)
app.include_router(faces.router)
app.include_router(ws.router)


@app.get("/health")
def health():
    return {"status": "ok"}
