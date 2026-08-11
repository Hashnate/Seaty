# Deployment

## Stack

`docker-compose.yml` defines three services on one network:

| Service   | Image                        | Host port | Notes                                        |
| --------- | ---------------------------- | --------- | -------------------------------------------- |
| `db`      | `postgres:16-alpine` + schema | —         | Volume `seaty-postgres-data`                 |
| `backend` | `python:3.11-slim` + FastAPI  | —         | Volume `seaty-uploads` at `/app/uploads`     |
| `admin`   | Node build → `nginx:alpine`   | `8025:80` | Serves the SPA *and* proxies the API         |

Only `admin` is published. Everything external — the SPA, the REST API, and all three WebSocket
endpoints — enters through that one Nginx container on port 8025, which a host-level reverse
proxy (and TLS terminator) is expected to sit in front of for `admin.seaty.hashnate.com` and
`api.seaty.hashnate.com`.

```bash
docker compose up -d --build          # deploy / redeploy
docker compose logs -f backend        # tail
docker compose ps                     # status
```

> [!IMPORTANT]
> Two things bite on every backend deploy:
>
> **`--force-recreate` does not pick up code changes.** The backend Dockerfile bakes the source in
> with `COPY . .` and there is no volume mount for `app/`, so a container recreated from the
> existing image runs the *old* code while the files on disk show the new. It fails silently — the
> app starts fine and behaves as before. Always `--build`.
>
> **Recreating the backend leaves the site returning 502.** Nginx resolves `proxy_pass
> http://backend:8000` once, at config load, and caches the container IP. The new container gets a
> new IP that Nginx keeps missing, so restart the proxy too.
>
> ```bash
> docker compose up -d --build backend && docker compose restart admin
> ```
>
> A full `docker compose up -d --build` covers both. The permanent fix for the second is a
> `resolver 127.0.0.11 valid=10s;` plus a variable `proxy_pass` target, so Nginx re-resolves.

Nothing in the repo automates server-side deployment — the only CI pipeline builds the mobile
app. Backend and admin releases are manual: pull, `docker compose up -d --build`.

## Environment

`backend/.env` is loaded via `env_file` and must exist before `docker compose up`.

| Variable                | Purpose                                | Notes                                              |
| ----------------------- | -------------------------------------- | -------------------------------------------------- |
| `ENVIRONMENT`           | `development` or `production`           | **Must be `production`** — also gates `PAYMENT_MODE=mock` |
| `DATABASE_URL`          | Postgres DSN                            | **Required** — no default; absent config stops the app |
| `SECRET_KEY`            | JWT signing key                         | **Required** — no default, for the same reason     |
| `NOTIFYLK_USER_ID`      | Notify.lk account                       | SMS OTP + booking confirmations                    |
| `NOTIFYLK_API_KEY`      | Notify.lk key                           | Sent as a **URL query parameter** — see Security   |
| `TEST_OTP_ACCOUNTS`     | Fixed-OTP accounts for store review     | `phone:code,phone:code`. See below                 |
| `PAYMENT_MOCK_ACCOUNTS` | Numbers that get simulated payments     | Comma-separated. Free bookings — clear before launch |
| `NOTIFYLK_SENDER_ID`    | Registered sender mask                  | Currently `NotifyDEMO` — **the shared demo sender**. See below |
| `NOTIFYLK_API_URL`      | Gateway endpoint                        | Defaults to the live Notify.lk URL                 |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase service account path  | Mounted read-only at `/app/firebase-service-account.json` |
| `UPLOAD_DIR`            | Where uploads are written               | **Do not set it** — see below                      |

Secrets live in two gitignored files and nowhere else:

| File | Holds | Reaches the container via |
| ---- | ----- | ------------------------- |
| `backend/.env` | `SECRET_KEY`, `DATABASE_URL`, Notify.lk credentials, `ENVIRONMENT` | `env_file:` |
| `.env` (repo root) | `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | `${VAR}` substitution in `docker-compose.yml` |

Start from `backend/.env.example` and `.env.example`. `POSTGRES_PASSWORD` must match the password
inside `backend/.env`'s `DATABASE_URL`.

> [!IMPORTANT]
> **Never add a secret to `docker-compose.yml`.** An `environment:` entry silently overrides
> `env_file`, which is exactly how the committed placeholder `SECRET_KEY` used to beat the real
> value in `backend/.env` — the deployment looked configured and wasn't. Only
> `GOOGLE_APPLICATION_CREDENTIALS` (a path) is set there.

`SECRET_KEY` and the database password have been rotated away from the exposed values. **The
Notify.lk API key and the Firebase service account have not** — reissue both in their vendor
consoles, since old image layers and git history (commit `51ec33d`) still carry them.

Confirm new images stay clean after any Dockerfile change:

```bash
docker run --rm --entrypoint sh seaty-backend -c 'ls -la /app/.env' 2>&1   # expect: No such file
```

### Rotating the database password

Postgres only reads `POSTGRES_PASSWORD` when initialising an empty volume, so changing `.env`
alone does nothing to an existing database. The real sequence, with one restart window:

```bash
docker compose exec -T db pg_dump -U postgres seaty > backups/seaty-$(date +%F).sql   # first
docker compose exec -T db psql -U postgres -d seaty -c "ALTER USER postgres WITH PASSWORD '<new>';"
# update POSTGRES_PASSWORD in .env AND the password inside backend/.env's DATABASE_URL
docker compose up -d --force-recreate backend    # --force-recreate: env_file is read at create time
docker compose restart admin                     # nginx re-resolves the backend IP
```

Use an **alphanumeric** password — it is embedded in a URL, so `@ : / ? #` will break parsing.
Rotating `SECRET_KEY` at the same time costs nothing extra, since both need the same restart.

### SMS delivery latency

If OTPs arrive late, check the sender ID before suspecting the application. Measured against the
live gateway, Seaty's own side is not the bottleneck:

```
DNS resolve              4 ms
TCP connect            116 ms
TLS handshake          181 ms
full API round trip    715 ms   ->  {"status":"success","data":"Sent"}
```

Notify.lk accepts the message in under a second. Everything after that — their queue, the carrier,
the handset — is outside this system.

**`NOTIFYLK_SENDER_ID` is `NotifyDEMO`, Notify.lk's shared demo mask.** Sri Lankan carriers
deprioritise unregistered shared senders, which is the usual explanation for multi-minute OTP
delays. Registering a branded mask with Notify.lk (and setting it here) is the fix, and it is an
account action rather than a code change.

Delivery is now observable — every send logs its outcome and timing:

```
docker compose logs backend | grep -i notify
2026-08-11 10:13:36 INFO app.services.sms_service: SMS accepted by Notify.lk for 947XXXXXXXX in 739ms (Sent)
```

A rejection logs at ERROR and the endpoint returns `502` instead of falsely reporting success.

### App Store / Play review accounts

Reviewers cannot receive our SMS, so they need a number whose OTP never changes. That pair is
submitted as **Sign-In Information** in App Store Connect and Play Console, and it must match
`TEST_OTP_ACCOUNTS` in `backend/.env`:

```
TEST_OTP_ACCOUNTS=0771234567:123456,0777140803:123456
```

For a listed number, `/auth/otp/send` sends no SMS and does not echo the code, the code must still
be submitted and matched, and it is never consumed so the reviewer can sign in repeatedly.

Rules worth keeping:

- **Passenger accounts only.** This is a credential that effectively becomes public; it must not
  carry an owner or conductor role, or a `company_id`.
- **Keep it in `.env`, never in source.** The previous version was hard-coded in
  `routes/auth.py` and therefore in the public repository.
- **Clear the variable once review is complete**, and change the code whenever you resubmit.

> [!WARNING]
> **`UPLOAD_DIR` means two different things.** `main.py` uses it as the directory served at the
> `/uploads` URL (default `/app/uploads`); `routes/uploads.py` uses it as the directory files are
> *written* to (default `/app/uploads/vehicles`) while returning URLs under `/uploads/vehicles/`.
> Left unset the two line up and images work. Set it to `/app/uploads` and every uploaded image
> 404s, with no error at upload time.

`ENVIRONMENT` defaults to `development` in `config.py`. Development mode fixes every OTP at
`123456` and echoes it in the send response — verification itself is never skipped, in any
environment, and the `AUTO` literal is gone. It also gates `PAYMENT_MODE=mock`, which refuses to
load in production. Verify it explicitly after every deploy:

```bash
docker compose exec backend python -c "from app.config import settings; print(settings.ENVIRONMENT)"
```

## Database

The `db` image bakes `backend/schema.sql` into `/docker-entrypoint-initdb.d/`, so it runs
**only when the data volume is empty**. Schema changes on an existing deployment must go through
`migrate_db.py`, which `start.sh` runs on every backend boot.

`migrate_db.py` is idempotent-by-try/except rather than by design: it wraps each `ALTER TABLE`
in a bare `except` that prints and continues, and the whole script is inside one outer `try` that
swallows any failure. **A failed migration does not stop the backend from starting** — it prints
`Migration error: ...` and the app boots against a half-migrated schema. Check the logs after
every deploy:

```bash
docker compose logs backend | grep -i "migration"
```

Before schema changes, back up:

```bash
docker compose exec db pg_dump -U postgres seaty > seaty-$(date +%F).sql
```

There is no backup schedule configured anywhere in the repo. Add one.

### Known fresh-deploy blocker

`users.fcm_token` is defined in `models.py` but missing from both `schema.sql` and
`migrate_db.py`, and `create_all` never adds columns to existing tables. A brand-new deployment
therefore comes up without it, and every query touching that column fails. Fix it in
`schema.sql` *and* add a guarded `ALTER TABLE` to `migrate_db.py` so both fresh and existing
databases converge. Until then, apply it manually after the first boot:

```bash
docker compose exec db psql -U postgres -d seaty \
  -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;"
```

## Uploads

Vehicle images land in the `seaty-uploads` named volume, mounted at `/app/uploads`, and are
served by FastAPI's `StaticFiles` at `/uploads`. They are **not** in the database and **not**
covered by `pg_dump` — back up the volume separately:

```bash
docker run --rm -v seaty_seaty-uploads:/data -v "$PWD":/backup alpine \
  tar czf /backup/uploads-$(date +%F).tar.gz -C /data .
```

## Nginx

`admin/nginx.conf` is the only ingress. Shared proxy directives live in `admin/nginx-proxy.conf`
and are `include`d by every backend-facing location — both files are copied in by the admin
Dockerfile, so a change to either needs an image rebuild, not just a restart.

Verify what is actually in effect with `docker compose exec admin nginx -T`.

| Setting | Value | Why |
| ------- | ----- | --- |
| `client_max_body_size` | `6m` | The default 1 MB rejected any image between 1 and 5 MB — a normal phone photo — with a 413 that never reached FastAPI |
| `proxy_read_timeout` | `3600s` | The default 60 s silently closed the receive-only notifications WebSocket every minute of quiet |
| `limit_req` on `/auth/login` | 10/min, burst 5 | Nothing capped login attempts; see [SECURITY.md](SECURITY.md) #32 |
| `limit_req` on `/auth/otp/send` | 20/min, burst 10 | Each call costs an SMS |
| `limit_req` on `/auth/phone/check` | 30/min, burst 20 | User-enumeration oracle |
| Security headers | nosniff, `X-Frame-Options: DENY`, `Referrer-Policy` | On all three server blocks |

Rate limits are **per source address**, and Sri Lankan carriers NAT heavily. If real users start
seeing `429`s, raise the passenger-facing zones (`auth_check`, `auth_otp`) before the login zone.

Still absent: HSTS (belongs at the TLS terminator in front of this container) and a CSP. The
`api.seaty.hashnate.com` block also proxies `/` wholesale, which publishes FastAPI's `/docs`,
`/redoc` and `/openapi.json`.

## Capacity and scaling

**The current hard ceiling is roughly 15 concurrent signed-in users**, and it is a database
connection limit, not a CPU or memory one.

`database.py` creates the engine with SQLAlchemy's defaults — `pool_size=5`, `max_overflow=10`,
15 total — and both authenticated WebSocket handlers hold a session open for the whole life of
the socket. Every signed-in app keeps the notifications socket connected, so each user consumes a
pooled connection until they close the app. Past 15, requests block for `pool_timeout` (30 s) and
then fail with `QueuePool limit of size 5 overflow 10 reached`. The symptom is a total API outage
that looks like a database fault and clears on its own as users disconnect.

If you see that error, the immediate mitigation is to raise the pool
(`create_engine(..., pool_size=20, max_overflow=30, pool_pre_ping=True)`); the real fix is to stop
holding a session across the socket lifetime. See [CODE_QUALITY.md](CODE_QUALITY.md) P1.

Separately, the backend must run as a **single process**. All three WebSocket managers (seat
updates, GPS tracking, notifications) hold connections in module-level dictionaries, and the OTP
store is a module-level dict too. A second worker or replica would serve users a disjoint view:
OTPs verified on one process would be unknown to the other, and seat updates would reach only the
clients that happened to land on the broadcasting process.

Before scaling horizontally: move OTP state to Redis or the database, and put the WebSocket fan-
out behind a shared pub/sub layer.

The `GET /trips?date=` endpoint also writes rows on read, so concurrent requests for a
not-yet-materialised date can race and create duplicate trips — a second reason to keep it to
one process until the generator is made idempotent with a unique constraint.

Two things grow without bound and need a plan before they matter:

- **`vehicle_location_history`** — one row per GPS fix, nothing reads it, no retention policy.
  4,750 rows from 3 test vehicles; roughly 2,000/day per bus in service.
- **`notifications`** — never pruned, and the table has no index on `user_id` despite that being
  the only column anything filters on.

## Mobile CI/CD

`.github/workflows/mobile-release.yml` runs on every push to `main` and on manual dispatch.

**Android** (`ubuntu-latest`) — decodes the keystore from secrets, writes `key.properties`,
builds a release APK and AAB, uploads both as workflow artifacts. Nothing is published to Play.

**iOS** (`macos-26`) — decodes the App Store Connect API key and distribution certificate from
secrets, copies the committed `Seaty_App_Store_Profile.mobileprovision`, creates a temporary
keychain, builds a signed IPA with `ios/ExportOptions.plist`, and uploads to **TestFlight**.

Build numbers are `github.run_number - BUILD_NUMBER_OFFSET`, with the offset (currently `3`)
hard-coded in the workflow `env`. Bumping the offset or resetting run numbers will collide with
build numbers already consumed by App Store Connect, which rejects duplicates — adjust
deliberately.

### Required repository secrets

| Secret                            | Used for                              |
| --------------------------------- | ------------------------------------- |
| `ANDROID_KEYSTORE_BASE64`         | Base64 of the release keystore        |
| `ANDROID_KEYSTORE_PASSWORD`       | Keystore password                     |
| `ANDROID_KEY_PASSWORD`            | Key password                          |
| `ANDROID_KEY_ALIAS`               | Key alias                             |
| `IOS_CERTIFICATE_BASE64`          | Base64 `.p12` distribution cert       |
| `IOS_CERTIFICATE_PASSWORD`        | `.p12` password                       |
| `IOS_PROVISIONING_PROFILE_BASE64` | Declared but unused — the profile is read from the repo |
| `APP_STORE_CONNECT_API_KEY_BASE64`| `.p8` key, base64 or raw PEM          |
| `APP_STORE_CONNECT_API_KEY_ID`    | Key ID                                |
| `APP_STORE_CONNECT_ISSUER_ID`     | Issuer ID                             |

No signing material other than the provisioning profile is committed; `mobile/.gitignore`
excludes `*.p8`, `*.p12`, `*.key`, `*.pem`, `*.cer`, and `*.mobileprovision`, and the local
copies in `mobile/` are untracked.

## Pre-launch checklist

Ordered roughly by consequence. The first four are the ones that make the platform trivially
compromisable as it stands.

- [x] ~~Hard-coded phone password removed~~ — done ([SECURITY.md](SECURITY.md) #22). Legacy hashes
      were deliberately **not** rotated; that decision holds only while `PASSWORD_LOGIN_ROLES`
      stays `("admin", "owner")` and no OTP-only account is ever promoted to `owner`.
- [x] ~~`.dockerignore` added to `backend/` and `admin/`~~ — done; rebuilt image verified clean (#23)
- [x] ~~`SECRET_KEY` and the database password moved out of `docker-compose.yml`~~ — done (#5)
- [x] ~~Rotate `SECRET_KEY` and the database password~~ — done and verified
- [ ] **Clear `PAYMENT_MOCK_ACCOUNTS`** — every listed number books for free
- [ ] **Register a branded Notify.lk sender mask** — `NotifyDEMO` is the shared demo sender and the likely cause of slow OTP delivery
- [ ] **Reissue the Notify.lk API key and the Firebase service account** — the remaining two of
      the four exposed credentials. Both need their vendor console; revoke the old Firebase key
      after swapping the file.
- [x] ~~`PUT /trips/{id}` role-gated~~ — done and verified (#24)
- [x] ~~Phone login requires a verified OTP; registration too; test numbers moved to config~~ —
      done and verified (#1, #4, #25, #10)
- [ ] **Ship the mobile app build that sends `otp_code` on login.** The backend change is live and
      **older app builds can no longer sign in** — they post only `{phone_number, role}` and get
      `422`. Anyone on a previous TestFlight build is locked out until they update.
- [x] ~~Open registration closed~~ — `/auth/register` is admin-only and creates owners only; no
      API path can create an admin (#2)
- [x] ~~At least one admin credential exists~~ — `admin@seaty.lk`. Nothing in the API can create
      an admin, so keep this recoverable; `create_admin.py` also resets and promotes an existing
      account:
      ```bash
      docker compose exec backend python create_admin.py ops@example.com "Ops Team"
      ```
- [ ] **Change the `admin@seaty.lk` password.** It is currently `password`, seeded deliberately
      as a development credential. Rate limiting now caps guessing at 10/min, which buys time but
      does not make `password` acceptable on the account that controls settings, refunds, and
      every company's data. The script enforces 12 characters unless `--allow-weak-password`.
- [x] ~~Rate-limit `/auth/login`~~ — done: 10/min per IP, verified (#32)
- [ ] The remaining authentication gaps closed — the unauthenticated payment completion/fail
      endpoints
- [ ] `ENVIRONMENT=production` confirmed on the running container (verified `production` today)
- [ ] `users.fcm_token` present in `schema.sql` and `migrate_db.py`
- [x] ~~`client_max_body_size` and `proxy_read_timeout` set in `admin/nginx.conf`~~ — done
- [ ] Connection pool raised and `pool_pre_ping` enabled, or sessions no longer held across
      WebSocket lifetimes
- [ ] `CORS allow_origins` narrowed from `["*"]` to the real client origins
- [ ] FastAPI `/docs`, `/redoc`, `/openapi.json` disabled or blocked at the proxy
- [ ] Rate limiting on `/auth/login`, `/auth/otp/send`, `/auth/phone/check`
- [ ] TLS terminating in front of :8025, with HTTP redirected
- [ ] Database backups scheduled and a restore actually tested
- [ ] Uploads volume included in backups
- [ ] A real payment gateway integrated and the sandbox endpoints removed
- [ ] `/public/log` endpoints removed from both mounts
- [ ] Retention policy decided for `vehicle_location_history` and `notifications`
