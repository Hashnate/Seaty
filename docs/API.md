# API reference

Base URL: `https://api.seaty.hashnate.com/api/v1` (production) · `http://localhost:8025/api/v1`
(local, through the admin Nginx container).

Interactive OpenAPI docs are served at `/docs` and the raw schema at `/openapi.json`.

## Conventions

- **Auth**: `Authorization: Bearer <jwt>` on every endpoint marked with a role. Tokens come from
  `POST /auth/login` or `POST /auth/phone/login` and last 7 days.
- **IDs** are UUIDs. **Money** is `NUMERIC(10,2)` in LKR. **Timestamps** are ISO-8601.
- **Errors** are FastAPI's `{"detail": "..."}` with the usual 400/401/403/404/409 codes.
- The **Roles** column lists who may call the endpoint. "Any" means any authenticated user;
  "Public" means no token is required.

> [!CAUTION]
> Endpoints marked 🔓 are reachable without authentication and should not be. See
> [SECURITY.md](SECURITY.md).

---

## Authentication — `/auth`

| Method | Path                | Roles  | Notes                                                        |
| ------ | ------------------- | ------ | ------------------------------------------------------------ |
| POST   | `/auth/register`    | Admin  | Creates an **owner**. `role` is pinned to `"owner"`; any other value is a 422 |
| POST   | `/auth/login`       | Public | OAuth2 password form (`username` = email). Returns JWT        |
| POST   | `/auth/logout`      | Any    | Bumps `token_version`, invalidating every token issued to the caller |
| GET    | `/auth/me`          | Any    | Current user profile                                          |
| POST   | `/auth/otp/send`    | Public | 🔓 Unrated-limited. Dev environment always uses code `123456` |
| POST   | `/auth/otp/verify`  | Public | Verifies against an in-memory store; grants no token          |
| POST   | `/auth/phone/check` | Public | Does this phone exist, and under what role                    |
| POST   | `/auth/phone/register` | Public | 🔓 `otp_code` is optional — omit it and no OTP is checked  |
| POST   | `/auth/phone/login` | Public | Phone + role + `otp_code`. The code is verified server-side and consumed on success |
| PUT    | `/auth/profile`     | Any    | Update name, NIC, gender, phone                               |
| POST   | `/auth/change-password` | Any | Requires the current password                              |
| POST\|PUT | `/auth/fcm-token`, `/auth/me/fcm-token` | Any | Compatibility aliases for FCM registration |

OTP codes live in a **process-local dict** (`otp_store` in `routes/auth.py`), valid 5 minutes.
They are lost on restart and not shared between workers.

`POST /auth/login` returns `{access_token, token_type}`; `POST /auth/phone/login` also returns
`role`.

---

## Companies — `/companies`

| Method | Path                        | Roles       | Notes                              |
| ------ | --------------------------- | ----------- | ---------------------------------- |
| POST   | `/companies`                | admin       | Create operator                    |
| GET    | `/companies`                | Any         | List                               |
| GET    | `/companies/{id}`           | Any         | Detail, with nested fleet/stats    |
| PATCH  | `/companies/{id}`           | admin       | Update                             |
| PATCH  | `/companies/{id}/toggle`    | admin       | Activate / deactivate              |

## Vehicles — `/vehicles`

| Method | Path                      | Roles                    | Notes                                        |
| ------ | ------------------------- | ------------------------ | -------------------------------------------- |
| POST   | `/vehicles`               | owner, admin             | Created unverified; notifies all admins      |
| GET    | `/vehicles`               | Any                      | Admin: all · owner/conductor: own company · passenger: verified only |
| GET    | `/vehicles/{id}`          | Any                      | Unverified hidden from non-owners            |
| POST   | `/vehicles/{id}/approve`  | admin                    | Sets `is_verified`, notifies owner           |
| POST   | `/vehicles/{id}/reject`   | admin                    | Notifies owner                               |
| PATCH  | `/vehicles/{id}/booking`  | owner, admin             | `{enabled, reason}` — take the whole bus off sale |
| PUT    | `/vehicles/{id}`          | owner, admin             | Update                                       |
| DELETE | `/vehicles/{id}`          | owner, admin             | 409 if any trip on it has a paid booking     |

Unverified vehicles cannot have trips scheduled against them.

`is_verified` and `booking_enabled` are different things and both are enforced: the first is the
admin's document approval, the second is the operator's own reversible off switch. A verified bus
can still be off the road today.

## Reviews — `/vehicles/{vehicle_id}/reviews`

| Method | Path                              | Roles     | Notes                                |
| ------ | --------------------------------- | --------- | ------------------------------------ |
| GET    | `/vehicles/{id}/reviews`          | Any       | List + average rating summary        |
| POST   | `/vehicles/{id}/reviews`          | passenger | 1–5 stars plus optional comment      |

## Routes — `/routes`

| Method | Path            | Roles        | Notes                                                     |
| ------ | --------------- | ------------ | --------------------------------------------------------- |
| POST   | `/routes`       | admin        | Origin, destination, `stops` JSONB, distance, duration     |
| GET    | `/routes`       | Any          | List                                                       |
| GET    | `/routes/{id}`  | Any          | Detail                                                     |
| DELETE | `/routes/{id}`  | admin        | Delete                                                     |

## Trips — `/trips`

| Method | Path                       | Roles                   | Notes                                              |
| ------ | -------------------------- | ----------------------- | -------------------------------------------------- |
| POST   | `/trips`                   | owner, admin            | Vehicle must be verified and in your company        |
| GET    | `/trips`                   | Public (optional auth)  | Filters `?origin=&destination=&date=YYYY-MM-DD`     |
| GET    | `/trips/{id}`              | Public                  | Includes vehicle, route, rating, booked seats       |
| PUT    | `/trips/{id}`              | owner, admin            | Notifies passengers if departure time changes       |
| PATCH  | `/trips/{id}/status`       | owner, admin, conductor | `?status=scheduled\|ongoing\|completed\|cancelled`  |
| PATCH  | `/trips/{id}/booking`      | owner, admin            | `{enabled, reason}` — temporary off switch          |
| DELETE | `/trips/{id}`              | owner, admin            | 409 if any booking on the trip is paid               |
| GET    | `/trips/{id}/manifest`     | owner, admin, conductor | Per-seat passenger list for the conductor           |
| POST   | `/trips/{id}/toggle-board` | owner, admin, conductor | `?seat=&action=board\|unboard\|toggle`              |

Behaviours worth knowing:

- `GET /trips?date=` **writes to the database.** For any date within the next 5 days it
  materialises missing `trips` rows from active `trip_schedules`, honouring `bus_overrides`.
- Origin/destination matching is a substring search that also walks intermediate `stops`, and
  requires the origin to sort before the destination along the route.
- Boarding via `toggle-board` is rejected more than 30 minutes before departure.
- **A trip that is not on sale is omitted from `GET /trips` for passengers entirely.** Staff
  still receive it, with `sale_blocked_reason` set to the passenger-facing explanation.
- Conductors reach `/status` (but not `cancelled` or `scheduled`), `/manifest` and
  `/toggle-board`, and only for trips they are assigned to. Everything else on this router is
  owner/admin, company-scoped.

### The temporary off switch

Three levels, all reversible, all `PATCH … /booking` with `{"enabled": bool, "reason": str?}`:

| Path                            | Effect                                                       |
| ------------------------------- | ------------------------------------------------------------ |
| `/trips/{id}/booking`           | One instance                                                  |
| `/schedules/{id}/booking`       | A recurring service **including trips already generated**     |
| `/vehicles/{id}/booking`        | Every trip on that bus, present and future                    |

While off, the trip vanishes from passenger search, `GET /seat-holds/trip/{id}` returns
`booking_enabled: false` with an empty `available_seats`, and holds, bookings and payment
initiation are all refused with 409 and the reason. Existing bookings keep their seats and
tickets — this is *not* a cancellation. `PATCH /trips/{id}/status?status=cancelled` remains the
one-way door that voids bookings, notifies passengers, and queues refunds.

`app/services/availability.py` is the single evaluator, checked in this order: the
`bookings_enabled` platform setting → `bus_companies.is_active` → `vehicles.is_verified` →
`vehicles.booking_enabled` → `trip_schedules.booking_enabled` → `trips.booking_enabled` →
`trips.status`. First refusal wins and its message is what the passenger sees.

## Recurring schedules — `/schedules`

| Method | Path                                   | Roles        | Notes                                   |
| ------ | -------------------------------------- | ------------ | --------------------------------------- |
| POST   | `/schedules`                           | owner, admin | `daily`/`weekdays`/`weekends`/`custom`  |
| GET    | `/schedules`                           | owner, admin | Company-scoped for owners               |
| GET    | `/schedules/{id}`                      | owner, admin | Detail                                  |
| PUT    | `/schedules/{id}`                      | owner, admin | Update                                  |
| PATCH  | `/schedules/{id}/toggle`               | owner, admin | Activate / pause **future materialisation only** |
| PATCH  | `/schedules/{id}/booking`              | owner, admin | Temporary off switch, incl. generated trips |
| DELETE | `/schedules/{id}`                      | owner, admin | 409 if a trip under it has a paid booking |
| POST   | `/schedules/{id}/overrides`            | owner, admin | Swap vehicle for one date               |
| GET    | `/schedules/{id}/overrides`            | owner, admin | List                                    |
| DELETE | `/schedules/overrides/{override_id}`   | owner, admin | Remove                                  |

`custom_days` is an int array with `0 = Monday … 6 = Sunday`.

## Seat holds — `/seat-holds`

| Method | Path                        | Roles             | Notes                                          |
| ------ | --------------------------- | ----------------- | ---------------------------------------------- |
| POST   | `/seat-holds`               | passenger, admin  | 409 if any seat is booked or held. 10 min TTL   |
| GET    | `/seat-holds/trip/{trip_id}`| Public            | Booked / held / available seats + seat genders  |
| DELETE | `/seat-holds/{hold_id}`     | Any (owner of hold)| Manual release                                 |
| POST   | `/seat-holds/cleanup`       | admin             | Sweep expired holds; **not scheduled anywhere** |

Creating a hold releases any earlier hold the same user had on that trip. Hold duration comes
from the `seat_hold_duration_minutes` platform setting.

`GET /seat-holds/trip/{id}` also returns `seat_genders`, derived from `passenger_details` on
confirmed bookings, so the seat map can show who is sitting where.

## Bookings — `/bookings`

| Method | Path                      | Roles             | Notes                                              |
| ------ | ------------------------- | ----------------- | -------------------------------------------------- |
| POST   | `/bookings`               | passenger, admin  | Max 6 seats. Price computed server-side             |
| GET    | `/bookings`               | Any               | Scoped by role: own / company / assigned trips / all|
| GET    | `/bookings/{id}`          | Any               | Ownership and company checks applied                |
| POST   | `/bookings/{id}/cancel`   | passenger (own), admin | Releases holds, broadcasts `SEAT_RELEASED`     |

`passenger_details` is JSONB shaped `{"primary": {name, gender, phone}, "guests": [{name, gender,
phone, seat}]}`. Bookings start `pending`/`pending` and only become `confirmed`/`paid` through a
payment completion.

## Payments — `/payments`

| Method | Path                                   | Roles            | Notes                                        |
| ------ | -------------------------------------- | ---------------- | -------------------------------------------- |
| POST   | `/payments/initiate`                   | passenger, admin | Refreshes hold, creates payment, returns URL  |
| GET    | `/payments/{id}`                       | Any (own/admin)  | Status                                        |
| GET    | `/payments/booking/{booking_id}`       | Any (own/admin)  | All payments for a booking                    |
| POST   | `/payments/sandbox/complete/{txn_id}`  | Public           | 🔓 **Marks a booking paid with no auth**      |
| POST   | `/payments/sandbox/fail/{txn_id}`      | Public           | 🔓 Marks it failed, releases seats            |
| POST   | `/payments/webhook`                    | Public           | 🔓 No signature verification                  |
| POST   | `/payments/{id}/refund`                | admin            | Only for completed payments                   |

Total charged = `booking.total_price` + platform fee, where the fee is
`commission_percentage`% + `commission_fixed_fee` from `platform_settings`. Transaction IDs look
like `SB-XXXXXXXXXXXX`. No real gateway is integrated — `payment_gateway` in settings can be set
to `payhere` or `stripe` but nothing reads it beyond stamping the payment row.

## Conductors — `/conductors`

| Method | Path                    | Roles        | Notes                                            |
| ------ | ----------------------- | ------------ | ------------------------------------------------ |
| GET    | `/conductors`           | owner, admin | Company-scoped for owners                        |
| POST   | `/conductors`           | owner        | Creates a phone-auth user in the owner's company |
| DELETE | `/conductors/{id}`      | owner, admin | Company-scoped                                   |

## Favourites — `/favourites`

| Method | Path                  | Roles | Notes                                   |
| ------ | --------------------- | ----- | --------------------------------------- |
| POST   | `/favourites/toggle`  | Any   | Add/remove by vehicle (+ optional schedule) |
| GET    | `/favourites`         | Any   | Full objects                             |
| GET    | `/favourites/ids`     | Any   | ID list, for cheap UI state              |

## Notifications — `/notifications`

| Method | Path                              | Roles | Notes                                          |
| ------ | --------------------------------- | ----- | ---------------------------------------------- |
| GET    | `/notifications`                  | Any   | Own history, newest first                       |
| POST   | `/notifications/{id}/read`        | Any   | Mark one read                                   |
| POST   | `/notifications/read-all`         | Any   | Mark all read                                   |
| POST   | `/notifications/broadcast`        | admin | To a role or everyone                           |
| POST   | `/notifications/send-direct`      | admin | By `user_id` or `phone_number`                  |
| POST   | `/notifications/fcm-token`        | Any   | Register device token                           |
| GET    | `/notifications/fcm-status`       | admin | Diagnostics; lists every user and token state   |
| POST   | `/notifications/public/log`        | Public | 🔓 Client diagnostics — prints to server stdout |

`POST /api/v1/public/log` at the app root is a duplicate of the last one, added for native iOS
diagnostics. Both are unauthenticated log-injection sinks and should be removed before launch.

## Uploads — `/uploads`

| Method | Path                             | Roles        | Notes                            |
| ------ | -------------------------------- | ------------ | -------------------------------- |
| POST   | `/uploads/vehicle-main-image`    | owner, admin | 1 file, ≤5 MB, JPEG/PNG/WebP     |
| POST   | `/uploads/vehicle-gallery`       | owner, admin | ≤5 files; invalid ones skipped   |

Files are written to `UPLOAD_DIR` with UUID names and served from `/uploads/vehicles/{name}`
by FastAPI's `StaticFiles` mount. MIME type, extension, size, and resolved path are all checked.

## Admin — `/admin`

| Method | Path                        | Roles        | Notes                                        |
| ------ | --------------------------- | ------------ | -------------------------------------------- |
| GET    | `/admin/dashboard`          | admin, owner | Aggregate stats; owners get company-scoped   |
| GET    | `/admin/analytics/revenue`  | admin        | `?days=30`, one row per day                  |
| GET    | `/admin/settings`           | admin        | All platform settings                        |
| PUT    | `/admin/settings/{key}`     | admin        | Update one setting                           |
| GET    | `/admin/users`              | admin        | `?role=` filter                              |

Seeded settings: `commission_percentage` (3.0), `commission_fixed_fee` (25.00),
`seat_hold_duration_minutes` (10), `payment_gateway` (sandbox), `currency` (LKR).

---

## WebSockets

### Seat availability — `ws://…/api/v1/trips/ws/{trip_id}`

No authentication. Send any text to keep alive. Server pushes:

```json
{ "event": "SEAT_HELD" | "SEAT_RELEASED", "seats": ["3", "4"], "genders": {} }
```

### GPS tracking — `ws://…/api/v1/ws/tracking/{vehicle_id}?role=driver|passenger&token=<jwt>`

Drivers must be the vehicle owner, a conductor in the same company, or an admin; only one driver
socket per vehicle (a new one evicts the old). Drivers send:

```json
{ "latitude": 6.9271, "longitude": 79.8612, "speed": 45.0, "heading": 180.0 }
```

Passengers receive the last known location immediately on connect, then every driver update.
Each update is persisted to `vehicle_locations`.

### Notifications — `ws://…/api/v1/notifications/ws?token=<jwt>`

Authenticated per user. Server pushes full notification objects:

```json
{ "id": "...", "user_id": "...", "title": "...", "message": "...",
  "type": "booking", "is_read": false, "created_at": "..." }
```

`type` is one of `booking`, `trip_update`, `trip_reminder`, `verification`, `system`.

> All three managers keep sockets in process memory, so the backend must run as a **single
> process**. Scaling out requires a shared pub/sub layer first.
