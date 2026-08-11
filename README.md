# Seaty

Bus/luxury-transport seat booking and live-tracking platform for Sri Lanka. Passengers search
trips, pick seats on a live seat map, pay, and track their bus in real time. Operators manage
fleets, recurring schedules, and staff. Conductors scan tickets and mark boarding.

**Live domains:** `seaty.hashnate.com` (marketing site) · `admin.seaty.hashnate.com` (admin web) ·
`api.seaty.hashnate.com` (API)

---

## Repository layout

| Path        | Stack                                       | What it is                                                        |
| ----------- | ------------------------------------------- | ----------------------------------------------------------------- |
| `backend/`  | FastAPI · SQLAlchemy · PostgreSQL           | REST API + WebSockets for seats, tracking, notifications          |
| `mobile/`   | Flutter 3.11 · Riverpod                     | Passenger, owner, and conductor app (iOS + Android)               |
| `admin/`    | React 19 · TypeScript · Vite · Nginx        | Admin & operator dashboard (also reverse-proxies the API)         |
| `website/`  | Static HTML/CSS/JS · Nginx                  | Public marketing site, download links, Privacy Policy & Terms     |
| `database/` | Postgres 16 Docker image                    | Ships `backend/schema.sql` as an init script                      |
| `.github/`  | GitHub Actions                              | Mobile release build → TestFlight + APK/AAB artifacts             |

## Documentation

| Doc                                        | Read it for                                                        |
| ------------------------------------------ | ------------------------------------------------------------------ |
| [Architecture](docs/ARCHITECTURE.md)       | Services, booking/payment/tracking flows, real-time channels       |
| [Data model](docs/DATA_MODEL.md)           | Every table and column, state machines, JSONB shapes, schema drift |
| [API reference](docs/API.md)               | Every endpoint, role requirements, WebSocket protocols             |
| [Development](docs/DEVELOPMENT.md)         | Running backend, admin, and mobile locally                         |
| [Deployment](docs/DEPLOYMENT.md)           | Docker Compose stack, CI/CD, environment variables, capacity limits |
| [Website](docs/WEBSITE.md)                 | Marketing site structure, editing content, deploying to its domain |
| [Payments](docs/PAYMENTS.md)               | Bancstac integration, test/live modes, the missing-webhook gap     |
| [Security](docs/SECURITY.md)               | **Known auth gaps and unauthenticated endpoints — read before launch** |
| [Code quality](docs/CODE_QUALITY.md)       | Correctness bugs, data-loss paths, performance ceilings, dead code |

> [!WARNING]
> **Not taking money yet.** The Bancstac gateway is integrated but unproven — `PAYMENT_MODE` is
> `off`, the live path has never processed a transaction, and there is nowhere to test it without
> real money until a deployment exists with `ENVIRONMENT=development`. See
> [docs/PAYMENTS.md](docs/PAYMENTS.md).
>
> Capacity is limited to roughly **15 concurrent signed-in users** by the database connection
> pool — one busload. See [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) P1; it is the largest
> remaining risk to a launch day.
>
> *Closed:* #22 shared password · #23/#5 secrets in the image, Compose and config fallbacks
> (`SECRET_KEY` and DB password rotated) · #24 ungated trip edit · #1/#4/#25 phone login now
> requires a verified, single-use OTP · #10 OTP rate limiting · #2 admin-only registration ·
> #3/#26/#27 payment auth · #32 login rate limiting and security headers.
>
> *Open:* Notify.lk and Firebase credentials still hold their exposed values (deferred) · #6/#28
> cross-company PII on trip manifests · #13/#29 `None == None` company scoping · P1 connection
> pool · C3 deleting a trip or schedule destroys paid bookings.

> [!IMPORTANT]
> The mobile app must ship together with the current backend. `POST /auth/phone/login` now requires
> an `otp_code`; older app builds send only `{phone_number, role}` and receive `422`.
>
> The console admin is `admin@seaty.lk` with the development password `password`. Login is now
> rate-limited to 10/min per IP, but that is a delay, not a defence — **give it a real password
> before launch**: `docker compose exec backend python create_admin.py admin@seaty.lk "Seaty Super Admin"`.

## Quick start

```bash
cp backend/.env.example backend/.env      # then fill in real values
docker compose up --build
```

The admin dashboard is served on <http://localhost:8025>. The API is reachable through the same
Nginx container at `/api/v1/`, with interactive docs at `/docs`. The backend and database
containers deliberately publish no host ports.

For the mobile app:

```bash
cd mobile
flutter pub get
flutter run
```

The app defaults to the production API. Point it at a local backend from the in-app profile
screen (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#pointing-the-app-at-a-local-backend)).

## Roles

| Role        | Can do                                                                          |
| ----------- | ------------------------------------------------------------------------------- |
| `passenger` | Search trips, hold and book seats, pay, review vehicles, track buses, favourite  |
| `owner`     | Manage own company's vehicles, trips, recurring schedules, and conductors        |
| `conductor` | View assigned trips, scan tickets, mark seats boarded, stream GPS                |
| `admin`     | Everything: approve vehicles, manage companies, platform settings, broadcasts    |

## Tech notes

- Auth is JWT (HS256, 7 days) issued by the backend; the mobile app authenticates by phone + OTP,
  the admin dashboard by email + password.
- Real-time seat availability, GPS tracking, and notifications each run over their own WebSocket.
- Payments go through **Bancstac Paycenter Web 4.0**. `PAYMENT_MODE` (`off` / `mock` / `live`)
  defaults to `off`; the live path is not finished. See [docs/PAYMENTS.md](docs/PAYMENTS.md).
- SMS (OTP and booking confirmations) goes through [Notify.lk](https://notify.lk).
- Push notifications go through Firebase Cloud Messaging (APNs on iOS).
