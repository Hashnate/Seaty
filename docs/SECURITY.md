# Security notes

Findings 1–21 come from a read-through of the codebase as of commit `572492c`, traced in source
only. Findings **22–33 were added at commit `3b43d6a`** and, where marked **verified**, were
confirmed against the running stack rather than inferred. Ordered by severity; numbering is
stable, so later additions appear at the end of each section.

This is an internal engineering note, not a disclosure document — the point is to make the gaps
explicit so they get closed before real passengers and real money are involved.

Non-security defects (correctness, data loss, performance) live in
[CODE_QUALITY.md](CODE_QUALITY.md).

### Status changes at `3b43d6a`

| Finding | Change |
| ------- | ------ |
| **#22 shared hard-coded password** | **Fixed.** `/auth/login` is now restricted to `admin`/`owner`, phone signup is clamped to `passenger`, and the shared constant is replaced by a random discarded secret. Verified end to end. |
| **#23 secrets in the image** | **Image fixed.** `.dockerignore` added to `backend/` and `admin/`; rebuilt image verified clean. |
| **#5 secrets in Compose** | **Removed.** No secret literal remains in `docker-compose.yml`; values come from `backend/.env` and a gitignored root `.env`. |
| **Credential rotation** | `SECRET_KEY` and the database password **rotated and verified**. The Notify.lk API key and the Firebase service account are **still the exposed values** — deferred by decision; they must be replaced in their vendor consoles. |
| **#24 ungated `PUT /trips/{id}`** | **Fixed.** Now `RoleChecker(["owner", "admin", "conductor"])`. Verified: passenger 403, owner/conductor unchanged, anonymous 401. |
| #15 reviews unverified | **Resolved.** `create_vehicle_review` now requires a paid booking on that vehicle, a departure that has passed, and a scanned ticket, one review per booking. Only `passenger_name` remains caller-supplied. |
| **#1 phone login** | **Fixed.** `/auth/phone/login` now requires an `otp_code`, verifies it server-side before the user lookup, and consumes it. Single-use, replay rejected. |
| **#4 registration without a code** | **Fixed.** `otp_code` is a required field and always verified. |
| **#25 hard-coded test numbers** | **Fixed.** Moved out of source to the `TEST_OTP_ACCOUNTS` env var; the code is no longer echoed in the send response and `AUTO` is gone. App Store / Play review sign-in still works. |
| **#10 OTP rate limiting** | **Added** — 60 s resend cooldown, 5 sends/hour, 5 wrong guesses before the code burns, constant-time compare, CSPRNG codes. Storage is still in-process. |
| **#2 open registration** | **Fixed.** `/auth/register` is admin-only and pinned to creating owners. No API path can create an admin; use `backend/create_admin.py`. |
| #17 token lifetime | Raised from 24 h to **7 days** by decision, to cut one-SMS-per-user-per-day. Still no refresh token and no revocation. |
| #9 `ENVIRONMENT` default | Still `development` in `config.py`, but the running container reports `production` (verified). The blanket dev bypass now only affects the code value, since verification itself is no longer skippable. |

---

## Critical — fix before any public launch

### 1. Phone login issued a token for any phone number — **fixed**

`POST /auth/phone/login` took a phone number and a role, looked up the matching user, and returned
a signed JWT. It verified no password, no OTP, and no session state. The mobile app called
`verifyOtp()` first, but that was a separate request, and its result was written to an
`entry["verified"]` flag that **nothing in the codebase ever read** — so a client that skipped the
call got the same token. Anyone who knew a phone number could authenticate as that user.

**What changed.** The OTP is now verified inside the login handler and consumed on success:

- `PhoneLoginRequest` makes `otp_code` mandatory
  ([`schemas.py:474`](../backend/app/schemas.py#L474)).
- `_verify_otp_code(norm, code, consume=True)` runs **before** the user lookup
  ([`routes/auth.py:236`](../backend/app/routes/auth.py#L236)), so a bad code cannot be used to
  probe which numbers exist.
- The code is deleted on success, so it is single-use and cannot be replayed.
- `/auth/otp/verify` still exists for immediate client-side feedback but deliberately does **not**
  consume, and nothing downstream trusts that it was called.

Verified against the running stack:

| Request | Result |
| ------- | ------ |
| login with no `otp_code` field | `422 Field required` |
| login with empty `otp_code` | `400 Verification code is required.` |
| login with a guessed code | `400 OTP code has expired or was not requested.` |
| correct code | `200` + token, then the same code replayed → `400` |

**Client impact**: the mobile app now sends the code on login
([`auth_provider.dart`](../mobile/lib/providers/auth_provider.dart)). Backend and app must ship
together — an older app build cannot sign in.

### 2. Anyone could register themselves as an admin — **fixed**

`POST /auth/register` was unauthenticated and passed `user_in.role` straight to the model, with
`role` declared as a plain string. A single unauthenticated request created an `admin` account
attached to any company — platform settings, refunds, broadcasts, and every company's data.

**What changed.** Account creation is now one-directional, and no API path can produce an admin:

| Role | Created by | Endpoint |
| ---- | ---------- | -------- |
| `admin` | **nothing in the API** | [`backend/create_admin.py`](../backend/create_admin.py), run out of band |
| `owner` | an admin | `POST /auth/register` — `RoleChecker(["admin"])`, `role` pinned to `Literal["owner"]` |
| `conductor` | their owner | `POST /conductors` — `RoleChecker(["owner"])`, role hardcoded |
| `passenger` | self-service | `POST /auth/phone/register` — `role` pinned to `Literal["passenger"]`, OTP required |

Verified against the running stack:

| Request | Result |
| ------- | ------ |
| `/auth/register` anonymous | `401 Not authenticated` |
| `/auth/register` as passenger / owner | `403` — admin only |
| `/auth/register` as admin, `role: "owner"` | `201`, owner created |
| `/auth/register` as admin, `role: "admin"` | `422 Input should be 'owner'` |
| `/auth/register` as admin, `role: "conductor"` | `422 Input should be 'owner'` |
| `/conductors` anonymous / passenger / admin | `401` / `403` / `403` |
| `/conductors` as owner | passes the gate, reaches business logic |

**Consequence to be aware of**: because nothing in the API can create an admin, losing the last
admin account means losing console access. `create_admin.py` is the recovery path — it also resets
an existing account's password and promotes it. Keep at least one admin credential somewhere
recoverable.

**Note**: `POST /conductors` is owner-only by design, so an **admin cannot create a conductor**
even though `GET`/`DELETE` on the same router allow admins. That asymmetry is intentional here but
will look like a bug to whoever hits it in a support scenario.

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

### 4. OTP registration accepted a missing code — **fixed**

`POST /auth/phone/register` validated `otp_code` only `if payload.otp_code:`. Omitting the field
skipped verification entirely, letting anyone register accounts against phone numbers they did not
control.

`otp_code` is now a required `str` on `PhoneRegisterRequest` and is verified unconditionally via
`_verify_otp_code`. Verified: registering without the field returns `422 Field required`.

It verifies without consuming, because the client registers and then immediately signs in with the
same code — sign-in is what burns it.

### 5. Signing secrets were committed in `docker-compose.yml` — **removed, rotation outstanding**

`docker-compose.yml` set `SECRET_KEY` to `SUPER_SECRET_KEY_SEATY_1234567890_CHANGEME_IN_PRODUCTION`
and the database password inline. Both were the same placeholder defaults hard-coded in
[`config.py:8`](../backend/app/config.py#L8), and — the part that made it worse — the Compose
`environment:` block **overrides** `env_file`, so the committed placeholder won even when
`backend/.env` held a real value.

With the signing key, anyone can forge a JWT for any user and role, no login required.

**What changed.** [`docker-compose.yml`](../docker-compose.yml) no longer contains any secret.
`DATABASE_URL` and `SECRET_KEY` come from `backend/.env` via `env_file`; the Postgres credentials
come from a gitignored root [`.env`](../.env.example) by `${VAR}` substitution. Only
`GOOGLE_APPLICATION_CREDENTIALS` — a path, not a secret — remains inline, with a comment saying
why. Verified that the effective configuration is byte-identical afterwards (matching sha256 for
every value), so the change invalidated no sessions and altered no behaviour.

Separately, `backend/.env` was committed once in history (commit `51ec33d`) containing
`DATABASE_URL` and `SECRET_KEY`. It has since been removed from tracking and is gitignored, but
**it is still in the git history and readable by anyone with repository access**.

**Still to do**: the values are unchanged, and two leak paths (git history, pre-existing image
layers — see #23) already expose them. Generate fresh ones and rotate. Rotating `SECRET_KEY` logs
everyone out, which is the desired outcome. Purging history is optional if the values are rotated — rotation is what
matters.

### 22. Every phone-registered account shared one hard-coded password — **fixed**

Was the worst finding in this document; it needed no OTP bypass and no phone-login endpoint.

Phone registration and conductor creation both set
`hashed_password=auth.get_password_hash("seaty_phone_auth_dummy_pass")`. The plaintext was a
literal in the repository and the email is deterministic (`{phone}@seaty.lk`), so `POST /auth/login`
— the ordinary admin email/password endpoint — authenticated as **any** phone user given only
their number. **18 of 23 live accounts** verified against that constant: all 10 passengers and all
8 conductors. Conductor accounts carry a `company_id`, so it was also a route into operator data.

[ARCHITECTURE.md](ARCHITECTURE.md#authentication) previously claimed these users "can never log in
through the password path". That was wrong and has been corrected.

**What changed.** The intended boundary — admin console is password, mobile app is phone + OTP —
is now enforced at the API instead of only in the admin SPA's route guards:

| Change | File |
| ------ | ---- |
| `POST /auth/login` restricted to `auth.PASSWORD_LOGIN_ROLES = ("admin", "owner")`. A disallowed role returns the **same 401** as a wrong password, so the endpoint is not an account/role oracle | [`routes/auth.py:37`](../backend/app/routes/auth.py#L37) |
| `PhoneRegisterRequest.role` is now `Literal["passenger"]` — self-service phone signup can no longer mint an `owner` or `admin` that would then be allowed through the password path | [`schemas.py:466`](../backend/app/schemas.py#L466) |
| `auth.unusable_password_hash()` (random `secrets.token_urlsafe(32)`, discarded) replaces the shared constant in both creation paths | [`auth.py:24`](../backend/app/auth.py#L24), [`routes/auth.py`](../backend/app/routes/auth.py), [`routes/conductors.py`](../backend/app/routes/conductors.py) |
| The app's staff entrance is sign-in only; an unrecognised number is told to contact its operator rather than being shown a signup form | [`auth_screen.dart:389`](../mobile/lib/screens/auth_screen.dart#L389) |

Verified against the rebuilt stack: conductor and passenger accounts now return
`401 Incorrect email or password` for the shared password — byte-identical to the response for a
non-existent account — while `phone/register` with `role=owner` or `role=admin` returns 422. The
5 console accounts (1 admin, 4 owners) are unaffected; they hold real passwords and allowed roles.

**Note for future changes.** The 18 pre-existing accounts still carry a hash of the old constant.
That is harmless — and rotation was considered and deliberately skipped — **only because two
things hold**:

1. `PASSWORD_LOGIN_ROLES` stays `("admin", "owner")`, so no OTP-only account can use a password.
2. No conductor or passenger is ever promoted to `owner`. There is no endpoint for this; it would
   take a manual `UPDATE`, and the team has ruled it out as a business rule.

If either changes, those accounts immediately hold a publicly known working password and must be
rotated first:

```python
# docker compose exec -T backend python
from app.database import SessionLocal
from app import models, auth
db = SessionLocal()
n = 0
for u in db.query(models.User).filter(~models.User.role.in_(auth.PASSWORD_LOGIN_ROLES)).all():
    u.hashed_password = auth.unusable_password_hash(); n += 1
db.commit(); print(f"rotated {n}")
```

Adding any new endpoint that calls `verify_password` has the same effect and the same requirement.

### 23. Runtime secrets were baked into the backend Docker image — **image fixed, rotation outstanding**

There was no `.dockerignore` in `backend/`, and the Dockerfile ends with `COPY . .`, so
`backend/.env` and `backend/firebase-service-account.json` were copied into an image layer.
Confirmed at the time on a fresh container with no mounts:

```bash
docker run --rm --entrypoint sh seaty-backend -c 'cat /app/.env'   # printed SECRET_KEY, DB URL, Notify.lk key
```

Compose mounts the Firebase key read-only at the same path, which hid — but did not remove — the
baked-in copy.

**What changed.** [`backend/.dockerignore`](../backend/.dockerignore) now excludes `.env*`,
`firebase-service-account.json`, key material, `__pycache__/`, `scratch/`, and `scratch_db.py`;
[`admin/.dockerignore`](../admin/.dockerignore) excludes `node_modules` and `dist` (which were
being copied over the freshly installed dependencies). Verified on the rebuilt image:

```
absent: /app/.env          absent: /app/firebase-service-account.json     absent: /app/scratch
ok: start.sh, migrate_db.py, schema.sql, requirements.txt, app/main.py
```

Secrets now reach the container only at runtime — env vars through `env_file`, the Firebase key
through the bind mount.

**Rotation status.** Images built before the `.dockerignore` still contain the old credentials, so
closing this finding required replacing them, not just stopping the leak:

| Credential | Status |
| ---------- | ------ |
| `SECRET_KEY` | **Rotated** — 86-char `secrets.token_urlsafe(64)`. Verified: tokens signed with the old key now fail signature verification. |
| Database password | **Rotated** — 40-char alphanumeric (no reserved characters, since it is embedded in a URL). Verified: `ALTER USER` applied, the old password is refused, the backend reconnected. |
| Notify.lk API key | **Not rotated** — must be reissued in the Notify.lk dashboard. |
| Firebase service account | **Not rotated** — must be reissued in the Firebase console and the old key revoked. |

A pre-rotation `pg_dump` and copies of both env files are in `backups/` (gitignored, mode 600).

### 24. `PUT /trips/{id}` had no role check — **fixed**

[`routes/trips.py:472`](../backend/app/routes/trips.py#L472) depended on `get_current_user`, not
`RoleChecker`, and every ownership check inside is nested under
`if current_user.role in ["owner", "conductor"]`. A passenger skipped all of it and could change
any trip's vehicle, route, times, conductor, and **`price_per_seat`**.

That last one broke the "prices are recomputed server-side" guarantee this document credits under
*What is done well*: set the trip price to `0`, then book normally, and the server computes a
total of zero from its own data. It also let any user fire "Trip Rescheduled!" pushes at every
confirmed passenger on any trip.

`delete_trip`, immediately below it, always got this right — the omission looked accidental.

**What changed.** The handler now takes
`Depends(auth.RoleChecker(["owner", "admin", "conductor"]))`, matching `create_trip`. Verified
against the running stack:

| Caller | Before | After |
| ------ | ------ | ----- |
| passenger | reached the mutations | `403` — role not authorised |
| owner | ownership check | `403` from the company check (unchanged) |
| conductor | ownership check | `403` from the company check (unchanged) |
| anonymous | `401` | `401` |

No client is affected: `updateTrip` is exported in `admin/src/api/client.ts` but not called by any
page, and the page that would call it is already restricted to owner/admin.

**Not fixed here**: conductors retain trip-editing rights, which is finding **#14** — narrowing
this to `["owner", "admin"]` should be done deliberately, with the rest of #14.

### 25. Hard-coded test phone numbers bypassed OTP in production — **fixed**

Four numbers — `0771234567` / `+94771234567` and `0777140803` / `+94777140803` — were hard-coded
as test accounts. For those, **regardless of `ENVIRONMENT`**, `/auth/otp/send` issued `123456` and
**returned it in the response body**, and `/auth/otp/verify` accepted `123456` or the literal
`AUTO`. All four were published in the repository.

These cannot simply be deleted: App Store and Play reviewers must be able to sign in, and they
cannot receive an SMS. The Sign-In Information submitted to App Store Connect is a real credential
that has to keep working.

**What changed.** The list moved out of source into the `TEST_OTP_ACCOUNTS` setting
([`config.py:18`](../backend/app/config.py#L18)), format `phone:code,phone:code`, read from
`backend/.env`. For a configured account:

- `/auth/otp/send` sends no SMS and **does not echo the code** — previously anyone who knew the
  number could read the code straight out of the response, which made it self-service.
- The code must still be submitted and matched (`secrets.compare_digest`); it is not a skip.
- The `AUTO` literal is gone.
- The code is not consumed, so a reviewer can sign in repeatedly.

The credential is now rotatable without a code change, and removable by emptying one env var once
review is done. Verified: reviewer sign-in with `123456` returns a token, repeat sign-in works,
`999999` is rejected, and the send response carries `otp_code: null`.

**Operational note**: point these at throwaway **passenger** accounts. A review account is a
published-in-effect credential, so it must not carry a role or company that grants anything.

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

**Fix**: restrict to `https://admin.seaty.hashnate.com` and whatever the mobile app needs.

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

### 26. `POST /payments/initiate` never checks who owns the booking

[`routes/payments.py:126`](../backend/app/routes/payments.py#L126). The docstring's first line is
"Validates the booking belongs to the current user"; the code does not. Any authenticated
passenger can pass any `booking_id` and the handler will overwrite that booking's `platform_fee`,
flip it to `awaiting_payment`, **release the victim's seat holds**, create a hold for the
*attacker* on the victim's seats, and return a payment row containing the transaction ID.

That transaction ID is the only thing standing between an attacker and #3's unauthenticated
completion endpoint, so this turns "confirm my own booking for free" into "act on a stranger's
booking".

**Fix**: `if booking.passenger_id != current_user.id and current_user.role != "admin": 403`.

### 27. `POST /payments/sandbox/fail/{txn}` is unauthenticated and ignores current state

[`routes/payments.py:329`](../backend/app/routes/payments.py#L329) has no auth dependency and no
guard on the payment's existing status. Called against a **completed** payment it sets the payment
to `failed`, the booking to `failed`/`cancelled`, and releases the holds — cancelling a paid,
confirmed ticket. The passenger is not notified; they find out at the door.

`sandbox_complete_payment` at least returns early when already completed. This one does not.

**Fix**: delete both sandbox endpoints before production (already #3's recommendation), and make
any state transition on a `completed` payment a 409.

### 28. Unauthenticated endpoints leak staff and passenger PII

`TripResponse` embeds a full `UserResponse` for the conductor, which includes `email`,
`phone_number`, and `nic_number` ([`schemas.py:40`](../backend/app/schemas.py#L40)).

- `GET /trips/{trip_id}` ([`trips.py:373`](../backend/app/routes/trips.py#L373)) has **no auth
  dependency at all**.
- `GET /trips` uses `get_optional_current_user`, so anonymous callers get the list — and with it
  every conductor's contact details and NIC.
- `GET /seat-holds/trip/{trip_id}` ([`seat_holds.py:124`](../backend/app/routes/seat_holds.py#L124))
  is also unauthenticated and returns `seat_genders` — a map of which seat holds a male or female
  passenger, for a named bus at a named time.

Trip UUIDs are handed out by the anonymous list endpoint, so none of this requires guessing.

**Fix**: require authentication on `GET /trips/{id}`; drop `conductor` from anonymous responses
(a name is enough); restrict `seat_genders` to the seat-selection flow for an authenticated
passenger.

### 29. The `None == None` scoping bug also covers schedules and overrides

Finding #13 records this for `vehicles.py`. The same pattern —
`vehicle.company_id != current_user.company_id` — guards `update_schedule`, `toggle_schedule`,
`delete_schedule`, `create_override`, `delete_override`, and `get_schedule`
([`schedules.py:128`](../backend/app/routes/schedules.py#L128) and five sibling lines). None of
them use `RoleChecker`, so the role is never constrained either.

For a **passenger** (`company_id` is `None`) acting on a vehicle whose `company_id` is also `None`,
the inequality is false and access is granted. Since `delete_schedule` cascades to trips, bookings,
and payments ([CODE_QUALITY.md](CODE_QUALITY.md) C3), that is an unauthenticated-adjacent data
destruction path for any company-less vehicle.

**Fix**: as #13 — treat a missing `company_id` as never matching, make it `NOT NULL`, and add
`RoleChecker` to all six handlers.

---

## Medium

### 10. OTP rate limiting — **added; storage still in process memory**

`otp_store` was a bare module-level dict with no caps: `/auth/otp/send` could be looped to burn
SMS credit or spam a number, and a 6-digit code could be walked at leisure inside its 5-minute
window. Both mattered much more once the code actually gated login (#1).

**What changed** ([`routes/auth.py`](../backend/app/routes/auth.py)):

| Control | Value |
| ------- | ----- |
| Resend cooldown per number | 60 s |
| Sends per number per hour | 5 |
| Wrong guesses before the code is burned | 5 |
| Code lifetime | 5 min |
| Comparison | `secrets.compare_digest` |
| Codes generated with | `secrets.randbelow` (was `random.randint`) |

Expired codes and stale send history are pruned on each send, so neither dict grows without
bound. Verified: the 6th wrong guess returns `429` and destroys the code; an immediate resend
returns `429` with the seconds remaining; the 6th send in an hour is refused.

**Still open**: the state is per-process. It is lost on every deploy — an in-flight code stops
working and the user sees "expired" — and it is one more reason the backend cannot run more than
one worker. Moving it to Postgres would fix both; there is no Redis in this stack. Per-IP limits
are also still absent, so the caps above are per-number only.

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

### 15. Reviews are unverified and unlimited — **resolved at `3b43d6a`**

~~Any authenticated user could post unlimited reviews for any vehicle.~~
`create_vehicle_review` ([`reviews.py:39`](../backend/app/routes/reviews.py#L39)) now requires a
paid booking on that vehicle, a departure time that has passed, a ticket actually scanned by the
conductor, and permits one review per booking. It is currently the strictest authorisation in the
codebase.

Two residues: `passenger_name` is still caller-supplied (it defaults to the account name, but a
caller can send anything), and the one-per-booking rule is a Python check-then-insert with no
`UNIQUE (booking_id)` behind it, so concurrent submissions both succeed.

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

Tokens last **7 days** (raised from 24 h) and there is no refresh token, no revocation list, and
no server-side logout — logout only clears local state, so a captured token stays valid for its
full lifetime, and nothing can cut a session short.

The lifetime was extended deliberately: with no refresh flow, expiry is the only thing that forces
a re-login, and every re-login costs a real SMS. A 24-hour token meant roughly one OTP per active
user per day. The trade-off is a seven-times-longer window for a stolen token, which makes the
absence of revocation matter more than it did.

**Fix**: `flutter_secure_storage` on mobile, and a short access token plus a refresh token — that
removes the cost argument for long sessions entirely. A revocation list (or a `token_version`
column on `users`, bumped on logout) would make sign-out actually mean something.

### 30. Operator documents are readable by every authenticated user

`VehicleResponse` includes `document_urls` ([`schemas.py:128`](../backend/app/schemas.py#L128)),
and `GET /vehicles` returns every verified vehicle to any passenger
([`vehicles.py:69`](../backend/app/routes/vehicles.py#L69)). Uploads are served by
`StaticFiles` at `/uploads` with no authentication, so handing out the URL hands out the file.
Filenames are UUIDs, which protects against guessing but not against being told.

**Fix**: drop `document_urls` (and arguably `contact_phone`) from the passenger-facing serialiser;
serve documents through an authenticated endpoint rather than the static mount.

### 31. The interactive API docs are publicly served

`admin/nginx.conf`'s `api.seaty.hashnate.com` block proxies `/` wholesale, so `/docs`, `/redoc`,
and `/openapi.json` are public — verified returning 200 through the running proxy. That publishes
a complete, accurate map of every endpoint, including the unauthenticated ones in #3, #7, #12,
#27, and #28.

**Fix**: `docs_url=None, redoc_url=None, openapi_url=None` in production, or deny those paths at
the proxy.

### 32. No rate limiting on login, and no security headers — **largely fixed**

Nothing capped login attempts, so any admin password was brute-forceable at line speed. That
mattered acutely because `admin@seaty.lk` was seeded with the password `password` as a development
credential.

**What changed.** Per-IP `limit_req` zones in [`admin/nginx.conf`](../admin/nginx.conf):

| Endpoint | Rate | Burst | Why |
| -------- | ---- | ----- | --- |
| `/auth/login` | 10/min | 5 | Staff only, so a tight cap is safe |
| `/auth/phone/login` | 10/min | 10 | |
| `/auth/otp/send` | 20/min | 10 | Costs an SMS per call; complements the per-number cap in #10 |
| `/auth/phone/check` | 30/min | 20 | User-enumeration oracle |

Verified: twelve rapid login attempts returned `401 ×6` then `429 ×6`, and a genuine sign-in
succeeded once the window reopened — throttled, not locked out.

`X-Content-Type-Options`, `X-Frame-Options: DENY` and `Referrer-Policy` are now set on all three
server blocks.

> [!NOTE]
> **Tuning caveat.** These are per source address, and Sri Lankan mobile carriers NAT heavily —
> many real users can share one IP. The passenger-facing zones are deliberately looser than the
> login zone for that reason. If legitimate users start seeing `429`s at scale, raise
> `auth_check`/`auth_otp` before touching `auth_login`.

**Still open**: no HSTS (belongs at the TLS terminator in front of this container, not here) and
no CSP. The admin SPA keeps its token in `localStorage` (#17), so a CSP is the layer that would
matter most. `admin@seaty.lk` should still be given a real password — rate limiting raises the
cost of guessing it, it does not make `password` an acceptable credential.

### 33. Admin inputs are unvalidated in ways that break the platform

- `GET /admin/analytics/revenue?days=N` ([`admin.py:136`](../backend/app/routes/admin.py#L136))
  runs one query per day in a Python loop with no bound on `N`.
- `PUT /admin/settings/{key}` ([`admin.py:170`](../backend/app/routes/admin.py#L170)) accepts any
  string for any key with no per-key validation. A non-numeric `commission_percentage` makes
  `float()` raise on **every** booking and payment attempt, platform-wide.

Both are admin-only, so this is availability rather than privilege — but "admin fat-fingers a
settings field and all bookings stop" is a real outage mode.

**Fix**: `Query(30, ge=1, le=365)`; a typed schema per settings key.

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
  `platform_settings` — the client cannot submit its own total. (Though **#24** lets it change
  `trip.price_per_seat` first, which is why that finding is Critical.)
- File uploads validate MIME type, extension, and size, use UUID filenames, and verify the
  resolved path stays inside the upload directory.
- All database access goes through the SQLAlchemy ORM with bound parameters; there is no string
  interpolation into SQL anywhere in the codebase.
- Seat availability is computed server-side from confirmed bookings plus unexpired holds, and
  the booking endpoint re-checks it under a 409 rather than trusting the client.
- Mobile signing material is properly gitignored and injected from CI secrets.

## Suggested order of work

Revised at `3b43d6a`. The first three items are the ones that make the platform trivially
compromisable today.

1. ~~**22** — the hard-coded password.~~ **Done.** Rotate the 18 legacy hashes to finish it.
2. **23** — rotate `SECRET_KEY`, the database password, the Notify.lk key, and the Firebase
   service account, then add the `.dockerignore` and rebuild. Do this alongside **5**, which is
   the same rotation from a different leak path.
3. ~~**24** — one dependency, closes an unauthenticated-tier write to trip pricing.~~ **Done.**
4. ~~**1, 4, 25**~~ **Done** — phone login now requires a verified, single-use OTP; rate limits
   added (**10**). ~~**2**~~ **Done** — registration is admin-only and cannot create admins.
   **Remaining on this surface: 3, 26, 27** (payment auth), which together still allow free
   bookings and are the last thing standing between the platform and real money.
5. **6, 28, 29** — the PII and company-scoping gaps, all the same missing check.
6. **31, 8, 12, 11** — reduce surface area: docs, CORS, log endpoints, diagnostics.
7. **32** — rate limiting on the auth paths and security headers.
8. **13, 14, 30, 33** — role scoping and input validation.
9. Everything else as normal hardening work.
