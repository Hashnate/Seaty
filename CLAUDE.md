# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Seaty — a bus seat-booking and live-tracking platform for Sri Lanka. Four parts in one repo:
a FastAPI backend (`backend/`), a Flutter app for passengers/owners/conductors (`mobile/`), a
React admin dashboard (`admin/`), and a Postgres image that ships the schema (`database/`).

Deeper background lives in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); endpoints in
[docs/API.md](docs/API.md); tables, state machines and schema drift in
[docs/DATA_MODEL.md](docs/DATA_MODEL.md); known non-security defects in
[docs/CODE_QUALITY.md](docs/CODE_QUALITY.md).

## Commands

```bash
# Full stack (needs backend/.env — copy from backend/.env.example)
docker compose up --build            # admin+API on :8025, docs at /docs
docker compose logs -f backend
docker compose down -v               # DESTROYS the database volume

# Backend alone (needs a Postgres and DATABASE_URL/SECRET_KEY exported)
cd backend && uvicorn app.main:app --reload --port 8000

# Admin
cd admin && npm run dev              # needs a Vite proxy, see docs/DEVELOPMENT.md
cd admin && npm run build            # tsc -b && vite build
cd admin && npm run lint             # oxlint

# Mobile
cd mobile && flutter run
cd mobile && flutter analyze
```

There is no test suite. `mobile/test/widget_test.dart` is the generated placeholder. Don't claim
a change is verified by tests — verify by reading the affected paths, or by running the stack.

## Things that will surprise you

- **`GET /trips?date=` writes to the database.** It materialises `trips` rows from
  `trip_schedules` for any date in the next 5 days. A "read" endpoint doing inserts is
  intentional here; don't "fix" it without handling schedule materialisation elsewhere.
- **Three sources of DDL disagree.** `schema.sql` (fresh volumes only), `Base.metadata.create_all`
  (tables only, never columns, runs at import in `main.py:10`), and `migrate_db.py` (ad-hoc
  ALTERs at every boot). Adding a column to `models.py` is not enough — add it to
  `migrate_db.py` **and** `schema.sql`. `users.fcm_token` is currently missing from both and
  breaks fresh deploys.
- **The backend must run single-process.** All three WebSocket managers and the OTP store are
  module-level dicts. Never suggest `--workers > 1` or replicas without a shared broker.
- **Each authenticated WebSocket pins a DB connection for its whole lifetime**
  (`tracking.py`, `notifications.py` both hold a `SessionLocal()`), and the engine uses
  SQLAlchemy's defaults — 15 connections total. That caps the platform at ~15 concurrent
  signed-in users. Don't add another long-lived-session socket without fixing this.
- **`ENVIRONMENT=development` makes every OTP `123456`** and echoes it in the send response. It is
  the default in `config.py`. Verification itself is never skipped, in any environment.
- **`TEST_OTP_ACCOUNTS` holds fixed-OTP accounts for App Store / Play review** (`phone:code,…`,
  in `backend/.env`). Reviewers cannot receive SMS, so these must keep working and must match the
  Sign-In Information submitted to the stores. Passenger accounts only; never hard-code them.
- **`migrate_db.py` step 4 renumbers every vehicle's seat labels on every boot**, unguarded.
  Seat labels are the join key for bookings, holds, and boarding, so changing the order of
  `seat_layout.seats` silently reassigns seats under existing bookings.
- **`UPLOAD_DIR` means two different things** — the served directory in `main.py:28`, the write
  directory in `routes/uploads.py:13`, with defaults one level apart. Leave it unset.
- **Deleting a trip or a schedule cascades to bookings and payments.** No endpoint warns or
  checks for paid bookings first.
- **Cross-router imports happen inside functions** to avoid circular imports (e.g.
  `from app.routes.notifications import create_and_send_notification`). Keep that pattern.
- **`mobile/lib/main.dart` re-exports everything** for legacy `import 'main.dart'` call sites.
  New code should import the specific provider/screen file.
- **`admin/src/api/client.ts` uses the relative base `/api/v1`**, so the SPA only works same-origin
  behind its own Nginx.

## Security posture

[docs/SECURITY.md](docs/SECURITY.md) documents 33 known gaps, several of them critical (secrets
baked into the Docker image, an ungated `PUT /trips/{id}`, unauthenticated payment completion,
phone login without OTP, open admin registration). They are **known and recorded, not
undiscovered** — don't re-report them as new findings on every task, and don't treat the
surrounding code as a template for new endpoints.

**Login is split by role and the split is load-bearing.** `POST /auth/login` (password, admin
console) accepts only `auth.PASSWORD_LOGIN_ROLES = ("admin", "owner")`; passengers and conductors
are phone + OTP only. Don't widen it without reading SECURITY.md #22 first — a disallowed role
must keep returning the same 401 as a wrong password, or the endpoint becomes an
account-enumeration oracle.

**Account creation is one-directional and no API path may create an admin.**
`create_admin.py` (out of band) → admin → owner (`POST /auth/register`, admin-only,
`Literal["owner"]`) → conductor (`POST /conductors`, owner-only). Passengers self-register by
phone + OTP, `Literal["passenger"]`. Every role field is a `Literal`, not a `str` — keep it that
way; a plain string here is what made SECURITY.md #2 an unauthenticated admin factory.

When adding an endpoint:

- Gate it with `auth.RoleChecker([...])` as a dependency, never with an inline role check, and
  never with `get_current_user` plus an `if role in [...]` block — that pattern is exactly how
  `update_trip` ended up open to passengers.
- Role gating is not enough — also scope by `company_id` for owner/conductor routes. Several
  existing endpoints forget this; `update_trip_status` in `routes/trips.py:331` shows the pattern.
- Compare `company_id` in a way that treats `None` as never matching (`None != None` is `False`,
  which currently grants access in a few places).
- Never trust a client-supplied price, role, or total — recompute server-side.
- Check ownership, not just role, before mutating a booking or payment (`initiate_payment` is the
  cautionary example — its docstring claims it does; it doesn't).
- Don't call blocking I/O (`send_sms`, `messaging.send`) from an `async def` — one event loop
  serves every WebSocket in the process.

## Conventions

- **Backend**: one router per domain in `routes/`, ORM in `models.py`, Pydantic in `schemas.py`.
  Money is `Numeric(10,2)`, IDs are UUIDs, timestamps are `DateTime(timezone=True)`.
- **Mobile**: Riverpod `NotifierProvider`, no code generation. Theme values come from
  `theme/app_colors.dart` and `theme/app_text_styles.dart` — don't hard-code colours.
- **Admin**: function components, inline styles referencing CSS variables, no UI library, no
  state library beyond context.
- **Commits**: Conventional Commits, optionally scoped — `feat(mobile):`, `fix(ios):`,
  `refactor:`.

## Don't touch

- `mobile/AuthKey_*.p8`, `dist_certificate*.p12`, `private.key`, `*.pem`, `*.cer` — untracked
  local signing material. Don't commit, move, or delete them.
- `mobile/Seaty_App_Store_Profile.mobileprovision` — committed deliberately; the iOS CI job reads
  it from the checkout.
- `backend/firebase-service-account.json` — gitignored, mounted read-only into the container.
- `.github/workflows/mobile-release.yml` `BUILD_NUMBER_OFFSET` — changing it collides with build
  numbers App Store Connect has already accepted.
