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
proxy (and TLS terminator) is expected to sit in front of for `seaty.hashnate.com` and
`api.seaty.hashnate.com`.

```bash
docker compose up -d --build          # deploy / redeploy
docker compose logs -f backend        # tail
docker compose ps                     # status
```

Nothing in the repo automates server-side deployment — the only CI pipeline builds the mobile
app. Backend and admin releases are manual: pull, `docker compose up -d --build`.

## Environment

`backend/.env` is loaded via `env_file` and must exist before `docker compose up`. Start from
`backend/.env.example`.

| Variable                | Purpose                                | Notes                                              |
| ----------------------- | -------------------------------------- | -------------------------------------------------- |
| `ENVIRONMENT`           | `development` or `production`           | **Must be `production`** — see below               |
| `DATABASE_URL`          | Postgres DSN                            | Overridden by Compose to the internal `db` host    |
| `SECRET_KEY`            | JWT signing key                         | Overridden by Compose — see the warning below      |
| `NOTIFYLK_USER_ID`      | Notify.lk account                       | SMS OTP + booking confirmations                    |
| `NOTIFYLK_API_KEY`      | Notify.lk key                           | Sent as a **URL query parameter** — see Security   |
| `NOTIFYLK_SENDER_ID`    | Registered sender name                  | Defaults to `NotifyDEMO`                           |
| `NOTIFYLK_API_URL`      | Gateway endpoint                        | Defaults to the live Notify.lk URL                 |
| `GOOGLE_APPLICATION_CREDENTIALS` | Firebase service account path  | Mounted read-only at `/app/firebase-service-account.json` |
| `UPLOAD_DIR`            | Where uploads are written               | Defaults to `/app/uploads`                         |

> [!CAUTION]
> `docker-compose.yml` sets `SECRET_KEY` and the database password **inline as literals**, and
> those literals override anything in `.env`. The committed values are the same placeholders
> that ship as defaults in `backend/app/config.py`. Anyone with repository access can forge
> admin JWTs against any deployment still running them. Move both to `.env` (or Docker secrets)
> and rotate them — this invalidates all existing sessions, which is the point.

`ENVIRONMENT` defaults to `development` in `config.py`, and development mode makes OTP a no-op:
every code is `123456`, it is returned in the API response, and `AUTO` is accepted for any
number. If `.env` is missing or the variable is unset, **the deployment silently runs in that
mode**. Verify it explicitly after every deploy:

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

## Scaling

The backend must run as a **single process**. All three WebSocket managers (seat updates, GPS
tracking, notifications) hold connections in module-level dictionaries, and the OTP store is a
module-level dict too. A second worker or replica would serve users a disjoint view: OTPs
verified on one process would be unknown to the other, and seat updates would reach only the
clients that happened to land on the broadcasting process.

Before scaling horizontally: move OTP state to Redis or the database, and put the WebSocket fan-
out behind a shared pub/sub layer.

The `GET /trips?date=` endpoint also writes rows on read, so concurrent requests for a
not-yet-materialised date can race and create duplicate trips — a second reason to keep it to
one process until the generator is made idempotent with a unique constraint.

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

- [ ] `ENVIRONMENT=production` confirmed on the running container (OTP is a no-op otherwise)
- [ ] `SECRET_KEY` and the database password moved out of `docker-compose.yml` and rotated
- [ ] The authentication gaps in [SECURITY.md](SECURITY.md) closed — phone login, open
      registration, and the unauthenticated payment-completion endpoint
- [ ] `users.fcm_token` present in `schema.sql` and `migrate_db.py`
- [ ] `CORS allow_origins` narrowed from `["*"]` to the real client origins
- [ ] TLS terminating in front of :8025, with HTTP redirected
- [ ] Database backups scheduled and a restore actually tested
- [ ] Uploads volume included in backups
- [ ] A real payment gateway integrated and the sandbox endpoints removed
- [ ] `/public/log` endpoints removed from both mounts
