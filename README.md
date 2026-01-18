# FastAPI uv Baked Template (Internal)

Status: Internal tool (v1.0, frozen)

This repository contains a PowerShell-based initializer
for creating opinionated FastAPI projects using `uv`.

## What this tool does

- Wraps `uv` for Python + dependency management
- Creates a standardized FastAPI project structure
- Supports optional PostgreSQL setup
- Configures SQLAlchemy (async) + Alembic (sync)
- Optionally generates Dockerfile and .dockerignore
- Validates database connectivity during setup

## Technologies used

- Python >= 3.10
- FastAPI
- uv (Python + dependency manager)
- SQLAlchemy (async)
- asyncpg (runtime)
- Alembic (migrations)
- psycopg2-binary (sync migrations)
- uvicorn
- python-dotenv
- Docker (optional)

## How it works (high level)

- This tool is a thin wrapper around `uv`
- Python versions are managed by `uv`
- Virtual environments are isolated per project
- Database migrations are intentionally synchronous
- Environment variables are loaded from `.env`

## Usage

Run the script from PowerShell:

```powershell
.\init_fastapi.ps1
````
