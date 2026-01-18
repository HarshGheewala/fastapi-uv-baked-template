# FUTURE.md

This document lists potential future enhancements for the
FastAPI uv Baked Template.

These items are **not planned**, **not guaranteed**, and **not in scope**
for the current frozen internal version (v1.0).

They exist only as a reference for future iterations.

---

## Platform & OS Support

- Support for non-Windows environments
  - Bash / Zsh script for Linux & macOS
  - Cross-platform Python-based CLI
- OS-specific dependency checks and fallbacks

---

## Database Enhancements

- Support for additional databases:
  - MySQL / MariaDB
  - SQLite (lightweight / testing)
  - MongoDB (async drivers)
  - Redis (cache / pub-sub)
- Configurable database selection during initialization
- Optional database abstraction layer per backend
- Optional database health checks at startup

---

## Authentication & Security

- Optional authentication middleware scaffolding:
  - JWT-based auth
  - API key auth
- Predefined auth router structure (`/auth`)
- Optional user model scaffolding
- Password hashing utilities (bcrypt / argon2)

---

## Infrastructure & Tooling

- Non-interactive mode (flags / arguments)
- Configurable environment profiles (dev / test / prod)
- Optional initial Alembic migration generation
- Docker Compose support (PostgreSQL, Redis)
- CI-friendly mode (no prompts)

---

## Project Structure Extensions

- Optional background worker setup
- Optional task queue integration
- Optional file storage service abstraction
- Optional third-party SDK scaffolding

---

## Documentation & UX

- Improved onboarding messages
- More descriptive INIT_README.md sections
- Optional verbose / quiet modes
- Clearer failure diagnostics

---

## Release Considerations

- Conversion to a Python CLI tool
- Public release considerations
- Versioned templates
- Backward compatibility strategy

---

Status: Idea backlog only  
Current Version: v1.0 (internal, frozen)
