# Architecture

## System shape

```
┌──────────────┐   HTTPS / WSS    ┌─────────────────────────────┐
│ Flutter app  │─────────────────▶│ Nginx (admin container)     │
│ passenger /  │                  │  :80  →  static React SPA   │
│ owner /      │                  │  /api/v1/ → backend:8000    │
│ conductor    │                  └──────────────┬──────────────┘
└──────────────┘                                 │
                                                 ▼
┌──────────────┐                  ┌─────────────────────────────┐
│ React admin  │─── same origin ─▶│ FastAPI backend (:8000)     │
│ dashboard    │      /api/v1     │  REST + 3 WebSocket routes  │
└──────────────┘                  └──────────────┬──────────────┘
                                                 │
                        ┌────────────────────────┼────────────────────────┐
                        ▼                        ▼                        ▼
                 ┌─────────────┐        ┌────────────────┐       ┌────────────────┐
                 │ PostgreSQL  │        │ Firebase FCM   │       │ Notify.lk SMS  │
                 │ (seaty)     │        │ (push)         │       │ (OTP + confirm)│
                 └─────────────┘        └────────────────┘       └────────────────┘
```

Only the `admin` container publishes a host port (`8025:80`). The backend, database, and the
static marketing site (`website/`) are reachable only on the Compose network, so **Nginx is the
single ingress** for the SPA, the API, and the marketing site alike. `admin/nginx.conf` defines
three server blocks: one matching `api.seaty.hashnate.com` that proxies everything to the
backend, one matching `seaty.hashnate.com`/`www.seaty.hashnate.com` that proxies to the
`website` container, and a default one that serves the admin SPA and proxies `/api/v1/`. The
API and default blocks set `Upgrade`/`Connection` headers so WebSockets pass through; the
marketing site has none (it's static, no WebSocket routes). See
[WEBSITE.md](WEBSITE.md) for the marketing site itself.

## Backend

FastAPI app in [`backend/app/main.py`](../backend/app/main.py). Every router mounts under
`/api/v1`. Layout:

```
backend/app/
├── main.py        # app assembly, CORS, static uploads, background scheduler
├── config.py      # pydantic-settings, reads .env / environment
├── database.py    # engine, SessionLocal, get_db dependency
├── auth.py        # bcrypt hashing, JWT issue/verify, RoleChecker dependency
├── models.py      # SQLAlchemy ORM models (the source of truth for tables)
├── schemas.py     # Pydantic request/response models
├── routes/        # one router per domain (17 files)
└── services/
    └── sms_service.py   # Notify.lk HTTP gateway
```

### Authentication

`auth.py` provides three dependencies used throughout the routers:

- `get_current_user` — requires a valid bearer token, 401 otherwise.
- `get_optional_current_user` — returns `None` instead of raising; used by `GET /trips` so
  anonymous browsing works while logged-in owners/conductors get a filtered list.
- `RoleChecker([...])` — wraps `get_current_user` and 403s if `user.role` is not in the list.

Tokens are HS256 JWTs with `sub` (email) and `role` claims, expiring after
`ACCESS_TOKEN_EXPIRE_MINUTES` (10080 = 7 days). **The `role` claim is decorative** — every
authorisation check re-reads `role` from the database row, so a stale token cannot escalate.

There are two parallel login paths:

| Path                     | Used by       | Credential                                          |
| ------------------------ | ------------- | --------------------------------------------------- |
| `POST /auth/login`       | Admin SPA     | email + password (OAuth2 password form)             |
| `POST /auth/phone/login` | Mobile app    | phone number + role + **OTP code, verified and consumed server-side** |

Phone-only users get a synthetic email `{phone}@seaty.lk` and a password hash of a random secret
that is generated and immediately discarded (`auth.unusable_password_hash()`).

The two paths are separated by role, enforced in the backend:

| Role | `POST /auth/login` (console) | `POST /auth/phone/login` (app) |
| ---- | :--------------------------: | :----------------------------: |
| `admin` | ✅ | — |
| `owner` | ✅ | ✅ |
| `conductor` | ❌ 401 | ✅ |
| `passenger` | ❌ 401 | ✅ |

`auth.PASSWORD_LOGIN_ROLES` drives the left column, and a disallowed role returns the same 401 as
a wrong password so the endpoint cannot be used to enumerate accounts or roles. The admin SPA's
`RoleProtectedRoute` guards mirror this, but they are UI only — the check that matters is the one
in `routes/auth.py`.

### Who can create whom

Account creation is one-directional, and enforced server-side at every step:

```
   create_admin.py  ──▶  admin  ──▶  owner  ──▶  conductor
   (out of band,                    (POST        (POST
    no API path)                  /auth/register) /conductors)

                        passenger  ◀── self-service, phone + OTP
                                       (POST /auth/phone/register)
```

| Role | Created by | Enforced how |
| ---- | ---------- | ------------ |
| `admin` | nobody, via the API | there is no endpoint; `backend/create_admin.py` only |
| `owner` | an admin | `RoleChecker(["admin"])` + `role: Literal["owner"]` |
| `conductor` | their owner | `RoleChecker(["owner"])`, role hardcoded, inherits the owner's `company_id` |
| `passenger` | anyone | `role: Literal["passenger"]` + a verified OTP |

Two consequences worth remembering: the app's staff entrance is **sign-in only** (an unrecognised
number is told to contact its operator), and **losing the last admin account means losing console
access** — `create_admin.py` is the only way back in.

> [!NOTE]
> Until commit `3b43d6a` both creation paths hashed the string literal
> `seaty_phone_auth_dummy_pass`, and `/auth/login` had no role check — so knowing a phone number
> was enough to sign in as that user. An earlier version of this document claimed the opposite.
> See [SECURITY.md](SECURITY.md) #22 for the full history; 18 legacy hashes still need rotating.

### Background work

`main.py` starts **two** asyncio tasks on startup:

| Task | Interval | What it does |
| ---- | -------- | ------------ |
| `trip_reminder_scheduler` | 30 s | Finds confirmed bookings whose trip departs within 30 minutes and sends a reminder, de-duplicating by `LIKE '%Booking ID: {id}%'` against the notifications table |
| `auto_expire_bookings_scheduler` | 60 s | Marks confirmed bookings on departed trips `completed` (all seats scanned) or `expired` (otherwise) |

The second one duplicates logic that `GET /bookings` also performs inline via
`_auto_update_booking_statuses` — two implementations of the same transition, with different
rules. See [CODE_QUALITY.md](CODE_QUALITY.md) C5.

There is **no scheduled seat-hold cleanup**, despite the docstring on
`POST /seat-holds/cleanup` claiming it runs "on app startup and periodically". That endpoint is
admin-triggered only. In practice expired holds still stop blocking seats because every
availability read filters on `expires_at > now`; what leaks is bookings stuck in
`awaiting_payment` forever.

## Data model

Seventeen tables. UUID primary keys throughout, `NUMERIC(10,2)` for money, `TIMESTAMPTZ` for time.
Field-level reference, state machines, JSONB shapes, and the full DDL-drift matrix are in
[DATA_MODEL.md](DATA_MODEL.md); what follows is the shape and the rationale.

```
bus_companies ─┬─< users ─┬─< bookings >─── payments
               │          ├─< seat_holds
               │          ├─< notifications
               │          ├─< reviews
               │          └─< user_favourites
               └─< vehicles ─┬─< trips >─── routes
                             ├─── vehicle_locations (1:1)
                             └─< trip_schedules ─┬─< trips
                                                 └─< bus_overrides
```

Key relationships and quirks:

- **`users.company_id`** scopes owners and conductors. Nearly all operator-side authorisation is
  "does this vehicle's `company_id` match mine?" — not "am I the owner?" So any owner in a
  company can act on any vehicle in that company.
- **`trip_schedules`** are recurring templates (`daily` / `weekdays` / `weekends` / `custom`
  weekday array, with `effective_from`/`effective_until`). Concrete `trips` rows are
  **materialised lazily** — `GET /trips?date=` generates missing trips for any date within the
  next 5 days on read. This means a plain `GET` performs writes.
- **`bus_overrides`** swap in a replacement vehicle for a schedule on one specific date; the
  generator honours them.
- **`seat_holds`** are soft locks (`expires_at` + `is_released`). Availability = confirmed paid
  bookings ∪ active unexpired holds. Booked seats win over holds on overlap.
- **`trips.boarded_seats`** is a `TEXT[]` the conductor toggles; boarding is rejected earlier
  than 30 minutes before departure.
- **`vehicles.seat_layout`** is JSONB `{"seats": [{"row": n, "col": n, "label": "1"}, ...]}`.
  `migrate_db.py` rewrote all labels to plain sequential numbers.

### Schema drift — important

There are three sources of DDL and they disagree:

| Source                     | Runs when                            | Creates                                |
| -------------------------- | ------------------------------------ | -------------------------------------- |
| `backend/schema.sql`       | First boot of a fresh `db` volume    | 11 tables, indexes, triggers, RLS      |
| `Base.metadata.create_all` | Every backend startup (`main.py:10`) | Any **table** in `models.py` that is missing |
| `backend/migrate_db.py`    | Every backend startup (`start.sh`)   | Ad-hoc `ALTER TABLE`s, data migrations |

`create_all` only creates missing *tables* — it never adds a column to an existing one. So:

- `reviews` and `user_favourites` are absent from `schema.sql` and get created by `create_all`
  (and `user_favourites` again by `migrate_db.py`). Fine, if noisy.
- **`users.fcm_token` exists in `models.py` but in neither `schema.sql` nor `migrate_db.py`.**
  On a fresh database the `users` table is created from `schema.sql` without that column,
  `create_all` skips the existing table, and no migration adds it — so every query touching
  `fcm_token` (login, `/auth/me`, any notification send) fails with `UndefinedColumn`. The
  current production database presumably has it added by hand. **A fresh deploy will not boot
  correctly until this is fixed** — see [SECURITY.md](SECURITY.md#operational-risks).

`schema.sql` also carries Supabase leftovers: `ENABLE ROW LEVEL SECURITY` on most tables plus
policies written against `auth.uid()`, backed by a local shim function that reads
`request.jwt.claim.sub`. The backend connects as the `postgres` superuser and never sets that
setting, so **RLS is enabled but completely inert**. All access control lives in Python.

## Request flows

### Booking and payment

```
1. POST /seat-holds              passenger  → soft-lock seats for 10 min (configurable)
2. POST /bookings                passenger  → booking(pending/pending), price + platform fee
                                              broadcasts SEAT_HELD on the trip WebSocket
3. POST /payments/initiate       passenger  → refreshes hold, creates payment(pending),
                                              returns a sandbox payment_url
4. POST /payments/sandbox/complete/{txn}    → payment(completed), booking(paid/confirmed),
                                              releases hold, notifies passenger + owner,
                                              sends confirmation SMS
```

Price is computed server-side: `trip.price_per_seat × seats`, plus a platform fee of
`commission_percentage`% + `commission_fixed_fee`, both read from `platform_settings`. Max 6
seats per booking. Step 4 has **no authentication** and step 3's real-gateway sibling
`POST /payments/webhook` has **no signature verification** — both are documented gaps.

The mobile client drives this from `seat_selector_screen.dart` → `sandbox_payment_screen.dart`.

### Real-time channels

Three independent WebSocket endpoints, each with its own in-process connection manager:

| Endpoint                              | Auth                  | Purpose                                        |
| ------------------------------------- | --------------------- | ---------------------------------------------- |
| `/api/v1/trips/ws/{trip_id}`          | **none**              | Seat hold/release/book events for a seat map    |
| `/api/v1/ws/tracking/{vehicle_id}`    | `?token=` + role check | Driver streams GPS; passengers receive it       |
| `/api/v1/notifications/ws?token=`     | `?token=`             | Per-user live notification feed                 |

All three keep connection state in a module-level dict, which means **the backend cannot be
scaled beyond one process** — a second worker would hold a disjoint set of sockets. Any move to
multiple replicas needs a shared broker (Redis pub/sub or similar) first.

> [!IMPORTANT]
> **A socket must never hold a database session.** Both handlers authenticate inside a
> `with session_scope() as db:` that closes before the socket starts running, and the GPS driver
> loop opens one scope per fix. This used to be one `SessionLocal()` per socket, closed only on
> disconnect, which pinned a pooled connection and an open transaction for every signed-in user
> and capped the platform at ~15 of them. Keep new socket code to the same shape: no session
> lives across an `await`.

Tracking authorises drivers as: vehicle owner, a conductor in the same company, or an admin.
Passenger listeners are authenticated but not restricted — any logged-in user can watch any
vehicle's location.

Nginx sets no `proxy_read_timeout`, so its 60-second default closes any socket quiet for a minute
— which the receive-only notifications socket always is. The GPS provider reconnects with backoff;
the notifications provider does not reconnect at all, so **in-app live notifications stop working
about a minute after sign-in** and only FCM push keeps arriving. See
[CODE_QUALITY.md](CODE_QUALITY.md) P8.

### Notification fan-out

`create_and_send_notification()` in `routes/notifications.py` is the single funnel: it writes a
`notifications` row, pushes over the user's WebSocket, then sends an FCM push if the user has a
`fcm_token`. Firebase Admin is lazily initialised from `GOOGLE_APPLICATION_CREDENTIALS` on first
use. Booking confirmations additionally trigger a Notify.lk SMS.

Triggers: booking confirmed (passenger + owner), trip status → ongoing/cancelled, trip
rescheduled, new vehicle registered (all admins), 30-minute departure reminder, and admin
broadcast/direct sends.

## Mobile app

Flutter with Riverpod (`NotifierProvider` throughout, no code generation). 34 Dart files.

```
mobile/lib/
├── main.dart              # entrypoint; re-exports everything for legacy imports
├── providers/             # auth, trips, bookings, fleet, gps, notifications, favourites
├── screens/               # passenger screens at top level; owner/ and conductor/ subfolders
├── theme/                 # colours, text styles, ThemeData
└── widgets/               # 3D seat, toasts, shimmer skeletons
```

`shared_providers.dart` holds global state that predates the provider split: `globalPrefs`
(a `late` `SharedPreferences`), `navigatorKey`, the API/WS base URL settings, and all Firebase
Messaging setup. `main.dart` re-exports every provider and screen so older `import 'main.dart'`
call sites keep working — new code should import the specific file instead.

Session state (token, role, name, NIC, gender, phone) is persisted in `SharedPreferences` in
plaintext, and the JWT with it.

iOS push needs an APNs token before FCM will issue a token, so `setupPushNotifications()` polls
`getAPNSToken()` up to 10 times at 2-second intervals before calling `getToken()`, and
`syncFcmToken()` retries the whole sync 5 times with increasing backoff. This is why so many
recent commits touch APNs.

## Admin dashboard

React 19 + React Router 7, no UI framework — hand-rolled components with CSS variables for
theming. `api/client.ts` is a thin typed `fetch` wrapper; every call takes the token explicitly.
Auth lives in `hooks/useAuth.tsx`, token in `localStorage` under `seaty_token`.

Routing is guarded twice: `ProtectedRoute` (any authenticated user) wraps `RoleProtectedRoute`
(role allow-list) per page. Owners see Overview, Bookings, Live Map, Fleet, Trips, Conductors;
admins additionally get Approvals, Companies, Routes, Passengers, Settings, Notifications.
These are **UI guards only** — the backend enforces the real boundary.

Because `API_BASE` is the relative path `/api/v1`, the SPA only works when served from the same
origin as the API — i.e. behind its own Nginx. `npm run dev` needs a Vite proxy or a rebuild.
Two files break that rule and hard-code `wss://api.seaty.hashnate.com`:
`components/NotificationDrawer.tsx` and `pages/SettingsPage.tsx`, so the dashboard's live
notification feed always points at production, including from a dev server.

Two things about this dashboard are easy to misread:

- **Live Map is a mock.** `pages/LiveMapPage.tsx` animates three hard-coded buses on a canvas.
  It is not connected to the GPS WebSocket and shows nothing about real vehicles, but it is routed
  and linked in the sidebar with no indication of that.
- **Operator accounts are created from the Companies page.** `CompaniesPage.tsx` calls
  `POST /auth/register` with `role: 'owner'`, a `company_id`, and the admin's bearer token. The
  endpoint is admin-only and can only ever create owners.
