# FastAPI uv Baked Template
# Version: 1.0 (internal)
# Status: Frozen

$ErrorActionPreference = "Stop"

Write-Host "========================================="
Write-Host " FastAPI uv BAKED TEMPLATE (DB + Alembic)"
Write-Host "========================================="

# --------------------------------------------------
# uv bootstrap
# --------------------------------------------------
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Write-Host "uv not found. Installing..." -ForegroundColor Yellow
    irm https://astral.sh/uv/install.ps1 | iex
    $uvPath = "$env:USERPROFILE\.local\bin"
    if ($env:Path -notlike "*$uvPath*") {
        $env:Path = "$uvPath;$env:Path"
    }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host "Restart shell and re-run." -ForegroundColor Red
        exit 1
    }
}

# --------------------------------------------------
# Project path (SAFE)
# --------------------------------------------------
do {
    $baseDir = (Read-Host "Enter base directory (absolute path)").Trim()
    try {
        $resolvedBase = Resolve-Path $baseDir -ErrorAction Stop
        break
    } catch {
        $create = Read-Host "Directory not found. Create it? (Y/N)"
        if ($create -match '^[Yy]$') {
            New-Item -ItemType Directory -Path $baseDir | Out-Null
            $resolvedBase = Resolve-Path $baseDir
            break
        }
    }
} while ($true)

do {
    $projectName = Read-Host "Enter project name"
} while (-not $projectName)

$projectPath = Join-Path $resolvedBase $projectName
if (Test-Path $projectPath) {
    Write-Host "Project already exists." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $projectPath | Out-Null
Set-Location $projectPath


# --------------------------------------------------
# Python version selection
# --------------------------------------------------
$minPython = [Version]"3.10"

do {
    $pyVersionInput = (Read-Host "Enter Python version (>=3.10, default 3.11)").Trim()
    if (-not $pyVersionInput) {
        $pyVersionInput = "3.11"
    }

    try {
        $pyVersion = [Version]$pyVersionInput
    } catch {
        Write-Host "Invalid version format. Use e.g. 3.10, 3.11" -ForegroundColor Red
        continue
    }

    if ($pyVersion -lt $minPython) {
        Write-Host "Python version must be >= 3.10" -ForegroundColor Red
        continue
    }

    break
} while ($true)

Write-Host "Using Python $pyVersionInput" -ForegroundColor Green


# --------------------------------------------------
# uv init
# --------------------------------------------------
uv init --python $pyVersionInput
if (Test-Path "main.py") { Remove-Item "main.py" }

uv add fastapi uvicorn python-dotenv

# --------------------------------------------------
# Base structure
# --------------------------------------------------
$dirs = @(
    "app/api/v1",
    "app/schemas",
    "app/db/models",
    "app/services",
    "app/middleware"
)

foreach ($dir in $dirs) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    "" | Set-Content "$dir/__init__.py"
}

New-Item .env -ItemType File | Out-Null

# --------------------------------------------------
# DB toggle
# --------------------------------------------------
$dbEnabled = $false
$dbValidated = $false

if ((Read-Host "Enable PostgreSQL database? (Y/N)") -match '^[Yy]$') {
    $dbEnabled = $true
    uv add sqlalchemy asyncpg alembic psycopg2-binary
}

# --------------------------------------------------
# DB URI + validation
# --------------------------------------------------
if ($dbEnabled) {
    do {
        $pgUri = Read-Host "Enter PostgreSQL URI (postgresql+asyncpg://...)"
        if ($pgUri -and $pgUri.StartsWith("postgresql+asyncpg://")) {
            break
        }
        Write-Host "Invalid URI format." -ForegroundColor Red
    } while ($true)

    Add-Content .env "POSTGRES_DB_URI=$pgUri"

    $masked = $pgUri -replace "://.*?:.*?@", "://***:***@"
    Write-Host "DB URI set: $masked" -ForegroundColor Green
}

# --------------------------------------------------
# Validate database connection
# --------------------------------------------------
if ($dbEnabled) {
    Write-Host ""
    Write-Host "Validating database connection..." -ForegroundColor Cyan

@"
import asyncio, os, sys
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine


load_dotenv()
DB_URI = os.getenv("POSTGRES_DB_URI")

async def validate():
    try:
        engine = create_async_engine(DB_URI, pool_pre_ping=True)
        async with engine.connect():
            pass
        await engine.dispose()
        print("Database connection successful.")
    except Exception as e:
        print("Database connection failed:")
        print(e)
        sys.exit(1)

asyncio.run(validate())
"@ | Set-Content _db_validate.py

    uv run python _db_validate.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Aborting setup due to DB failure." -ForegroundColor Red
        exit 1
    }

    Remove-Item _db_validate.py
    $dbValidated = $true
}


# --------------------------------------------------
# logging_config.py
# --------------------------------------------------
@"
import logging.config

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "default": {
            "format": "[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s",
        },
    },
    "handlers": {
        "default": {
            "class": "logging.StreamHandler",
            "formatter": "default",
        },
    },
    "loggers": {
        "": {"handlers": ["default"], "level": "INFO"},
        "uvicorn.access": {"level": "WARNING"},
    },
}

def setup_logging():
    logging.config.dictConfig(LOGGING_CONFIG)
"@ | Set-Content app/logging_config.py

# --------------------------------------------------
# middleware
# --------------------------------------------------
@"
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("request")

class LogMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        logger.info("[%s] %s", request.method, request.url.path)
        return await call_next(request)
"@ | Set-Content app/middleware/log_middleware.py

# --------------------------------------------------
# schemas
# --------------------------------------------------
"# Request schemas" | Set-Content app/schemas/request.py
"# Response schemas" | Set-Content app/schemas/response.py

# --------------------------------------------------
# db base
# --------------------------------------------------
if ($dbEnabled) {
@"
from sqlalchemy.orm import DeclarativeBase

class Base(DeclarativeBase):
    pass
"@ | Set-Content app/db/base.py
}

# --------------------------------------------------
# postgres service
# --------------------------------------------------
if ($dbEnabled) {
@"
import os
import logging
from typing import AsyncGenerator
from dotenv import load_dotenv

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    AsyncEngine,
    async_sessionmaker,
    create_async_engine,
)


load_dotenv()

logger = logging.getLogger("postgres_db")

POSTGRES_DB_URI = os.getenv("POSTGRES_DB_URI")

_engine: AsyncEngine | None = None
SessionLocal: async_sessionmaker[AsyncSession] | None = None


def init_engine() -> AsyncEngine:
    global _engine, SessionLocal

    if not POSTGRES_DB_URI:
        raise RuntimeError("POSTGRES_DB_URI not set")

    if _engine is None:
        logger.info("Creating async PostgreSQL engine")
        _engine = create_async_engine(
            POSTGRES_DB_URI,
            pool_pre_ping=True,
        )
        SessionLocal = async_sessionmaker(
            _engine,
            expire_on_commit=False,
        )

    return _engine


async def close_engine() -> None:
    global _engine
    if _engine:
        logger.info("Disposing PostgreSQL engine")
        await _engine.dispose()
        _engine = None


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    if SessionLocal is None:
        raise RuntimeError("Database not initialized")
    async with SessionLocal() as session:
        yield session
"@ | Set-Content app/services/postgres_db.py
}

# --------------------------------------------------
# api router
# --------------------------------------------------
@"
from fastapi import APIRouter

router = APIRouter(prefix="/v1")

@router.get("/health")
async def health():
    return {"status": "ok"}
"@ | Set-Content app/api/v1/router.py

# --------------------------------------------------
# main.py
# --------------------------------------------------
if ($dbEnabled) {
@"
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.logging_config import setup_logging
from app.middleware.log_middleware import LogMiddleware
from app.api.v1.router import router
from app.services.postgres_db import init_engine, close_engine

setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_engine()
    yield
    await close_engine()

app = FastAPI(title="$projectName", version="1.0", lifespan=lifespan)

#Middleares
app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_headers=["*"],
        allow_methods=["*"]
)

app.add_middleware(LogMiddleware)

#Routes
app.include_router(router)
"@ | Set-Content app/main.py
}
else {
@"
from fastapi import FastAPI
from contextlib import asynccontextmanager
from app.middleware.log_middleware import LogMiddleware
from fastapi.middleware.cors import CORSMiddleware
from app.logging_config import setup_logging
from app.api.v1.router import router



setup_logging()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # functions to be called on app startup (Creating Engine, Connecting Services/Socket/Pool, Instance Creation )
    yield
    # functions to be called on app shutdown (Disposing Engine, Disconnecting Services/Socket/Pool, Instance Deletion)

app = FastAPI(title="$projectName", version="1.0", lifespan=lifespan)

#Middleware
app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_headers=["*"],
        allow_methods=["*"]
    )

app.add_middleware(LogMiddleware)

#Routes
app.include_router(router)
"@ | Set-Content app/main.py
}

# --------------------------------------------------
# Alembic setup
# --------------------------------------------------
if ($dbEnabled -and $dbValidated) {
    uv run alembic init alembic

@"
import os
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Import metadata
from app.db.base import Base
target_metadata = Base.metadata

# Read ASYNC DB URL
ASYNC_DATABASE_URL = os.getenv("POSTGRES_DB_URI")
if not ASYNC_DATABASE_URL:
    raise RuntimeError("POSTGRES_DB_URI not set")

# Convert async URL → sync URL for Alembic
SYNC_DATABASE_URL = ASYNC_DATABASE_URL.replace(
    "postgresql+asyncpg://", "postgresql://"
)

config.set_main_option("sqlalchemy.url", SYNC_DATABASE_URL)


def run_migrations_offline():
    context.configure(
        url=SYNC_DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
"@ | Set-Content alembic/env.py
}

# --------------------------------------------------
# README
# --------------------------------------------------
@"
# $projectName
uv run uvicorn app.main:app --reload
"@ | Set-Content README.md

# --------------------------------------------------
# Initialize INIT_README.md
# --------------------------------------------------
@"
---
Status: `Internal tool (v1.0)`
Scope: `Personal / internal projects only`
Stability: `Feature-frozen; bug fixes only`
---

This project was generated using the FastAPI uv baked template.


## Python
- Version: $pyVersionInput
- Managed by uv (.venv)

"@ | Set-Content INIT_README.md


# --------------------------------------------------
# Adding Database Configuration to INIT_README.md
# --------------------------------------------------
if ($dbEnabled) {
@"
## Database
- Async runtime: asyncpg
- Migrations: Alembic + psycopg2-binary
- DB validated during initialization
"@ | Add-Content INIT_README.md
} else {
@"
## Database
No database configured.
"@ | Add-Content INIT_README.md
}



# --------------------------------------------------
# gitignore
# --------------------------------------------------
@"
.env
.venv
**/__pycache__/
.idea/
alembic/versions/*.pyc
"@ | Set-Content .gitignore

# --------------------------------------------------
# Dockerfile option
# --------------------------------------------------
$useDocker = Read-Host "Generate Dockerfile? (Y/N)"

if ($useDocker -match '^[Yy]$') {

@"
# syntax=docker/dockerfile:1
ARG PYTHON_VERSION=$pyVersionInput
FROM python:\${PYTHON_VERSION}-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock* ./
RUN uv sync --frozen --no-dev

COPY . .

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
"@ | Set-Content Dockerfile
}

# --------------------------------------------------
# Adding .dockerignore
# --------------------------------------------------

if ($useDocker -match '^[Yy]$') {

@"
# Python
__pycache__/
*.pyc
*.pyo
*.pyd

# Virtual environments
.venv/
.env

# Git
.git/
.gitignore

# Docker
Dockerfile
.dockerignore

# Alembic
alembic/versions/*.pyc

# OS / Editor
.DS_Store
Thumbs.db
.vscode/
.idea/
"@ | Set-Content .dockerignore
}


# --------------------------------------------------
# Adding DockerFile Configuration to INIT_README.md
# --------------------------------------------------
if ($useDocker -match '^[Yy]$') {
@"
## Docker

A Dockerfile has been generated for this project.

Build image:
docker build --build-arg PYTHON_VERSION=$pyVersionInput -t fastapi-app .

Run container:
docker run -p 8000:8000 fastapi-app

The container uses:
- Python $pyVersionInput
- uv for dependency management
- uvicorn as the ASGI server

"@ | Add-Content INIT_README.md
}


Write-Host "Project ready."
Write-Host "Run uv run uvicorn app.main:app --reload"
