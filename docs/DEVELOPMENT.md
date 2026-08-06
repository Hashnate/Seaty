# Development

## Prerequisites

| Tool           | Version | For                                     |
| -------------- | ------- | --------------------------------------- |
| Docker Desktop | current | Running the full stack                  |
| Python         | 3.11    | Backend outside Docker                  |
| Node.js        | 20+     | Admin dashboard                         |
| Flutter        | 3.11+   | Mobile app (Dart SDK ^3.11.0)           |
| Xcode / Android Studio | — | iOS / Android device builds          |

## Full stack with Docker (recommended)

```bash
cp backend/.env.example backend/.env      # fill in real values before starting
docker compose up --build
```

| Service | Where                                                     |
| ------- | --------------------------------------------------------- |
| Admin   | <http://localhost:8025>                                   |
| API     | <http://localhost:8025/api/v1>                            |
| Docs    | <http://localhost:8025/docs>                              |
| DB      | not published — `docker compose exec db psql -U postgres seaty` |

The backend and database publish no host ports; everything goes through the admin container's
Nginx. `backend/start.sh` waits for Postgres, runs `migrate_db.py`, then starts Uvicorn.

To reset the database completely (this destroys all data):

```bash
docker compose down -v && docker compose up --build
```

`schema.sql` only runs on a **fresh volume** — editing it does nothing to an existing database.

> [!IMPORTANT]
> A fresh database currently comes up without `users.fcm_token`, which breaks login and every
> notification path. Until that is fixed in `schema.sql`, add it by hand after the first boot:
>
> ```bash
> docker compose exec db psql -U postgres -d seaty \
>   -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;"
> ```
>
> See [ARCHITECTURE.md](ARCHITECTURE.md#schema-drift--important) for why.

## Backend on its own

```bash
cd backend
python -m venv .venv && source .venv/Scripts/activate   # Git Bash on Windows
pip install -r requirements.txt

export DATABASE_URL="postgresql://postgres:<password>@localhost:5432/seaty"
export SECRET_KEY="dev-secret"
export ENVIRONMENT="development"
export UPLOAD_DIR="./uploads"

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

You still need a Postgres 16 instance. The quickest one is the Compose database with a port
published temporarily.

`ENVIRONMENT=development` changes real behaviour: `POST /auth/otp/send` always issues `123456`
and returns it in the response body, and `POST /auth/otp/verify` accepts `123456` or `AUTO` for
any number. **Never set this in production.**

`requirements.txt` pins nothing. Two installs weeks apart can produce different dependency trees;
pin versions before you rely on reproducible builds.

## Admin dashboard

```bash
cd admin
npm install
npm run dev      # Vite dev server, default :5173
npm run build    # tsc -b && vite build
npm run lint     # oxlint
```

`api/client.ts` uses the relative base `/api/v1`, so the dev server needs a proxy to reach a
backend. Add one to `vite.config.ts`:

```ts
server: {
  proxy: {
    '/api': { target: 'http://localhost:8000', changeOrigin: true, ws: true },
    '/uploads': { target: 'http://localhost:8000', changeOrigin: true },
  },
},
```

Without it, use `docker compose up` and work against the built bundle on :8025.

## Mobile app

```bash
cd mobile
flutter pub get
flutter run                # attached device or emulator
flutter analyze            # lints from analysis_options.yaml
flutter test               # currently one placeholder widget test
```

### Pointing the app at a local backend

The app defaults to `https://api.seaty.hashnate.com/api/v1`. `SettingsNotifier.updateServerIp()`
in `lib/providers/shared_providers.dart` rewrites both the API and WebSocket base URLs to
`http://<ip>:8000/api/v1`, persisting them to `SharedPreferences`. It's wired to a field in the
profile screen. Use your machine's LAN IP, not `localhost`, when running on a physical device —
and note the port is hard-coded to `8000`, so expose the backend directly for this to work.

### Firebase

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` are committed, so
FCM works out of the box on a checkout. The backend side needs
`backend/firebase-service-account.json` (gitignored) — download it from Firebase Console →
Project Settings → Service Accounts.

Push notifications do not work on the iOS simulator; you need a real device and a paid Apple
Developer account. `initFirebaseMessaging()` skips Firebase entirely on Windows and Linux.

### Signing artefacts

`mobile/` contains local signing material — `AuthKey_*.p8`, `dist_certificate*.p12`,
`private.key`, `*.pem`, `*.cer`. These are covered by `mobile/.gitignore` and are **not** in the
repository; they exist only on this machine. CI gets its own copies from GitHub Secrets. Don't
commit them, and don't delete them without a backup — regenerating an Apple signing identity
means re-provisioning.

`Seaty_App_Store_Profile.mobileprovision` **is** committed on purpose: the iOS CI job copies it
from the checkout. It carries no private key.

## Testing

There is effectively no automated test coverage: one placeholder Flutter widget test, no backend
tests, no frontend tests, no CI test step. The highest-value first tests, in order:

1. Seat-hold concurrency — two users racing for the same seat must produce exactly one 409.
2. Payment state machine — initiate → complete → confirmed, and the failure/refund branches.
3. Authorisation matrix — each role against each router, asserting 403s.
4. Schedule → trip materialisation, including `bus_overrides` and cross-midnight arrivals.

`pytest` + `httpx.AsyncClient` against a throwaway Postgres (or SQLite where JSONB/ARRAY aren't
needed) is the natural fit; nothing is installed yet.

## Conventions

- **Backend**: one router per domain in `routes/`, ORM models in `models.py`, Pydantic in
  `schemas.py`. Authorisation goes through `auth.RoleChecker([...])` as a dependency, never
  inline. Cross-router imports are done inside functions to avoid circular imports — follow
  that pattern rather than moving imports to module level.
- **Mobile**: Riverpod `NotifierProvider`, no code generation. New screens import their
  providers directly rather than relying on the `main.dart` re-exports.
- **Admin**: function components, inline styles keyed to CSS variables, no component library.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `refactor:`), optionally scoped
  (`fix(ios):`, `feat(mobile):`).

## Housekeeping

Three paths in the repo are leftovers and safe to delete: `temp_dir/` (empty), `backend/scratch/`
(only `__pycache__`), and `mobile/colombo.jpg` + `mobile/download_images.py` (a one-off asset
fetch script). `mobile/dist_cert_temp.pem` is a zero-byte file.
