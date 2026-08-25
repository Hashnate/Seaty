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
- **Nothing may hold a DB session across an `await`.** A `Session` keeps its pooled connection
  from its first query until commit/rollback/close, so a socket that authenticates once and then
  waits in `receive_text()` used to pin a connection — and an open transaction — for as long as
  the user stayed signed in. That, not the hardware, was the ~15-concurrent-user ceiling. Outside
  a request use `with session_scope() as db:` (`database.py`) around the shortest span that does
  the work: authenticate in one scope, do each message's work in its own. `tracking.py` and
  `notifications.py` are the worked examples.
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
- **Deleting a trip, schedule or vehicle cascades to bookings and payments.** All three deletes
  now refuse with 409 when a paid booking is attached; nothing else guards it, so any new delete
  path must add the same check.
- **"Off sale" and "cancelled" are different states and both exist.** `booking_enabled` (on
  `trips`, `trip_schedules`, `vehicles`) is the reversible switch that hides a trip from
  passengers and refuses new sales while leaving existing bookings intact.
  `trips.status='cancelled'` is one-way: it voids bookings, notifies and texts passengers, and
  queues refunds. Don't collapse them.
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

**Scoping goes through `app/permissions.py`, not inline checks.** Role gating answers "may this
kind of user call this"; it never answers "does this row belong to them". `permissions.require_*`
(`require_vehicle`, `require_trip`, `require_operable_trip`, `require_schedule`,
`require_conductor`) load the row and enforce ownership in one call, raising a uniform 404 so an
endpoint cannot be used to probe for IDs in other companies. `same_company()` treats `None` as
matching nothing — never hand-roll `a.company_id != b.company_id`, because `None != None` is
`False` and an admin-created vehicle and a passenger both have a NULL `company_id`.

`MANAGER_ROLES = ("admin", "owner")` is who may manage fleet resources. **Conductors are
operational only**: their assigned trips' `/status` (not `cancelled`/`scheduled`), `/manifest`,
`/toggle-board`, and GPS. They create and suspend nothing. `require_operable_trip` is the one
helper that admits them, and only for trips where `trip.conductor_id` is themselves.

When adding an endpoint:

- Gate it with `auth.RoleChecker([...])` as a dependency, never with an inline role check, and
  never with `get_current_user` plus an `if role in [...]` block — that pattern is exactly how
  `update_trip` ended up open to passengers.
- Then scope it with a `permissions.require_*` helper. Role gating alone is how the trip manifest
  — passenger names, genders and phone numbers — was readable by any conductor on the platform.
- If it sells, holds, or charges for a seat, call `availability.assert_bookable(db, trip)`. That
  is the only place the on/off switches and `trip.status` are evaluated, and every sale path must
  go through it or the switch leaks.
- Deletes that cascade into `bookings`/`payments` must refuse when a paid booking exists.
  Relationships crossing those cascades need `passive_deletes=True`, or SQLAlchemy nulls the FK
  first and the NOT NULL constraint turns the delete into a 500.
- Never trust a client-supplied price, role, or total — recompute server-side.
- Check ownership, not just role, before mutating a booking or payment (`initiate_payment` is the
  cautionary example — its docstring claims it does; it doesn't).
- Don't call blocking I/O (`send_sms`, `send_fcm_push`, `messaging.send`) from an `async def` —
  one event loop serves every WebSocket in the process, so a 10-second SMS freezes all of them.
  Wrap it: `await run_in_threadpool(send_sms, …)` from `starlette.concurrency`. A plain `def`
  endpoint already runs in the threadpool and needs no wrapper — that is why `send_otp` calls
  `send_sms` directly and `_send_booking_notifications` may not.

## Conventions

- **Backend**: one router per domain in `routes/`, ORM in `models.py`, Pydantic in `schemas.py`.
  Money is `Numeric(10,2)`, IDs are UUIDs, timestamps are `DateTime(timezone=True)`.
- **Mobile**: Riverpod `NotifierProvider`, no code generation. Theme values come from
  `theme/app_colors.dart` and `theme/app_text_styles.dart` — don't hard-code colours.
- **Mobile session-scoped providers watch `sessionProvider`, never `authProvider`.** It exposes
  only `(isAuthenticated, role, token)`, so a provider reloads when the session changes and not
  when the user edits their name — watching the whole `AuthState` made a profile save tear down
  the notifications WebSocket and refetch everything. `ref.read(authProvider)` inside a method is
  fine; it does not subscribe.
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
