# Code quality

Findings from a full read of `backend/`, `mobile/lib/`, `admin/src/`, and the deployment
configuration at commit `3b43d6a`, cross-checked against the running stack (`docker compose ps`
at the time of writing: `db`, `backend`, `website`, `admin` all up, 23 users / 38 trips /
55 bookings / 4,750 GPS history rows).

This is the non-security counterpart to [SECURITY.md](SECURITY.md) — correctness, data
integrity, performance, and maintainability. Where a finding is both, it is recorded in full
here and cross-referenced there.

Nothing below was fixed as part of writing this document.

---

## Correctness and data integrity

### C1 — `PUT /trips/{id}` had no role gate at all — **fixed**

`update_trip` depended on `auth.get_current_user`, not `RoleChecker`. Every ownership check inside
it is nested under `if current_user.role in ["owner", "conductor"]:`, so a **passenger** fell
straight through to the mutation block and could rewrite any trip's `vehicle_id`, `route_id`,
`departure_time`, `arrival_time`, `price_per_seat`, and `conductor_id`.

Now `Depends(auth.RoleChecker(["owner", "admin", "conductor"]))`
([`trips.py:480`](../backend/app/routes/trips.py#L480)), matching `create_trip`. See
[SECURITY.md](SECURITY.md) #24 for the verification matrix.

**Still open in the same handler**: a `PUT` that omits `conductor_id` sets it to `NULL`
([`trips.py:512-518`](../backend/app/routes/trips.py#L512)) rather than leaving it alone. Because
`TripCreate` makes the field optional, any client updating only the price or the time silently
unassigns the conductor. `PUT` with a full-representation body arguably justifies that, but no
caller sends a full body today.

### C2 — Boarding a seat can mark unrelated bookings "completed"

[`routes/trips.py:686`](../backend/app/routes/trips.py#L686). After toggling a seat, the handler
loads **every** booking on the trip with no status filter and flips any whose seats are a subset
of `boarded_seats` to `completed`:

```python
trip_bookings = db.query(models.Booking).filter(models.Booking.trip_id == trip.id).all()
for b in trip_bookings:
    seats_set = set(b.selected_seats or [])
    if seats_set and seats_set.issubset(boarded_set):
        b.booking_status = "completed"
```

A `cancelled` or `expired` booking for seat 12 becomes `completed` as soon as whoever re-booked
seat 12 is scanned. That booking then counts as occupied
([`models.py:12`](../backend/app/models.py#L12) `OCCUPIED_BOOKING_STATUSES`), appears in the
conductor's manifest, is eligible to leave a review, and shows as a completed journey in the
passenger's history.

**Fix**: filter to `booking_status == "confirmed"`.

### C3 — Deleting a trip or schedule destroys paid bookings and payments

`trips.bookings` cascades on the database side (`ON DELETE CASCADE`), and
[`models.py:137`](../backend/app/models.py#L137) declares
`trips = relationship(..., cascade="all, delete-orphan")` on `TripSchedule`. So:

- `DELETE /trips/{id}` ([`trips.py:553`](../backend/app/routes/trips.py#L553)) deletes the trip →
  Postgres cascades away its bookings → which cascades away their payments.
- `DELETE /schedules/{id}` ([`schedules.py:216`](../backend/app/routes/schedules.py#L216)) deletes
  every trip ever generated from that schedule, and everything hanging off them.

Neither endpoint checks for confirmed or paid bookings first, warns, or soft-deletes. An owner
tidying up an old recurring schedule silently erases the payment record for journeys that were
actually sold and travelled. There is no audit trail left behind — the rows are gone.

**Fix**: refuse deletion when paid bookings exist (409), or soft-delete via `is_active`. At
minimum, return a count so the client can confirm.

### C4 — `migrate_db.py` rewrites every vehicle's seat labels on every boot

[`migrate_db.py:44-75`](../backend/migrate_db.py#L44). Step 4 is not guarded by an
"already applied" check and is not inside a `try`. On **every container start** it reads all
vehicles and reassigns `seat_layout.seats[*].label` to `"1".."N"` in array order.

Seat labels are the join key between a booking and a physical seat: `bookings.selected_seats`,
`trips.boarded_seats`, and `seat_holds.seat_labels` are all `TEXT[]` of these labels. If the
`seats` array order ever changes — an admin edits the layout in
[`MyFleetPage.tsx`](../admin/src/pages/MyFleetPage.tsx), or the JSONB round-trips differently —
the next restart silently renumbers seats **underneath existing bookings**. Passenger A's ticket
now points at Passenger B's seat, and the conductor's manifest agrees with neither.

It is also plain waste: a full read-modify-write of the `vehicles` table on every deploy.

**Fix**: guard it with a `platform_settings` marker the way the reverted timezone migration was
(`trip_tz_fix_applied` is already in the table, so the pattern exists), or delete the step now
that all live layouts are numeric.

### C5 — Two independent booking state machines race each other

The same transition is implemented twice, with different rules:

| Where | Trigger | Behaviour |
| ----- | ------- | --------- |
| [`main.py:129`](../backend/app/main.py#L129) `auto_expire_bookings_scheduler` | every 60 s | confirmed + departed → `completed` if all seats boarded, else `expired` |
| [`bookings.py:128`](../backend/app/routes/bookings.py#L128) `_auto_update_booking_statuses` | on every `GET /bookings` and `GET /bookings/{id}` | same, plus pending-hold timeout → `expired` + `failed` |

Consequences:

- A confirmed booking flips to `expired` within 60 seconds of departure, whether or not the
  passenger is on the bus. If the conductor scans a minute after pulling out — normal — the
  booking has already been marked `expired`, and `toggle-board` then flips it to `completed`
  (via C2's unfiltered loop, which is the only reason it recovers).
- `expired` is not in `OCCUPIED_BOOKING_STATUSES`, so during that window the seat is briefly
  free for rebooking. The comment at [`models.py:8`](../backend/app/models.py#L8) documents
  having already been bitten by exactly this class of bug.
- A read endpoint performs writes. `GET /bookings` mutating rows makes the endpoint
  non-idempotent, non-cacheable, and unsafe to retry.

**Fix**: one owner for the transition. Keep the scheduler, delete the read-path mutation, and
tie "expired" to arrival time rather than departure time.

### C6 — `UPLOAD_DIR` means two different things

| File | Default | Meaning |
| ---- | ------- | ------- |
| [`main.py:28`](../backend/app/main.py#L28) | `/app/uploads` | mounted at URL `/uploads` |
| [`uploads.py:13`](../backend/app/routes/uploads.py#L13) | `/app/uploads/vehicles` | write target; returns URL `/uploads/vehicles/{name}` |

Unset, the two line up by luck and images work. Set `UPLOAD_DIR=/app/uploads` — which is exactly
what [DEPLOYMENT.md](DEPLOYMENT.md#environment) documents as its default — and files land in
`/app/uploads/` while their URLs resolve to `/app/uploads/vehicles/`. **Every image 404s**, with
no error at upload time.

**Fix**: one variable for the root, derive the subdirectory from it in both places.

### C7 — `booked_seats` is computed two different ways

| Source | Filter |
| ------ | ------ |
| [`seat_holds.py:31`](../backend/app/routes/seat_holds.py#L31) `get_unavailable_seats` | status in (`confirmed`,`completed`) **AND `payment_status == "paid"`** |
| [`trips.py:265`](../backend/app/routes/trips.py#L265) and [`trips.py:389`](../backend/app/routes/trips.py#L389) | status in (`confirmed`,`completed`) only |

`GET /trips` therefore reports a seat as booked that `GET /seat-holds/trip/{id}` reports as
available, for any booking that is `confirmed` without being `paid`. The seat map the passenger
picks from and the occupancy count on the trip card disagree.

The booking path uses the stricter one, so this does not oversell seats — it is a display
inconsistency and a trap for the next person who adds a third caller.

**Fix**: call `get_unavailable_seats` from both.

### C8 — Phone-uniqueness is checked two incompatible ways

Registration normalises to the last 9 digits
([`auth.py:65`](../backend/app/routes/auth.py#L65) `normalize_phone_digits`) before checking for
a duplicate. `PUT /auth/profile` ([`auth.py:271`](../backend/app/routes/auth.py#L271)) compares
the **raw string** instead.

So `0771234567` and `+94771234567` collide at registration but not at profile update. Save the
other format from the profile screen and two accounts in the same role end up on one phone
number — after which `/auth/phone/login`'s "first match wins" loop
([`auth.py:235`](../backend/app/routes/auth.py#L235)) decides which of them you log in as, by
table order.

**Fix**: normalise on both paths; better, store the normalised form in a generated column and
put a unique index on `(normalised_phone, role)`.

### C9 — Mobile registration reports success on network failure

[`auth_provider.dart:229`](../mobile/lib/providers/auth_provider.dart#L229):

```dart
} catch (e) {
  debugPrint('API Registration Error: $e');
  return true;      // <- network error, timeout, DNS failure
}
```

`registerPhoneDB` returns `true` when the request never completed. The sign-up flow proceeds as
if the account exists; the subsequent login 404s. The timeout is 5 s, and login's is **2 s**
([`auth_provider.dart:248`](../mobile/lib/providers/auth_provider.dart#L248)) — tight enough on
a mobile network that this is a routine path, not an edge case.

**Fix**: `return false`, and raise the login timeout to something realistic (10–15 s).

### C10 — Naive and aware datetimes are mixed against the same columns

Every timestamp column is `TIMESTAMPTZ`, but writers disagree about what they write:

- `now_sl()` / `to_sl()` (UTC+5:30 aware) — trips, seat-hold cutoffs, boarding windows, review
  eligibility, the schedulers.
- `datetime.datetime.utcnow()` (naive) — `payments.paid_at`/`refunded_at`
  ([`payments.py:302`](../backend/app/routes/payments.py#L302)), seat-hold `expires_at`
  ([`seat_holds.py:108`](../backend/app/routes/seat_holds.py#L108)), the hold-expiry comparison
  ([`seat_holds.py:28`](../backend/app/routes/seat_holds.py#L28)), `schedules.updated_at`.
- `datetime.datetime.now(datetime.timezone.utc)` (UTC aware) — GPS fixes, banners.
- SQLAlchemy column defaults are `datetime.datetime.utcnow` (naive) on **every** model.

It currently works because the container's Postgres session timezone is UTC, so naive values are
interpreted as UTC and the offsets cancel. Change the session timezone, the container base
image, or the host, and seat holds start expiring 5½ hours early or late with no error.

**Fix**: one helper for "now", used everywhere, including the model defaults.

### C11 — Review eligibility has a check-then-insert race

[`reviews.py:103`](../backend/app/routes/reviews.py#L103) checks for an existing review on the
booking in Python, then inserts. There is no unique constraint on `reviews.booking_id`
(confirmed against the live schema), so two concurrent submissions both pass the check.

Worth noting that the rest of this endpoint is now the **strictest** authorisation in the
codebase — paid booking on that vehicle, departure passed, ticket actually scanned, one review
per booking. SECURITY.md finding #15 describes the old, unguarded version and is stale.

**Fix**: `UNIQUE (booking_id)`.

### C12 — Trip materialisation has no uniqueness guard

[`trips.py:174-208`](../backend/app/routes/trips.py#L174) checks "does a trip already exist for
this schedule on this date", then inserts, with a `db.commit()` inside the loop. There is no
unique index on `trips(schedule_id, departure_time)` — verified against the live database — so
two concurrent `GET /trips?date=` calls for a not-yet-materialised date both see nothing and both
insert. Passengers then see the same bus twice, with independent seat maps.

Single-process operation narrows the window (the two requests interleave at `await` points
rather than running in parallel) but does not close it: the check and the insert are separated
by several ORM round trips.

**Fix**: `UNIQUE (schedule_id, departure_time)` and `ON CONFLICT DO NOTHING`.

---

## Performance and scalability

### P1 — Long-lived WebSockets exhaust the database pool (hard ceiling: ~15)

The single most severe scaling limit in the system, and it is not in any current doc.

[`database.py:7`](../backend/app/database.py#L7) creates the engine with no pool arguments, so
SQLAlchemy's `QueuePool` defaults apply: **`pool_size=5`, `max_overflow=10` — 15 connections
total.** Both authenticated WebSocket handlers open a session and hold it for the entire life of
the socket:

- [`tracking.py:97`](../backend/app/routes/tracking.py#L97) — `db: Session = SessionLocal()`,
  closed in `finally` when the driver or passenger disconnects.
- [`notifications.py:139`](../backend/app/routes/notifications.py#L139) — same, and **every
  signed-in app and admin browser tab holds one of these open continuously**.

So the 16th concurrent connected user blocks for `pool_timeout` (30 s) and then every REST
request starts failing with `TimeoutError: QueuePool limit of size 5 overflow 10 reached`. The
symptom is a total API outage that looks like a database problem and clears when users close
the app.

There is also no `pool_pre_ping=True`, so after a Postgres restart the pooled connections are
stale and the first request on each fails.

**Fix, in order**: (1) don't hold a session across the socket lifetime — open one per message or
use a short-lived session for the initial read and the writes; (2) raise `pool_size` and set
`pool_pre_ping=True`; (3) put fan-out behind Redis so the socket layer stops needing the ORM at
all (also the precondition for running more than one process — see
[DEPLOYMENT.md](DEPLOYMENT.md#scaling)).

### P2 — Blocking I/O inside async handlers stalls the whole server

The backend is one process with one event loop, so any synchronous network call inside an
`async def` freezes **everything**, including all live GPS streams and seat updates.

| Call | Where | Blocking for |
| ---- | ----- | ------------ |
| `send_sms` — `urllib.request.urlopen` | [`sms_service.py:57`](../backend/app/services/sms_service.py#L57), awaited via `_send_booking_notifications` | up to its 10 s timeout, on every booking confirmation and every OTP |
| `messaging.send` — Firebase HTTP | [`notifications.py:75`](../backend/app/routes/notifications.py#L75) | one round trip per notification |
| the broadcast loop | [`notifications.py:249`](../backend/app/routes/notifications.py#L249) | one blocking FCM call **per user, sequentially** |

An admin broadcast to 1,000 users is ~1,000 sequential HTTPS calls on the event loop. Nothing
else in the process runs until it finishes.

**Fix**: `run_in_threadpool` (or `httpx.AsyncClient`) for both, and `messaging.send_each_for_multicast`
for broadcasts.

### P3 — Every phone login reads the entire users table

[`auth.py:155`](../backend/app/routes/auth.py#L155), [`:199`](../backend/app/routes/auth.py#L199),
[`:230`](../backend/app/routes/auth.py#L230) — `/auth/phone/check`, `/auth/phone/register`, and
`/auth/phone/login` each run `db.query(models.User).all()` and then normalise phone numbers in
Python. `/notifications/send-direct`
([`notifications.py:266`](../backend/app/routes/notifications.py#L266)) does the same.

`idx_users_phone` exists in the schema and is never used, because the comparison happens
client-side. Sign-in is O(users) in rows transferred and O(users) in Python string work, three
times over for a single sign-in flow (check → send OTP → login).

**Fix**: store the normalised phone and query it directly.

### P4 — N+1 queries on the hottest endpoints

| Endpoint | Pattern |
| -------- | ------- |
| `GET /trips` [`trips.py:254-279`](../backend/app/routes/trips.py#L254) | per trip: vehicle, **all reviews for that vehicle**, route, conductor, all bookings — 5 queries × N trips |
| `GET /bookings` [`bookings.py:210`](../backend/app/routes/bookings.py#L210) | per booking: trip, passenger, route, vehicle, conductor — 5 × N, **and admins get every booking on the platform, unpaginated** |
| `GET /schedules` [`schedules.py:90`](../backend/app/routes/schedules.py#L90) | 3 × N |
| `GET /trips/my-active` [`trips.py:364`](../backend/app/routes/trips.py#L364) | 3 × N |
| `GET /schedules/{id}/overrides` [`schedules.py:314`](../backend/app/routes/schedules.py#L314) | 1 × N |

`GET /trips` is the app's home screen. Average rating is recomputed by loading every review row
for the vehicle and summing in Python, once per trip in the result set — the same vehicle's
reviews are re-fetched for each of its trips that day.

Note that these loops assign to mapped relationship attributes (`trip.vehicle = ...`,
`trip.conductor = ...`) on persistent objects. That marks them dirty; nothing commits afterwards
today, so it is latent rather than broken, but adding a `db.commit()` anywhere downstream would
start writing `conductor_id = NULL` back to trips that have no conductor.

**Fix**: `joinedload`/`selectinload`, a single aggregate query for ratings, and pagination on the
admin lists.

### P5 — Unbounded work driven by client input

- [`admin.py:136`](../backend/app/routes/admin.py#L136) — `GET /admin/analytics/revenue?days=N`
  runs **one query per day** in a Python loop, and `days` is an unvalidated `int`. `?days=100000`
  is 100,000 sequential queries on the event loop.
- `GET /admin/users`, `GET /vehicles`, `GET /bookings`, `GET /notifications`,
  `GET /notifications/fcm-status`, `GET /companies`, `GET /routes`, `GET /schedules` — none
  paginate.
- File uploads are fully read into memory before the size check
  ([`uploads.py:82`](../backend/app/routes/uploads.py#L82)); Starlette spools past 1 MB to disk,
  so the pressure lands on the container filesystem rather than RAM.

**Fix**: `days: int = Query(30, ge=1, le=365)`, one `GROUP BY date` query, and `limit`/`offset`
on the list endpoints.

### P6 — `vehicle_location_history` grows without bound

One row per accepted GPS fix, written on the driver socket
([`tracking.py:180`](../backend/app/routes/tracking.py#L180)), with no retention policy anywhere
in the repo. The live database already holds **4,750 rows from 3 test vehicles**. The mobile
client emits on a 10 m distance filter plus a 15 s heartbeat
([`gps_tracking_provider.dart:241`](../mobile/lib/providers/gps_tracking_provider.dart#L241)), so
a bus on an 8-hour run produces on the order of 2,000 rows/day. Fifty buses is ~36 M rows/year,
in a table nothing currently reads.

**Fix**: decide what it is for. If it is a replay trail, partition by month and drop old
partitions. If nothing reads it, stop writing it.

### P7 — Missing indexes on the paths that matter

Verified against the live database:

| Query | Missing index |
| ----- | ------------- |
| `GET /notifications` — `WHERE user_id = ? ORDER BY created_at DESC` | `notifications(user_id, created_at DESC)` — the table has only its primary key |
| trip materialisation — `WHERE schedule_id = ? AND departure_time BETWEEN ?` | `trips(schedule_id, departure_time)` (also the uniqueness guard from C12) |
| override lookup, once per schedule per date query | `bus_overrides(schedule_id, override_date)` — only a primary key exists |
| `GET /schedules` join | `trip_schedules(vehicle_id)`, `trip_schedules(conductor_id)` — only a primary key exists |
| review lookup by booking | `reviews(booking_id)` |

`notifications` is the one that will hurt first: 361 rows today, and every app foreground fetches
the full list.

### P8 — Nginx defaults contradict the application

`admin/nginx.conf` sets neither directive; confirmed with `nginx -T` on the running container.

- **`client_max_body_size` defaults to 1 MB.** The upload endpoints advertise and enforce a 5 MB
  limit ([`uploads.py:14`](../backend/app/routes/uploads.py#L14)). Anything between 1 and 5 MB —
  i.e. a normal phone photo — is rejected by Nginx with a 413 that never reaches FastAPI, so the
  admin sees a generic failure for a file the API would have accepted.
- **`proxy_read_timeout` defaults to 60 s**, and this one is a live user-visible bug rather than a
  latent risk. The notifications WebSocket is receive-only; neither the mobile client nor
  `NotificationDrawer.tsx` sends a keepalive, so Nginx closes it after 60 seconds of quiet. On the
  app side, `startNotificationsListener()` is called **only** from
  [`notifications_provider.dart:60`](../mobile/lib/providers/notifications_provider.dart#L60) —
  inside `build()`, i.e. once at sign-in — and `onDone`
  ([line 254](../mobile/lib/providers/notifications_provider.dart#L254)) just sets
  `isNotiListenerConnected: false`. There is no reconnect, no backoff, and no app-lifecycle hook.

  **So in-app live notifications work for the first minute after login and then stop for the rest
  of the session.** FCM push still arrives, which is almost certainly why this has gone unnoticed:
  the system tray keeps working while the in-app toast and the live unread badge quietly stop.
  Contrast `gps_tracking_provider.dart`, which has a proper 1/2/4/8/15/30 s backoff on both its
  sockets.

**Fix**: `client_max_body_size 6m;` and `proxy_read_timeout 3600s;` on the proxied locations, an
application-level ping, and reconnect-with-backoff on the notifications socket to match the GPS
one.

---

## Duplication and structure

**Copy-pasted logic.** The same function exists under two names in two modules —
`_get_platform_fee` ([`bookings.py:17`](../backend/app/routes/bookings.py#L17)) and
`_calculate_platform_fee` ([`payments.py:23`](../backend/app/routes/payments.py#L23));
`_get_hold_duration` ([`bookings.py:121`](../backend/app/routes/bookings.py#L121) and
[`seat_holds.py:15`](../backend/app/routes/seat_holds.py#L15)). The hard-coded test-phone list is
duplicated between `send_otp` and `verify_otp`
([`auth.py:81`](../backend/app/routes/auth.py#L81), [`:117`](../backend/app/routes/auth.py#L117)).
The "release this user's holds for this trip" block appears five times in `payments.py` alone.
The nested-object enrichment loop appears in six handlers. The 30-minute boarding check is
written out twice inside a single function
([`trips.py:646`](../backend/app/routes/trips.py#L646) and [`:670`](../backend/app/routes/trips.py#L670)).

There is no service layer: routers hold all business logic, so the only way to share it is to
import across routers, which is why the circular-import dance
(`from app.routes.notifications import create_and_send_notification` inside function bodies)
exists in five files.

**Surprising side effects.** `create_and_send_notification`
([`notifications.py:83`](../backend/app/routes/notifications.py#L83)) calls `db.commit()` on the
caller's session. Callers such as `update_trip_status` depend on that to persist their own
changes, so what looks like a notification helper is load-bearing for unrelated writes.

**Oversized files.** `ticket_screen.dart` 2,250 lines, `bus_details_screen.dart` 1,828,
`passenger_main_screen.dart` 1,689, `tracker_screen.dart` 1,195, `seat_selector_screen.dart`
1,065; `MyTripsPage.tsx` 1,087 and `MyFleetPage.tsx` 948 on the admin side. Each mixes
networking, state, and layout in one widget/component tree.

**Logging.** 20 bare `print()` calls in the backend and 86 `debugPrint` in the app. Only
`sms_service.py` uses the `logging` module — and because the root logger is left at its default
level, its `logger.info` calls (including the Notify.lk response body, the only record of whether
an SMS actually sent) are silently discarded, while `logger.error` gets through. Several prints
leak data: FCM token prefixes and user names
([`auth.py:316`](../backend/app/routes/auth.py#L316),
[`notifications.py:295`](../backend/app/routes/notifications.py#L295)).

**Duplicate route registration.** `/auth/fcm-token`, `/auth/me/fcm-token`, and
`/notifications/fcm-token` are three paths to the same handler body, two of them via stacked
`@router.api_route` decorators ([`auth.py:305`](../backend/app/routes/auth.py#L305)). Likewise
`/api/v1/public/log` exists in both `main.py` and `notifications.py`.

---

## Dead code and unused dependencies

| Item | Note |
| ---- | ---- |
| `google_maps_flutter: ^2.6.1` | Not imported anywhere. `tracker_screen.dart` uses `flutter_map`. Pulls the Google Maps SDK into both binaries for nothing. |
| `video_player: ^2.11.1` | Not imported anywhere; `assets/videos/` is declared in `pubspec.yaml`. |
| `admin/src/pages/LiveMapPage.tsx` | The "Live Map" is a **canvas animation over three hard-coded buses** ([line 5](../admin/src/pages/LiveMapPage.tsx#L5)), not the GPS feed. It is routed and linked in the sidebar with no indication that it is a mock. |
| `backend/scratch/`, `backend/scratch_db.py` | Scratch files shipped in the image (no `.dockerignore`). |
| `IOS_PROVISIONING_PROFILE_BASE64` | Declared as a required secret in [DEPLOYMENT.md](DEPLOYMENT.md#required-repository-secrets); the workflow reads the committed profile instead. |
| RLS policies in `schema.sql` | Enabled, written against `auth.uid()`, inert because the backend connects as superuser. See SECURITY.md #20. |
| `trip_tz_fix_applied` platform setting | Left over from the reverted timezone migration ([`migrate_db.py:177`](../backend/migrate_db.py#L177)). |
| `VehicleLocationUpdate` / `VehicleLocationResponse` schemas | No REST endpoint uses them; tracking is WebSocket-only. |

**Hard-coded hosts in the admin SPA.** `client.ts` is correctly relative, but
[`NotificationDrawer.tsx:54`](../admin/src/components/NotificationDrawer.tsx#L54) and
[`SettingsPage.tsx:316`](../admin/src/pages/SettingsPage.tsx#L316) hard-code
`wss://api.seaty.hashnate.com`. The dashboard's live notification feed therefore always points at
production, including from a local dev server.

---

## Build and dependency hygiene

- **No `.dockerignore` in `backend/` or `admin/`.** `COPY . .` bakes `backend/.env`,
  `backend/firebase-service-account.json`, `__pycache__/`, and `scratch/` into the image. Verified:
  `docker run --rm --entrypoint sh seaty-backend -c 'cat /app/.env'` prints the live `SECRET_KEY`.
  This is a security finding as well — see SECURITY.md.
- **`requirements.txt` is unpinned** — 13 packages, no constraints, no lockfile.
- **`admin/Dockerfile` uses `npm install`, not `npm ci`**, despite `package-lock.json` being
  present, so the lockfile is advisory.
- **Android release falls back to debug signing.** `build.gradle.kts` selects
  `signingConfigs.getByName("debug")` when `key.properties` is absent, so a local
  `flutter build apk --release` silently produces a debug-signed artifact.
- **No R8/ProGuard configuration** — no shrinking, no obfuscation on Android release builds.
- `compileSdk = 36` with `targetSdk = 35`.

---

## Testing

There is none. `mobile/test/widget_test.dart` is the unmodified Flutter template; there is no
`pytest`, no `vitest`, no CI job that runs anything other than the mobile release build. Every
finding above was reached by reading code, because there is no suite to run.

The highest-value first tests, given what is actually fragile:

1. **Seat availability and double-booking** — `get_unavailable_seats` and the 409 path in
   `create_booking`, including the hold/booking overlap rules. This is the money path.
2. **Authorisation matrix** — a parameterised test asserting the expected status for
   (role × endpoint), which would have caught C1 and the SECURITY.md scoping gaps immediately.
3. **Booking state machine** — the transitions in C5 as a table of (status, payment_status,
   departure, boarded) → expected.
4. **Timezone helpers** — `to_sl`/`now_sl` round trips against naive and aware inputs (C10).
5. **Trip materialisation** — one schedule, one date, two calls, one trip (C12).

`docker compose` already gives a real Postgres, so these can run against the actual schema rather
than SQLite, which matters because the code relies on `ARRAY`, `JSONB`, and `TIMESTAMPTZ`.

---

## Suggested order of work

1. **C1** — one-line role gate, currently the widest hole in the system.
2. **P1** — the connection-pool ceiling; it is the difference between "works in demo" and
   "works with 20 users on board".
3. **C3, C4** — the two silent data-destruction paths.
4. **C2, C5, C7** — booking-state correctness, best done as one change with tests.
5. **P8** — two Nginx directives; fixes uploads and WebSocket churn.
6. **P2, P4, P3** — the throughput work, in that order.
7. **C6, C8, C9, C10** — correctness cleanups.
8. Structure, dead code, and pinning as normal maintenance.
