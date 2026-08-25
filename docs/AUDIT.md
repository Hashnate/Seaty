# Production readiness audit

**Date:** 2026-08-24 · **Commit:** `d75ff8c` + uncommitted fixes ·
**Verdict: 115 / 200 — closer, still not ready to take money.**

> **Second pass.** The audit first scored **94 / 200**. Four of the seven launch blockers have
> since been fixed and verified, one is partly addressed, and two remain. The score below reflects
> the code as it now stands in the working tree. See [Fixes applied](#fixes-applied).

Method: full read of the backend, mobile, admin, website and infrastructure sources; every one of
the 93 routed endpoints exercised; **380 automated checks** (unit, integration, smoke, authorization,
concurrency, load) run against an **isolated copy of the stack** — a throwaway Postgres with the real
`schema.sql`, the real image, `PAYMENT_MODE=mock`, SMS pointed at a black hole. **Production was never
written to.** Its data is identical before and after (34 bookings / 34 payments / 21 users); the only
production access was read-only aggregate SQL.

**323 of 380 checks passed.** The failures cluster into 34 distinct defects listed below.

---

## Score

| # | Area | Was | Now | Why it moved |
|---|------|----:|----:|--------------|
| 1 | Security & access control | 22 | **22 / 40** | Unchanged — no security finding has been fixed |
| 2 | Correctness & data integrity | 13 | **23 / 40** | Seat overselling closed; C1–C15 largely remain |
| 3 | Payments & money handling | 17 | **26 / 30** | Window enforced end to end; refund queue closed as scoped, gateway call deferred to Bancstac |
| 4 | Reliability, performance & scale | 10 | **10 / 25** | Unchanged — search still caps the platform at ~4 req/s |
| 5 | Architecture & code quality | 15 | **15 / 25** | Unchanged |
| 6 | Testing & quality gates | 2 | **3 / 15** | A reproducible suite now exists, but it is not in the repo and CI runs nothing |
| 7 | Operations & deployment | 8 | **8 / 15** | Unchanged |
| 8 | Documentation | 7 | **8 / 10** | This document is current; four stale claims elsewhere still stand |
| | **Total** | 94 | **115 / 200** | |

The platform can no longer sell one seat twice, and the money rules now match the business rules.
What still blocks a launch is smaller but real: an admin typo takes every booking down, one
endpoint crashes instead of denying, and any signed-in user can read any operator's revenue.

<a name="fixes-applied"></a>
## Fixes applied

Verified against the isolated stack; all five earlier suites re-run at baseline
(43/7 · 9/0 · 49/5 · 68/9 · 73/8 — no regressions).

| Blocker | State | What changed |
|---------|-------|--------------|
| **B1** seat sold to three passengers | **Closed** | `create_booking` now takes the seat hold itself, in the same transaction, and locks the trip row. Previously the hold was only created ~1.4 s later by `initiate_payment`, so nothing reserved the seat in between |
| **B2** late payment takes a sold seat | **Closed** | `finalise_payment` re-checks the seats before confirming; if they have gone, the booking is not confirmed and the charge is flagged |
| **B5** payment settles after departure | **Closed** | Guarded on actual departure, not the 30-minute cutoff — a booking made just over that line must still be able to settle. Reachable when an operator reschedules a trip earlier |
| **B3** cancelling a paid booking keeps the money | **Resolved by policy** | Confirmed as intended: bookings are non-refundable, which the app already states. Operator-side cancellation is the exception and now refunds |
| **B4** no refund path | **Closed as scoped** | `GET /payments/refunds/pending` gives admins a worklist; `POST /{id}/refund` no longer claims to process a refund, it records one and clears the queue. Automating the transfer needs a refund operation Bancstac does not expose — **deferred by decision** pending that conversation |
| **B6** admin typo kills all bookings | **Open** | Verified still open: `commission_percentage: "3%"` → every booking 500s |
| **B7** `PATCH /trips/{id}/status` crashes | **Open** | Verified still open: invalid value returns 500, not 400 |

### Carried as process, not as defects

B4 is closed on the code side; two consequences remain that no code can enforce, and both should be
written into whoever owns payments' routine:

- **Refunds are a manual duty.** Somebody has to work `GET /payments/refunds/pending` and send the
  money in Bancstac's portal. If nobody does, nobody gets paid.
- **Nothing reconciles the transfer.** No check asks Bancstac whether a refund really happened, so
  marking one sent is taken on trust. Closable as soon as a refund API exists.

One piece is **not** blocked on Bancstac: the queue has no admin screen, so the notification points
operators at `GET /payments/refunds/pending` — a developer instruction, not something they can act
on. That UI is buildable today and is what turns the queue into a usable process.

### Two further defects were found and fixed during the work

- **Trip cancellation told only half the passengers.** The notify loop queried
  `booking_status == "confirmed"`, so anyone mid-payment or yet to pay heard nothing — and their
  booking stayed live on a dead trip. The passenger sitting on the card page was the one most at
  risk. Every booking holder is now cancelled and notified, with wording that matches whether they
  paid.
- **A payment could confirm a seat on a cancelled trip.** `finalise_payment` now refuses, and
  queues the charge for refund.

Also changed, at the product owner's direction:

- The payment window is **10 minutes**, driven by the existing `seat_hold_duration_minutes`
  setting so the hold and the window cannot drift apart. An earlier draft used 35 minutes to cover
  Bancstac's session; that was reverted.
- The mobile card page now carries a **10-minute countdown** and closes itself when it expires.
  Bancstac's own 30-minute session cannot be shortened by us, so this is the only thing that stops
  a customer paying too late. Production data says the margin is generous: the slowest real
  payment ever recorded took **2 minutes 5 seconds**.
- **Trip cancellations now go out by SMS** as well as push and in-app — one message per passenger,
  deduplicated by number, dispatched concurrently so a full bus does not hold the request. SMS is
  sent for exactly three things: the login OTP, booking confirmation, and trip cancellation.

---

## Blockers — must fix before taking a single real payment

### B1. Three passengers can hold a paid ticket for the same seat — and concurrency is not required

**Corrected 2026-08-24.** An earlier draft of this finding described a check-then-insert *race* in
`create_booking` and prescribed a row lock. That was wrong about the mechanism, and the reality is
broader: no race window is involved in the booking path at all.

`get_unavailable_seats` counts a seat as taken only when a booking is `confirmed`/`completed`
**and** `paid`, or an active unexpired hold exists. A booking sitting at `pending`/`pending` matches
neither condition. Three passengers booked seat 33 **strictly sequentially, 0.4 s apart** — every one
returned 201, and the public seat map reported the seat free after each:

```
p1 POST /bookings seat 33 -> HTTP 201   | seat map: booked=False held=False
p2 POST /bookings seat 33 -> HTTP 201   | seat map: booked=False held=False
p3 POST /bookings seat 33 -> HTTP 201   | seat map: booked=False held=False
booking rows on seat 33: 3
```

All three then settle, because **payment never re-checks the seat**. `initiate_payment` does not call
`get_unavailable_seats` at all — it inserts a *fresh* `seat_hold` for the booking's seats with no
conflict check — and `finalise_payment` verifies the amount and the client reference but never the
seat. Counted in SQL rather than taken from API responses:

```
>>> CONFIRMED+PAID bookings on seat 30, counted in the database: 3
>>> passengers holding a valid paid ticket for seat 30: ['p1', 'p2', 'p3']
```

**What does work, and is worth keeping:** once a booking reaches `confirmed`/`paid`, a later booking
for that seat is correctly refused with a 409. The system defends "book after someone paid". It does
not defend "several people book before anyone pays".

**What normally masks this:** the mobile client takes a seat hold before booking, and under light load
the hold path does return 409 to the second caller. But nothing *requires* a client to take a hold
before `POST /bookings`, and the hold path carries its own genuine check-then-insert race. With three
threads released from a `threading.Barrier` on one seat:

```
Scenario B (holds only):  p4 201, p5 201, p6 409  -> 2 simultaneous ACTIVE holds in the database
Scenario C (hold->book):  p1 201/201, p2 201/201, p3 201/201 -> 3 booking rows on one seat
```

**Nothing at the database level prevents any of it.** The complete index list on the two tables:

```
bookings_pkey · idx_bookings_trip · idx_bookings_passenger · idx_bookings_status
seat_holds_pkey · idx_seat_holds_trip · idx_seat_holds_expires
```

**Corrected fix.** A row lock alone would not have solved the sequential case. Four things are needed:

1. A live booking must block its seats — count unexpired `pending` bookings in
   `get_unavailable_seats`, or require the caller to own an active hold covering every seat booked.
2. A partial unique index over the unnested seat labels of all *live* bookings (pending, confirmed
   and completed — not just paid ones), so the database refuses the second row regardless of code path.
3. A row lock on the trip across the check-and-insert in **both** `create_seat_hold` and
   `create_booking`, to close the concurrent-hold race.
4. The seat-availability re-check in `finalise_payment` (B2), so an abandoned session cannot settle
   onto a seat that has since been sold.

### B2. A payment that returns late confirms a seat already sold to someone else

The hold lasts 10 minutes (`seat_hold_duration_minutes`); the Bancstac session lasts 30, and the
reconciliation sweeper keeps trying to 35. `finalise_payment` re-verifies the amount and the client
reference — but never re-checks that the seats are still free.

Verified: passenger A holds seat 35 and opens a payment. The hold expires. Passenger B holds, books
and pays for seat 35. Passenger A's abandoned session then returns:

```
P1 seat35 = confirmed/paid    P2 seat35 = confirmed/paid    → SEAT SOLD TWICE, both paid
```

`_is_past_booking_cutoff` already exists and is called in `initiate_payment`; the same guard plus a
seat-availability re-check belongs in `finalise_payment` before it flips the booking to confirmed.

### B3. Cancelling a paid booking keeps the customer's money and resells the seat

`cancel_booking` sets `booking_status = "cancelled"` and releases the holds. It does not touch
`payment_status`, does not create a refund, and does not call the gateway.

```
after cancel: booking_status=cancelled  payment_status=paid  payment row=completed
seat 22 immediately rebooked and paid for by another passenger → double revenue on one seat
```

There is also no cutoff — a booking can be cancelled after the bus has departed.

### B4. There is no refund path anywhere in the system

`POST /payments/{id}/refund` sets `payment.status = "refunded"` and a timestamp. No gateway is
called; no `refund` method exists on `DisabledGateway`, `MockGateway` or `BancstacGateway`. An admin
who "refunds" a passenger has moved no money, and the admin console reports success.

Compounding this: cancelling a trip sends passengers a notification saying *"A refund has been
initiated"* (`routes/trips.py`). Nothing initiates one. That is a written promise the platform
cannot keep, and the direct route to chargebacks.

### B5. A payment returning after departure still charges the passenger

Same missing guard as B2. A payment completing after the bus has left marks the booking `expired`
while `payment_status` becomes `paid` — the passenger is charged for a bus they cannot board, and
nothing flags it for refund.

### B6. One admin typo takes the whole platform's bookings down

`PUT /admin/settings/{key}` accepts any string. `_get_platform_fee` does `float(setting.value)`
inside every booking.

```
PUT /admin/settings/commission_percentage {"value": "3%"}  → 200 OK
POST /bookings (any passenger, any trip)                    → 500 Internal Server Error
```

Every booking on the platform fails until someone notices. Seat holds keep working, so the seat map
looks healthy. `seat_hold_duration_minutes: "-5"` is likewise accepted.

### B7. `PATCH /trips/{id}/status` crashes on both of its error paths

```python
def update_trip_status(trip_id: UUID, status: str = Query(...), …):
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, …)
```

The `status` query parameter shadows the imported `fastapi.status` module, so both the
cross-company denial and the invalid-value branch raise
`AttributeError: 'str' object has no attribute 'HTTP_403_FORBIDDEN'` → HTTP 500.

Access is still denied (a 500 is not a 200), but the operator sees an unexplained crash, and any
client that distinguishes 400 from 500 is misled. Verified against both paths.

---

## Security findings

Confirmed by exploitation against the isolated stack. Findings already in
[SECURITY.md](SECURITY.md) are cross-referenced; the rest appear to be new.

### S1. Any operator or conductor can read any trip's passenger manifest — *SEC #6/#28, still open*

`GET /trips/{id}/manifest` gates on role but never on company.

```
owner B → owner A's trip manifest: 200, leaked 2 passengers including phone '0774000001'
conductor B → same trip:           200, leaked 2 passengers
```

Full name, gender, phone number and booking id of every passenger on **any** trip on the platform,
available to every competitor with an operator account. This is the most serious privacy exposure in
the system and it is a PDPA problem, not just a bug.

### S2. Any conductor can mark seats boarded on any company's trip — *new*

`POST /trips/{id}/toggle-board` has the same missing company scope. A rival conductor marked seat 5
boarded on another operator's departed trip: **200 OK**. Because `toggle-board` flips bookings whose
seats are all boarded to `completed`, this also lets one operator corrupt another's booking states —
and `completed` is one-way (S9).

### S3. Any signed-in user can read any company's revenue — *new*

`GET /companies/{id}` scopes only owners (`if current_user.role == "owner" and …`). Passengers and
conductors fall through to the detail response, which includes `total_revenue`, `total_bookings`,
`vehicle_count` and `owner_count`.

```
passenger → company A detail: 200, revenue=5000.0 bookings=1
conductor B → company A:      200, revenue disclosed
```

Any passenger who registers with a phone number can read every operator's takings.

### S4. Conductors have full write access to the company fleet — *SEC #14, confirmed*

`PUT /vehicles/{id}` and `DELETE /vehicles/{id}` use `get_current_user` plus an inline check that
admits conductors. A conductor renamed a company bus and **rewrote its `seat_layout` to empty**:
200 OK. Seat labels are the join key for bookings, holds and boarding.

`create_trip`, `create_schedule` and `create_vehicle` also grant conductors owner-level powers.

### S5. Schedule endpoints have no role gate at all — *SEC #29, confirmed*

`update_schedule`, `delete_schedule`, `toggle_schedule`, `create_override` and `delete_override` all
use bare `get_current_user`. The only barrier is `vehicle.company_id != current_user.company_id`,
which is `False` when both sides are `NULL` — so a passenger (whose `company_id` is always `NULL`)
gains full control of any schedule attached to a company-less vehicle.

**Mitigating:** production currently has **zero** vehicles or staff with a `NULL` `company_id`, so
this is not exploitable today. It becomes exploitable the moment one is created, and nothing prevents
that. `GET /schedules` is also unscoped for passengers — every operator's timetable and pricing is
readable by any signed-in user.

### S6. The seat-map WebSocket is unauthenticated and unbounded — *SEC #7, confirmed*

`/api/v1/trips/ws/{trip_id}` accepts anonymous connections, and accepts **any string** as a trip id:

```
connect to /trips/ws/this-is-not-a-uuid → connected: true
```

Each distinct string creates a key in a module-level dict that is never validated or bounded — a
trivial memory-exhaustion vector against a process that must run single-instance.

### S7. Seat maps, including per-seat gender, are public

`GET /seat-holds/trip/{id}` needs no token and returns `seat_genders`, derived from
`passenger_details`. Anyone on the internet can enumerate which seats are taken on any bus and
whether a man or a woman is in each one. Combined with the public `GET /routes` (also
unauthenticated), the full network map and live occupancy are open.

### S8. CORS reflects any origin *with* credentials — *SEC #8, worse than documented*

`allow_origins=["*"]` with `allow_credentials=True` makes Starlette echo the caller's origin:

```
Origin: https://evil.example
→ Access-Control-Allow-Origin: https://evil.example
  Access-Control-Allow-Credentials: true
```

This is not the "`*`" the code comment implies — it is a per-origin allow, for every origin.

### S9. Rate limits are bypassable via the default vhost

`admin/nginx.conf` applies `limit_req` to `/auth/login`, `/auth/otp/send`, `/auth/phone/check` and
`/auth/phone/login` on the `api.seaty.hashnate.com` server block. The `default_server` block —
reached by the bare IP or any other Host header — rate-limits **only** `/auth/login`. OTP sending,
phone check and phone login are uncapped there. The backend's per-number cap still applies, but
nothing caps an attacker rotating through numbers: an open tap on the Notify.lk balance.

### S10. Phone numbers can be changed and collided without verification

`PUT /auth/profile` changes `phone_number` with no OTP:

```
passenger sets phone to 0779998888 (a number they do not control) → 200 OK
passenger sets phone to '+94771000010' while 0771000010 exists     → 200 OK
```

Uniqueness is checked on the **exact string**, while login matches on the **last 9 digits**
(`normalize_phone_digits`). `0771000010` and `+94771000010` are different strings but the same
account key. `login_phone` then iterates `db.query(User).all()` with no ordering and takes the first
match — so which account a victim signs into becomes arbitrary. Not an account takeover (the OTP
still goes to the real handset), but a live identity-confusion bug. *(SEC #C8, confirmed exploitable.)*

### S11. No password policy

`POST /auth/change-password` accepted a **one-character** password for an operator account, 200 OK.
`create_admin.py` enforces 12 characters; the API enforces nothing. Conversely a password over 72
bytes raises an uncaught `ValueError` from bcrypt → **HTTP 500** on `/auth/register`.

### S12. Two unauthenticated log-injection sinks — *SEC #12, still open*

`POST /api/v1/notifications/public/log` and `POST /api/v1/public/log` both print caller-controlled
text to server stdout, unauthenticated and unrated-limited. Newlines are not stripped, so forged log
lines can be injected. Also a disk-fill vector.

### S13. Interactive API docs are public

`GET /docs` and `GET /openapi.json` return 200 to anonymous callers on the API vhost, publishing the
complete endpoint inventory. *(SEC #31, confirmed.)*

### S14. Any signed-in user can track any vehicle — *SEC #18, confirmed*

A passenger with no booking connected to `/ws/tracking/{vehicle_id}?role=passenger` and received live
GPS. Driver-side authorization, by contrast, is **correct** — every escalation attempt was rejected
(no token, bad token, passenger-as-driver, rival conductor, rival owner, unknown role: all 403).

---

## What is genuinely well built

Worth stating plainly, because it is not a small list.

**Authentication survived every attack in the suite.** Wrong-key tokens, `alg=none`, expired tokens
and a *validly signed* token carrying a forged `role: admin` claim were all rejected — the `role`
claim really is decorative and authorization really does re-read the database row. `token_version`
invalidates sessions on logout, verified. The password/OTP role split holds: passengers and
conductors cannot use `/auth/login`, and a disallowed role returns the same 401 as a wrong password.
Role `Literal`s make an admin unmintable through the API — confirmed on both creation paths.

**OTP handling is sound.** Single-use consumption verified (replay rejected), 60-second resend
cooldown enforced, code burned after 5 wrong attempts, and the code is verified *before* the user
lookup so a wrong code cannot probe which numbers exist.

**The payment gateway abstraction is the strongest code in the repo.** Cents end-to-end via `Decimal`;
the gateway's amount *and* client reference verified against the stored payment before anything is
confirmed; `finalise_payment` idempotent (replay left state intact, verified); completion locked to
the mode that opened the session; `PAYMENT_MODE=mock` refuses to load in production; the
reconciliation sweeper is a well-reasoned substitute for the webhook Bancstac does not provide. The
sandbox shims are correctly clamped to `MOCK-` prefixes — a paid booking could not be flipped to
failed through them.

**The connection-pool ceiling is genuinely fixed.** 60 concurrent signed-in users completing
three-request sessions: 0 failures. The `session_scope` discipline in the WebSocket handlers is
correct and the documented ~15-user cap is gone.

**GPS validation works.** Out-of-range coordinates rejected, an implausible Colombo→London jump
rejected, malformed frames skipped without killing the stream, second driver evicts the first.

**Secrets hygiene is verified clean.** `backend/.dockerignore` works — no `.env` in the running image,
confirmed by inspection. Nginx carries per-IP rate limits and security headers.

**The review gate is correctly enforced** through all four conditions: paid booking, departure passed,
ticket scanned, one review per booking. Every bypass attempt was rejected.

**A fresh deploy boots cleanly** — see the corrections below.

---

## Correctness bugs

| # | Bug | Evidence |
|---|-----|----------|
| C1 | **Trip materialisation race** — 12 concurrent searches created **3 duplicate trips** for one schedule+date. The passenger sees the same bus listed 3 times, each with independent seat inventory. **This has already happened in production**: schedule `08cbdc54…` has 3 trips for 2026-08-17. *(C12, confirmed live.)* | `3 duplicate trips created`, `3 identical listings` |
| C2 | **`POST /notifications/send-direct` by phone is permanently broken.** `auth.normalize_phone_digits` does not exist — it lives in `routes.auth`. Every call → 500. A dead admin feature. | `AttributeError: module 'app.auth' has no attribute 'normalize_phone_digits'` |
| C3 | **Deleting a trip or schedule with any booking returns 500.** SQLAlchemy tries to null `bookings.trip_id` instead of deferring to the DB cascade. Operators can never delete a booked trip and get no explanation. | `NotNullViolation: null value in column "trip_id"` |
| C4 | **`POST /favourites/toggle` with an unknown vehicle → 500** (raw FK violation, should be 404). | `ForeignKeyViolation … user_favourites_vehicle_id_fkey` |
| C5 | **Schedule price edits do not reach generated trips.** Changing a schedule to 9999 left the already-materialised trips at 2750 — passengers book tomorrow at yesterday's fare. Only `conductor_id` propagates. | `generated trips still priced 2750.00` |
| C6 | **Boarding status is one-way.** Un-boarding a seat leaves the booking `completed`; a mis-scan cannot be undone. | `still completed` |
| C7 | **Duplicate seat labels in one booking are charged.** `["8","8","8"]` → 201, `total_price = 7500` for one physical seat. | verified |
| C8 | **Seat labels are never validated against the vehicle layout.** Holds and bookings accept `"999"`, `"SEAT-X"`, and 5000 labels on a 40-seat bus. | verified |
| C9 | **Negative prices accepted end to end.** A trip at `-5000.00` was created and booked, producing `total_price = -5000.0`. | verified |
| C10 | **`broadcast` silently accepts an invalid `target_role`**, reports success, reaches nobody. | verified |
| C11 | **No length limit on any text field.** A 200 KB `full_name` was stored. Every `String` column is unbounded. | verified |
| C12 | **`migrate_db.py` step 4 renumbers every vehicle's seat labels on every boot**, unguarded. Combined with S4 (conductors can rewrite `seat_layout`), this silently reassigns seats under live bookings. | source |
| C13 | **Migration failures do not stop startup.** The whole script is one `try/except` that prints and exits 0; `start.sh` launches uvicorn regardless. *(SEC #19.)* | source |
| C14 | **Passengers cannot see cancelled bookings.** `list_bookings` filters passengers to paid-or-pending only — cancelled and failed history is invisible in the app. | source |
| C15 | **`get_payment` skips its ownership check when the booking is missing** (`if booking and …`). | source |

---

## Performance and capacity

Measured on the isolated stack, 120 trips on the search date.

| Load | p50 | max | Throughput |
|------|----:|----:|-----------:|
| 1 request | 323 ms | — | — |
| 5 concurrent | 1.25 s | 1.28 s | 3.9 req/s |
| 10 concurrent | 2.54 s | 2.62 s | 3.8 req/s |
| 20 concurrent | 5.25 s | 5.34 s | 3.7 req/s |
| 40 concurrent | 7.65 s | 9.89 s | 4.0 req/s |

**The platform's total search capacity is ~4 requests/second and does not improve with concurrency.**
`list_trips` runs four sequential queries *per trip* inside a Python loop (vehicle, reviews, route,
conductor, plus bookings), so cost is linear in trips and every request holds a pooled connection for
its duration. Scaling measured at 2.0–2.3 ms per trip: 405 trips → 800 ms, 1005 trips → 2.35 s.

**Search load degrades everything else**, because all endpoints share one 30-connection pool:

| Journey | Platform idle | 30 concurrent searchers |
|---------|--------------:|------------------------:|
| View my bookings | 63 ms | **5,114 ms** (81×) |
| Conductor manifest | 6 ms | 328 ms (55×) |
| Open seat map | 17 ms | 431 ms (25×) |
| OTP send | 27 ms | 101 ms |

A burst of concurrent searching causes congestive collapse: requests queue behind the threadpool and
the pool, and recovery takes minutes. It is not a connection *leak* — connections do drain, verified —
but there is no request timeout, no queue bound, and no pagination anywhere to limit the damage.

Other measured limits:

- **`phone/check` and `phone/login` load the entire `users` table into Python on every call.** At 11
  users: 2.8 ms. At 5,011 users: **155.7 ms — 55× slower**. This is on the login path. *(P3.)*
- `GET /admin/users` returned **5,011 records** in one unpaginated response.
- `GET /notifications/fcm-status` dumps every user (5,011 rows). *(SEC #11.)*
- `GET /admin/analytics/revenue?days=20000` runs 20,000 sequential aggregates — **11.6 s**, unbounded.
- `vehicle_location_history` has no retention policy. 3 vehicles over 8 light days produced 5,891 rows
  / 1.28 MB; 50 buses streaming 1 fix/s for 10 h/day is ~1.8 M rows/day. *(P6.)*
- The backend **must** run single-process — three module-level socket managers and the OTP store.

---

## Mobile app

- **The live seat map never connects.** `screens/seat_selector_screen.dart:42` hard-codes
  `ws://127.0.0.1:8000/api/v1/trips/ws/$tripId`. On a real phone this always fails, and the failure is
  swallowed by a `debugPrint`. The 4-second polling timer in `_startSyncTimer` is the only thing
  keeping the seat map current — so the feature *appears* to work while the entire real-time path is
  dead. Every other socket in the app correctly uses `buildWebSocketUrl(settings.wsBaseUrl, …)`.
- **The payment WebView matches on path only**, not host (`path.endsWith('/api/v1/payments/result/success')`).
  Any host serving that path would display success. Impact is limited — the booking state is re-read
  from the server immediately after — but it should be host-checked.
- **JWTs are stored in plaintext `SharedPreferences`** alongside name, NIC, gender and phone.
  *(SEC #17.)* On the admin side the token sits in `localStorage`.
- `flutter analyze` could not be run — Flutter is not installed on this host. Mobile findings are from
  source reading only.

## Admin dashboard

- `npm run lint` — clean apart from **12 warnings** (11 × `react-hooks/exhaustive-deps`, 1 fast-refresh).
  `tsc -b` — clean.
- **`NotificationDrawer.tsx` and `SettingsPage.tsx` hard-code `wss://api.seaty.hashnate.com`**, so a
  dev server's live notification feed points at production.
- **`LiveMapPage.tsx` is a mock** — three hard-coded buses animated on a canvas, routed and linked in
  the sidebar with nothing indicating it is not real. An operator will believe they are watching their
  fleet.

## Website

Clean. Leaflet is loaded from unpkg **with SRI integrity hashes** — good practice. The QR code from
`api.qrserver.com` encodes only `https://seaty.lk`, no personal data. A delete-account page exists,
satisfying App Store guideline 5.1.1(v). Two minor items: `fix_image.html` is a stray internal logo
tool served publicly (unlinked from robots/sitemap), and the site vhost sets no `X-Frame-Options`.

## Build and supply chain

- **Not one dependency is pinned.** `requirements.txt` lists 14 bare package names, so every rebuild
  pulls the current latest of FastAPI, SQLAlchemy, Pydantic, Starlette and python-jose. The running
  image has `starlette 1.6.0`, `fastapi 0.141.1`, `pydantic 2.13.4`. A rebuild can silently change
  production behaviour, and there is no lockfile to audit or roll back to. *(SEC #21.)*
- **CI builds the mobile app only.** No backend job — no tests, no lint, no typecheck, no dependency
  scan. Signing secrets are handled correctly through GitHub secrets.
- The backend container **runs as root**; `docker-compose.yml` declares no healthchecks.

---

## Corrections to existing documentation

Four claims in the current docs are provably wrong. They matter because they misdirect effort — two
warn about dangers that do not exist, and one understates a live risk.

1. **"A fresh deploy will not boot correctly"** — ARCHITECTURE.md, DATA_MODEL.md ("The fresh-deploy
   blocker"), DEPLOYMENT.md, CLAUDE.md all state that `users.fcm_token` is missing from `schema.sql`
   and `migrate_db.py`. **It is present**, at `schema.sql:49`, and so is `token_version` (line 50).
   A fresh volume built from `database/Dockerfile` booted cleanly, migrated, and served requests —
   this audit ran entirely on one. The blocker does not exist.

2. **"Deleting a trip or a schedule destroys paid bookings and payments"** — CODE_QUALITY.md C3,
   README, CLAUDE.md. **It does not.** The delete raises `NotNullViolation` and returns 500; the
   trip, the booking and the payment all survive intact (verified row counts). The data is
   accidentally safe. The real defect is the opposite one: operators can never delete a booked trip
   and receive an unexplained 500 (C3 above).

3. **"Not taking money yet · `PAYMENT_MODE` is `off`"** — README. The deployed configuration is
   `ENVIRONMENT=production` with **`PAYMENT_MODE=live`**, against real Bancstac credentials.
   `TEST_OTP_ACCOUNTS` (2 numbers) and `PAYMENT_MOCK_ACCOUNTS` (1 number) are both populated —
   documented as "clear before public launch". `PAYMENT_TEST_CHARGE_LKR` is correctly empty.

4. **`POST /payments/webhook`** is documented in API.md as a public endpoint with no signature
   verification. **It no longer exists in the code.** The whole Payments section of API.md is stale:
   it describes `SB-XXXXXXXXXXXX` transaction ids and states "No real gateway is integrated", which
   the Bancstac implementation contradicts.

Additionally, **8 live endpoints are absent from API.md**: `GET /trips/my-active`, the four
`/banners` routes, `POST /uploads/banner`, and `DELETE /auth/me` / `DELETE /auth/account`.

---

## Suggested order of work

**Before any real payment (B1–B7, S1–S3):**

1. Unique index on occupied `(trip_id, seat)` + row lock in `create_booking` — B1
2. Re-check cutoff **and** seat availability inside `finalise_payment` — B2, B5
3. Build a real refund path; make `cancel_booking` use it; stop promising refunds that do not
   happen — B3, B4
4. Validate `platform_settings` values on write, and make the fee read fail safe — B6
5. Rename the `status` parameter in `update_trip_status` — B7 (one line)
6. Company-scope `manifest`, `toggle-board` and `GET /companies/{id}` — S1, S2, S3

**Before public launch:**

7. Replace every inline role check with `RoleChecker`; scope schedules, and treat `NULL == NULL` as
   no match — S4, S5
8. Authenticate the seat WebSocket and validate the trip id — S6
9. Require an OTP to change a phone number; normalise before the uniqueness check — S10
10. Password minimum length; catch the >72-byte bcrypt error — S11
11. Delete both `public/log` endpoints; gate `/docs`; scope the default nginx vhost's rate
    limits — S12, S13, S9
12. Set explicit CORS origins — S8
13. Fix the mobile seat-map WebSocket URL; label or remove the mock Live Map
14. Pin every dependency; add a backend CI job that runs this audit's suite

**Before scale:**

15. Eager-load `list_trips` (one query, not 4×N) and paginate every list endpoint
16. Index and query `users` by normalised phone instead of `.all()`
17. Advisory lock or unique constraint on trip materialisation — C1
18. Retention policy for `vehicle_location_history`; bound the `days` parameter

---

*The 380-check suite used for this audit is reproducible against an isolated stack and is the natural
starting point for the regression tests this repository does not yet have.*
