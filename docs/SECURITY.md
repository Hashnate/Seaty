# Security notes

Findings from a read-through of the codebase as of commit `572492c`. Everything below was traced
in source; none of it was tested against a running deployment. Ordered by severity.

This is an internal engineering note, not a disclosure document — the point is to make the gaps
explicit so they get closed before real passengers and real money are involved.

---

## Critical — fix before any public launch

### 1. Phone login issues a token for any phone number

[`routes/auth.py:212`](../backend/app/routes/auth.py#L212) — `POST /auth/phone/login` takes a
phone number and a role, looks up the matching user, and returns a signed JWT. It verifies no
password, no OTP, and no session state. The mobile app calls `verifyOtp()` first
([`auth_provider.dart:174`](../mobile/lib/providers/auth_provider.dart#L174)), but that is a
separate request whose result is never checked server-side — a client that simply skips it gets
the same token.

Anyone who knows a phone number can authenticate as that user, including operators and admins.
Phone numbers of operators are visible through `contact_phone` on vehicles, and
`POST /auth/phone/check` confirms which numbers exist and under what role.

**Fix**: make `/auth/phone/login` require the OTP code and verify it server-side, the way
`/auth/phone/register` does when a code is supplied. Mark the OTP entry consumed on success.

### 2. Anyone can register themselves as an admin

[`routes/auth.py:12`](../backend/app/routes/auth.py#L12) — `POST /auth/register` is
unauthenticated and passes `user_in.role` straight to the model.
[`schemas.py:22`](../backend/app/schemas.py#L22) declares `role` as a plain string defaulting to
`passenger`, with no validation. `company_id` is accepted the same way.

A single unauthenticated request creates an `admin` account attached to any company, granting
platform settings, refunds, broadcasts, and every company's data.

**Fix**: force `role="passenger"` on public registration and move privileged account creation
behind an admin-only endpoint. Constrain the field with an `Enum` so it can never widen again.

### 3. Payments can be completed without authentication

[`routes/payments.py:197`](../backend/app/routes/payments.py#L197) —
`POST /payments/sandbox/complete/{transaction_id}` has no auth dependency. It sets the payment
to `completed`, the booking to `paid`/`confirmed`, releases the seat hold, and fires
confirmation SMS and push. The transaction ID is returned to the client that initiated the
payment, so any passenger can confirm their own booking without paying, and IDs are guessable
enough to be worth brute-forcing (`SB-` + 12 hex characters).

[`routes/payments.py:286`](../backend/app/routes/payments.py#L286) — `POST /payments/webhook`
has the same problem with no signature verification; the docstring notes this is where PayHere
or Stripe validation *would* go.

**Fix**: delete the sandbox endpoints before production. When a real gateway is integrated,
verify its signature on the webhook and treat the gateway's server-to-server callback as the
only path that can mark a booking paid.

### 4. OTP registration accepts a missing code

[`routes/auth.py:169`](../backend/app/routes/auth.py#L169) — `POST /auth/phone/register`
validates `otp_code` only `if payload.otp_code:`. Omit the field entirely and the account is
created with no verification at all, letting anyone register accounts against phone numbers they
do not control.

**Fix**: require the code and verify it unconditionally.

### 5. Signing secrets are committed in `docker-compose.yml`

[`docker-compose.yml:26`](../docker-compose.yml#L26) sets `SECRET_KEY` to
`SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION` and line 12 sets the database
password inline. Both are the same placeholder defaults hard-coded in
[`config.py:8`](../backend/app/config.py#L8), and the Compose `environment:` block **overrides**
whatever `.env` provides.

With the signing key, anyone can forge a JWT for any user and role — no login required.

Separately, `backend/.env` was committed once in history (commit `51ec33d`) containing
`DATABASE_URL` and `SECRET_KEY`. It has since been removed from tracking and is gitignored, but
**it is still in the git history and readable by anyone with repository access**.

**Fix**: generate fresh values, move them to `.env` or Docker secrets, remove the literals from
Compose, and rotate the database password. Rotating `SECRET_KEY` logs everyone out, which is the
desired outcome. Purging history is optional if the values are rotated — rotation is what
matters.

---

## High

### 6. Trip manifests expose passenger PII across companies

[`routes/trips.py:486`](../backend/app/routes/trips.py#L486) — `GET /trips/{id}/manifest` is
gated on role (`admin`, `owner`, `conductor`) but never checks that the trip belongs to the
caller's company. Any conductor account — which any owner can create, and which the phone-login
gap above makes reachable anyway — can read the full manifest of **any trip on the platform**:
passenger names, genders, and phone numbers.

`POST /trips/{id}/toggle-board` ([`trips.py:541`](../backend/app/routes/trips.py#L541)) has the
same missing scope check, so any conductor can mark seats boarded on any trip.

**Fix**: apply the company/assignment check used elsewhere in the same router (see
`update_trip_status` at line 331 for the pattern).

### 7. Seat availability WebSocket is unauthenticated

[`routes/trips.py:602`](../backend/app/routes/trips.py#L602) —
`ws://…/api/v1/trips/ws/{trip_id}` accepts any connection with no token. It is read-only, so the
exposure is limited to seat activity on a trip whose UUID you already know, but it is also an
unmetered connection sink with no limit on concurrent sockets.

The other two WebSockets (`/ws/tracking/{vehicle_id}`, `/notifications/ws`) do authenticate via
a `token` query parameter. That places the JWT in URLs, where it lands in proxy and access logs —
acceptable given the WebSocket API's header limitations, but worth keeping in mind when
configuring log retention.

### 8. CORS allows every origin with credentials

[`main.py:21`](../backend/app/main.py#L21) — `allow_origins=["*"]` with
`allow_credentials=True`, `allow_methods=["*"]`, `allow_headers=["*"]`. The inline comment
already flags it. Because the admin SPA stores its token in `localStorage` rather than a cookie,
this is not directly exploitable as CSRF, but it removes a layer that should be there.

**Fix**: restrict to `https://seaty.hashnate.com` and whatever the mobile app needs.

### 9. Development mode silently disables OTP

[`routes/auth.py:80`](../backend/app/routes/auth.py#L80) — when
`ENVIRONMENT` is `dev`/`development`, `POST /auth/otp/send` always issues `123456` **and returns
it in the response body**, and `/auth/otp/verify` accepts `123456` or the literal `AUTO` for any
number.

`ENVIRONMENT` defaults to `development` in [`config.py:6`](../backend/app/config.py#L6). If
`.env` is missing or the variable is unset, production runs with OTP disabled and no visible
signal. Combined with finding #1 this is moot today, but it must not be the fallback once phone
login is fixed.

**Fix**: default to `production` and fail startup loudly if the value is unrecognised.

---

## Medium

### 10. OTP has no rate limiting and lives in process memory

`otp_store` ([`auth.py:63`](../backend/app/routes/auth.py#L63)) is a module-level dict. There is
no cap on send attempts, so `/auth/otp/send` can be used to burn SMS credit or spam a number, and
no cap on verify attempts, so a 6-digit code is brute-forceable within its 5-minute window. The
store is also lost on restart and not shared between processes.

**Fix**: move to Redis or the database, rate-limit per phone and per IP, and lock an entry after
a handful of failed verifications.

### 11. `fcm-status` dumps the whole user table to any admin

[`notifications.py:289`](../backend/app/routes/notifications.py#L289) returns every user's ID,
name, and role. It is admin-only and intended as a diagnostic, but it is an unpaginated dump of
the user base sitting on a permanently mounted route.

**Fix**: remove it, or reduce it to aggregate counts.

### 12. Unauthenticated log-injection endpoints

`POST /api/v1/notifications/public/log`
([`notifications.py:321`](../backend/app/routes/notifications.py#L321)) and its duplicate
`POST /api/v1/public/log` ([`main.py:61`](../backend/app/main.py#L61)) print arbitrary
caller-supplied strings to server stdout with no auth and no length limit. That means log
flooding, log forging via newline injection, and disk pressure.

These were added for native iOS diagnostics. **Fix**: delete both.

### 13. `None == None` widens company scoping

Several checks are written as `vehicle.company_id != current_user.company_id`
([`vehicles.py:155`](../backend/app/routes/vehicles.py#L155) and
[`:173`](../backend/app/routes/vehicles.py#L173)). When an owner has no company **and** the
vehicle has no company, both sides are `NULL`/`None`, the inequality is false, and access is
granted. Vehicles created by a company-less owner get `company_id=None`
([`vehicles.py:21`](../backend/app/routes/vehicles.py#L21)), so any company-less owner can edit
or delete any other company-less owner's vehicles.

**Fix**: treat a missing `company_id` as never matching, and require owners to have a company.

### 14. Conductors have owner-level fleet permissions

`create_vehicle`, `update_vehicle`, `delete_vehicle`, `create_trip`, and `delete_trip` all accept
the `conductor` role. A conductor is meant to scan tickets and mark boarding, not restructure the
fleet. Note also that `update_vehicle` resets `is_verified` to false, so a conductor can take
every vehicle in a company offline.

**Fix**: narrow these to `owner` and `admin`.

### 15. Reviews are unverified and unlimited

[`reviews.py:36`](../backend/app/routes/reviews.py#L36) lets any authenticated user post any
number of reviews for any vehicle, with no check that they ever travelled on it, and
`passenger_name` is caller-supplied.

**Fix**: require a completed booking on that vehicle, one review per booking, and take the name
from the account.

### 16. Notify.lk credentials travel in the query string

[`sms_service.py:48`](../backend/app/services/sms_service.py#L48) builds
`{API_URL}?user_id=…&api_key=…&…`. TLS protects it in transit, but query strings are routinely
written to access logs and proxy logs on both ends. This is what the vendor's API requires, so
the mitigation is operational: keep the key rotatable and treat any log capture as a compromise.

### 17. JWTs are stored in plaintext on the client

The mobile app persists the token in `SharedPreferences`
([`auth_provider.dart:79`](../mobile/lib/providers/auth_provider.dart#L79)) alongside the user's
name, NIC, gender, and phone. The admin dashboard stores it in `localStorage`
([`useAuth.tsx:25`](../admin/src/hooks/useAuth.tsx#L25)). Neither is encrypted; on a rooted or
jailbroken device the mobile token is readable by other apps, and `localStorage` is readable by
any XSS.

Tokens last 24 hours and there is no refresh token, no revocation list, and no server-side
logout — logout only clears local state, so a captured token stays valid for its full lifetime.

**Fix**: `flutter_secure_storage` on mobile, and shorter-lived tokens with a refresh flow.

---

## Low

### 18. Any authenticated user can track any vehicle

[`tracking.py:157`](../backend/app/routes/tracking.py#L157) — the `passenger` branch
authenticates the user but never checks for a booking on that vehicle. Anyone logged in can
watch any bus's live GPS. Driver-side streaming *is* properly scoped to owner, same-company
conductor, or admin.

### 19. Migration failures do not stop startup

`migrate_db.py` wraps every statement in a bare `except` that prints and continues, inside an
outer `try` that swallows everything. The backend boots against a half-migrated schema and only
a log line records it. See [DEPLOYMENT.md](DEPLOYMENT.md#database).

### 20. Row-level security is enabled but inert

`schema.sql` enables RLS on most tables with policies written against a Supabase-style
`auth.uid()`, backed by a local shim reading `request.jwt.claim.sub`. The backend connects as the
`postgres` superuser (which bypasses RLS entirely) and never sets that variable. The policies
give the appearance of defence in depth while providing none.

**Fix**: either drop the policies to avoid false confidence, or connect as a non-superuser role
and set the claim per transaction.

### 21. Unpinned backend dependencies

`requirements.txt` lists twelve packages with no version constraints. Builds are not
reproducible, and a breaking upstream release lands on the next `docker compose build`.

**Fix**: pin, and use `pip-compile` or equivalent.

---

## What is done well

Worth recording so it does not get undone:

- Passwords are bcrypt via `passlib`, with per-password salts and no home-grown crypto.
- Authorisation reads the role from the **database row**, not the JWT claim, so a stale token
  cannot escalate after a role change.
- Prices and platform fees are computed server-side from `trip.price_per_seat` and
  `platform_settings` — the client cannot submit its own total.
- File uploads validate MIME type, extension, and size, use UUID filenames, and verify the
  resolved path stays inside the upload directory.
- All database access goes through the SQLAlchemy ORM with bound parameters; there is no string
  interpolation into SQL anywhere in the codebase.
- Seat availability is computed server-side from confirmed bookings plus unexpired holds, and
  the booking endpoint re-checks it under a 409 rather than trusting the client.
- Mobile signing material is properly gitignored and injected from CI secrets.

## Suggested order of work

1. Findings **1–5** together — they are one auth/payment surface and a partial fix leaves the
   hole open.
2. **6** (manifest PII) and **9** (`ENVIRONMENT` default) — both are one-line changes with
   outsized impact.
3. **8, 12, 11** — reduce surface area: CORS, log endpoints, diagnostics.
4. **13, 14** — tighten role and company scoping.
5. Everything else as normal hardening work.
