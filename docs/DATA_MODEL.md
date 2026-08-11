# Data model

Reference for the Postgres schema as it exists at commit `3b43d6a`. Column types, defaults, and
constraints below were read from the **running database** (`information_schema`,
`pg_constraint`, `pg_indexes`), not from the DDL files — because the three DDL sources disagree
and only the live database is authoritative. See [Schema drift](#schema-drift) for what each
source actually produces.

[ARCHITECTURE.md](ARCHITECTURE.md#data-model) has the relationship sketch and the design
rationale; this document is the field-level reference and the state machines.

---

## Tables

Seventeen tables. UUID primary keys throughout, `NUMERIC(10,2)` for money, `TIMESTAMPTZ` for all
timestamps, Postgres arrays for seat lists, `JSONB` for anything shaped.

### `users`

The single identity table for all four roles.

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `email` | text | no | | `UNIQUE`. Phone-registered users get a synthetic `{phone}@seaty.lk` |
| `hashed_password` | text | no | | bcrypt. Phone users share one hard-coded plaintext — see [SECURITY.md](SECURITY.md) |
| `full_name` | text | no | | |
| `phone_number` | text | yes | | Stored **as entered**; matching normalises to the last 9 digits in Python |
| `nic_number` | text | yes | | National ID |
| `gender` | text | yes | | Drives the seat-map gender colouring |
| `role` | text | no | `'passenger'` | `CHECK IN ('passenger','owner','admin','conductor')` |
| `company_id` | uuid → `bus_companies` | yes | | `ON DELETE SET NULL`. Scopes owners and conductors |
| `fcm_token` | **varchar** | yes | | Push token. Present in the live DB **only because it was added by hand** — see [Schema drift](#schema-drift) |
| `created_at` / `updated_at` | timestamptz | no | `now()` | `updated_at` maintained by trigger |

Indexes: `users_pkey`, `users_email_key` (unique), `idx_users_company`, `idx_users_phone`.
`idx_users_phone` is never used — every phone lookup loads the whole table and compares in Python.

### `bus_companies`

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `id` | uuid | no | `gen_random_uuid()` |
| `name` | text | no | |
| `registration_number` | text | yes | `UNIQUE` |
| `contact_email`, `contact_phone`, `logo_url`, `address` | text | yes | |
| `is_active` | boolean | no | `true` |
| `created_at` / `updated_at` | timestamptz | no | `now()` |

Only admins create companies. Deactivating one hides it from passenger listings but does not stop
its trips or bookings.

### `vehicles`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `owner_id` | uuid → `users` | no | | `ON DELETE CASCADE` |
| `company_id` | uuid → `bus_companies` | yes | | `ON DELETE SET NULL`. **Nullable, and that is the root of the `None == None` authorisation bug** |
| `name` | text | no | | |
| `registration_number` | text | no | | `UNIQUE` |
| `type` | text | no | `'bus'` | `CHECK IN ('bus','train','other')` |
| `seat_layout` | jsonb | no | | See [JSONB shapes](#jsonb-shapes) |
| `total_seats` | integer | no | | Not validated against `seat_layout` |
| `amenities` | text[] | no | `'{}'` | |
| `is_verified` | boolean | no | `false` | Admin approval gate; reset to `false` on any edit |
| `document_urls` | text[] | no | `'{}'` | Operator paperwork. **Returned to every authenticated user** by `GET /vehicles` |
| `contact_phone` | text | yes | | Shown to passengers as "Bus Tel" |
| `main_image_url` | text | yes | | |
| `gallery_image_urls` | text[] | yes | `'{}'` | Capped at 5 in the router, not the schema |
| `created_at` / `updated_at` | timestamptz | no | `now()` | |

Indexes: pkey, unique on registration, `idx_vehicles_company`, `idx_vehicles_owner`.

### `routes`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `origin`, `destination` | text | no | | Free text, no place table |
| `stops` | jsonb | no | `'[]'` | Ordered intermediate stops |
| `total_distance` | numeric(6,2) | no | | km |
| `estimated_duration` | interval | no | | Written from `estimated_duration_seconds` |
| `created_at` | timestamptz | no | `now()` | |

Origin/destination matching is substring-based and case-insensitive, performed in Python
(`find_stop_position` in `routes/trips.py`), so it is not indexable and "Colombo" matches
"Colombo Fort".

### `trip_schedules`

Recurring templates. Concrete `trips` are materialised from these lazily.

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `vehicle_id` | uuid → `vehicles` | no | | `ON DELETE CASCADE` |
| `route_id` | uuid → `routes` | no | | `ON DELETE CASCADE` |
| `departure_time` / `arrival_time` | **time** (no tz) | no | | Sri Lanka wall clock. Arrival < departure means overnight |
| `price_per_seat` | numeric(10,2) | no | | Copied onto each generated trip |
| `schedule_type` | text | no | `'daily'` | `daily` \| `weekdays` \| `weekends` \| `custom`. **Not constrained** |
| `custom_days` | integer[] | yes | `'{}'` | 0 = Monday … 6 = Sunday |
| `effective_from` | date | no | `CURRENT_DATE` | |
| `effective_until` | date | yes | | `NULL` = open-ended |
| `is_active` | boolean | no | `true` | |
| `conductor_id` | uuid → `users` | yes | | `ON DELETE SET NULL`. Propagated to future trips on update |
| `created_at` / `updated_at` | timestamptz | no | `now()` | |

Indexes: primary key only. `vehicle_id` and `conductor_id` are unindexed despite being the join
and filter columns for `GET /schedules` and every trip-materialisation pass.

> **Deleting a schedule deletes its trips** — `cascade="all, delete-orphan"` in `models.py` —
> which cascades to bookings and payments. See [CODE_QUALITY.md](CODE_QUALITY.md) C3.

### `bus_overrides`

Swap in a replacement vehicle for one schedule on one date.

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `id` | uuid | no | `gen_random_uuid()` |
| `schedule_id` | uuid → `trip_schedules` | no | `ON DELETE CASCADE` |
| `override_date` | date | no | |
| `replacement_vehicle_id` | uuid → `vehicles` | no | `ON DELETE CASCADE` |
| `reason` | text | yes | |
| `created_at` | timestamptz | no | `now()` |

Primary key only — no index and **no unique constraint** on `(schedule_id, override_date)`, though
the router enforces one-per-date by deleting any existing row first.

### `trips`

A concrete, bookable journey.

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `vehicle_id` | uuid → `vehicles` | no | | `ON DELETE CASCADE` |
| `route_id` | uuid → `routes` | no | | `ON DELETE CASCADE` |
| `schedule_id` | uuid → `trip_schedules` | yes | | `ON DELETE SET NULL`. `NULL` for one-off trips |
| `departure_time` / `arrival_time` | timestamptz | no | | Written as Sri Lanka-aware |
| `price_per_seat` | numeric(10,2) | no | | Snapshot; editing it does not reprice existing bookings |
| `status` | text | no | `'scheduled'` | `CHECK IN ('scheduled','ongoing','completed','cancelled')` |
| `boarded_seats` | text[] | no | `'{}'` | Seat labels the conductor has scanned |
| `conductor_id` | uuid → `users` | yes | | `ON DELETE SET NULL` |
| `created_at` / `updated_at` | timestamptz | no | `now()` | |

Indexes: `idx_trips_vehicle`, `idx_trips_route`, `idx_trips_departure`, `idx_trips_status`.
**No index on `schedule_id`** and **no unique constraint on `(schedule_id, departure_time)`**,
which is what allows duplicate materialisation under concurrency.

### `bookings`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `trip_id` | uuid → `trips` | no | | `ON DELETE CASCADE` — deleting a trip deletes the booking |
| `passenger_id` | uuid → `users` | no | | `ON DELETE CASCADE` |
| `selected_seats` | text[] | no | | Max 6, enforced in the router |
| `total_price` | numeric(10,2) | no | | Fare only — **excludes** `platform_fee` |
| `platform_fee` | numeric(10,2) | no | `0` | Set at booking, recomputed at payment initiation |
| `payment_status` | text | no | `'pending'` | `CHECK IN ('pending','awaiting_payment','paid','failed','refunded')` |
| `booking_status` | text | no | `'pending'` | `CHECK IN ('pending','confirmed','cancelled','completed','expired')` |
| `passenger_details` | jsonb | yes | | Primary passenger + guests, see below |
| `created_at` / `updated_at` | timestamptz | no | `now()` | `created_at` doubles as the hold-timeout clock |

Indexes: `idx_bookings_trip`, `idx_bookings_passenger`, `idx_bookings_status`.

The amount actually charged is `total_price + platform_fee`; only `payments.amount` stores the
combined figure.

### `payments`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `booking_id` | uuid → `bookings` | no | | `ON DELETE CASCADE`. One booking may have several rows |
| `payment_gateway` | text | no | `'sandbox'` | Read from the `payment_gateway` platform setting |
| `gateway_transaction_id` | text | yes | | `SB-` + 12 hex. **Not unique**, and looked up by this value |
| `amount` | numeric(10,2) | no | | Fare **+** platform fee |
| `platform_fee` | numeric(10,2) | no | `0` | |
| `currency` | text | no | `'LKR'` | |
| `status` | text | no | `'pending'` | `CHECK IN ('pending','processing','completed','failed','refunded')` |
| `payment_url` | text | yes | | Sandbox: the relative completion path |
| `paid_at`, `refunded_at` | timestamptz | yes | | Written as **naive UTC** |
| `gateway_response` | jsonb | yes | | Sandbox marker or raw gateway payload |
| `created_at` | timestamptz | no | `now()` | |

Indexes: `idx_payments_booking`, `idx_payments_status`. Refunds are bookkeeping only — no money
moves, because no real gateway is wired up.

### `seat_holds`

Soft locks taken while the passenger pays.

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `trip_id` | uuid → `trips` | no | | `ON DELETE CASCADE` |
| `user_id` | uuid → `users` | no | | `ON DELETE CASCADE` |
| `seat_labels` | text[] | no | | |
| `expires_at` | timestamptz | no | | `now + seat_hold_duration_minutes` (default 10), written **naive UTC** |
| `is_released` | boolean | no | `false` | |
| `created_at` | timestamptz | no | `now()` | |

Indexes: `idx_seat_holds_trip`, `idx_seat_holds_expires`.

Rows are never deleted. A hold stops blocking a seat when `is_released` flips **or** `expires_at`
passes, because every availability read filters on both — which is why the absent cleanup job
does not break seat availability.

### `notifications`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | `gen_random_uuid()` | |
| `user_id` | uuid → `users` | no | | `ON DELETE CASCADE` |
| `title` | text | no | | |
| `message` | text | no | | The 30-minute reminder embeds `Booking ID: {uuid}` and is de-duplicated with `LIKE` against it |
| `type` | text | no | | `booking` \| `trip_ongoing` \| `trip_cancelled` \| `trip_rescheduled` \| `trip_reminder` \| `verification` \| `system`. **Not constrained** |
| `booking_id` | uuid → `bookings` | yes | | `ON DELETE SET NULL`. Deep-link target |
| `vehicle_id` | uuid → `vehicles` | yes | | `ON DELETE SET NULL`. Deep-link target |
| `is_read` | boolean | no | `false` | |
| `created_at` | timestamptz | no | `now()` | |

**Primary key only** — no index on `user_id`, which is the sole filter on every read. Also has the
only two live RLS policies in the schema, both inert.

### `platform_settings`

Key/value configuration, all values stored as text and parsed at the call site.

| Key | Live value | Read by |
| --- | ---------- | ------- |
| `commission_percentage` | `3.0` | booking + payment fee calculation |
| `commission_fixed_fee` | `25.00` | booking + payment fee calculation |
| `seat_hold_duration_minutes` | `10` | seat holds, payment initiation, pending-booking timeout |
| `payment_gateway` | `sandbox` | recorded on each payment row |
| `currency` | `LKR` | not read by any code path |
| `support_phone` | `0262237803` | confirmation SMS footer, ticket screen |
| `trip_tz_fix_applied` | `true` | leftover marker from a reverted migration |

`PUT /admin/settings/{key}` accepts any string with no per-key validation, so a non-numeric
`commission_percentage` makes `float()` raise on **every** booking and payment.

### `vehicle_locations`

Latest known position, one row per vehicle.

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `vehicle_id` | uuid → `vehicles` | no | primary key, `ON DELETE CASCADE` |
| `latitude`, `longitude` | **double precision** | no | |
| `speed`, `heading` | numeric(5,2) | yes | |
| `updated_at` | timestamptz | no | `now()` |

`models.py` declares latitude/longitude as `Numeric`; both DDL sources use `DOUBLE PRECISION`.
Harmless today, but the ORM and the database disagree about the type.

### `vehicle_location_history`

Append-only breadcrumb trail, one row per accepted GPS fix.

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `id` | uuid | no | `gen_random_uuid()` |
| `vehicle_id` | uuid → `vehicles` | no | `ON DELETE CASCADE` |
| `latitude`, `longitude` | double precision | no | |
| `speed`, `heading` | numeric(5,2) | yes | |
| `recorded_at` | timestamptz | no | `now()` |

Indexed on `(vehicle_id, recorded_at)`. **Nothing reads this table** — no endpoint queries it —
and there is no retention policy. 4,750 rows from three test vehicles at the time of writing.

### `reviews`

| Column | Type | Null | Default | Notes |
| ------ | ---- | ---- | ------- | ----- |
| `id` | uuid | no | **none** | Generated in Python, not by the database |
| `vehicle_id` | uuid → `vehicles` | no | | `ON DELETE CASCADE`, indexed |
| `user_id` | uuid → `users` | no | | `ON DELETE CASCADE` |
| `booking_id` | uuid → `bookings` | yes | | `ON DELETE SET NULL`. **Not unique** — the one-review-per-booking rule is Python-only |
| `passenger_name` | **varchar** | no | | Caller-supplied, falls back to the account name |
| `rating` | integer | no | | 1–5, validated by Pydantic only — **no `CHECK`** |
| `comment` | text | yes | | |
| `is_verified` | boolean | no | `true` | Always true; nothing sets it false |
| `created_at` | timestamptz | **yes** | none | Python-side default |

The odd column types and missing defaults are the signature of a table created by
`Base.metadata.create_all` rather than by SQL — see below.

### `user_favourites`

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `id` | uuid | no | `gen_random_uuid()` |
| `user_id` | uuid → `users` | no | `ON DELETE CASCADE` |
| `schedule_id` | uuid → `trip_schedules` | yes | `ON DELETE CASCADE` |
| `vehicle_id` | uuid → `vehicles` | no | `ON DELETE CASCADE` |
| `created_at` | timestamptz | no | `now()` |

`UNIQUE (user_id, vehicle_id, schedule_id)` — but Postgres treats `NULL`s as distinct, so a
vehicle can be favourited repeatedly with a `NULL` `schedule_id`.

### `hero_banners`

| Column | Type | Null | Default |
| ------ | ---- | ---- | ------- |
| `id` | uuid | no | `gen_random_uuid()` |
| `image_url` | text | no | |
| `title`, `subtitle` | text | yes | |
| `sort_order` | integer | no | `0` |
| `is_active` | boolean | no | `true` |
| `created_at` / `updated_at` | timestamptz | no | `now()` |

Indexed on `(is_active, sort_order)`. Public read, admin write. Deleting a banner does not delete
the uploaded image from the uploads volume.

---

## State machines

### `bookings.booking_status`

```
                    POST /bookings
                          │
                          ▼
                     ┌─────────┐   payment completed    ┌───────────┐
                     │ pending │───────────────────────▶│ confirmed │
                     └─────────┘                        └───────────┘
                       │     │                            │       │
   hold window elapsed │     │ payment failed /           │       │ all seats scanned
   (created_at + N min)│     │ cancelled by passenger     │       ▼
                       │     ▼                            │  ┌───────────┐
                       │  ┌───────────┐                   │  │ completed │
                       │  │ cancelled │◀──────────────────┘  └───────────┘
                       │  └───────────┘   cancel / refund       ▲
                       ▼                                        │
                  ┌─────────┐   departure passed,               │
                  │ expired │◀──────────────────────────────────┘
                  └─────────┘   not fully scanned
```

Who performs each transition:

| Transition | Actor |
| ---------- | ----- |
| → `pending` | `POST /bookings` |
| `pending` → `confirmed` | payment completion (sandbox endpoint or webhook) |
| `pending` → `expired` | `_auto_update_booking_statuses`, on read, after the hold window |
| `pending`/`confirmed` → `cancelled` | `POST /bookings/{id}/cancel`, sandbox fail, webhook fail, admin refund |
| `confirmed` → `completed` | `POST /trips/{id}/toggle-board` once every seat on the booking is scanned; also both auto-expiry paths |
| `confirmed` → `expired` | `auto_expire_bookings_scheduler` (60 s tick) and `_auto_update_booking_statuses`, once departure has passed |

Two components implement the last two rows independently and disagree at the edges — see
[CODE_QUALITY.md](CODE_QUALITY.md) C5. There is no state-transition validation anywhere: any
handler can set any value the `CHECK` constraint permits.

**Which statuses occupy a seat**: `OCCUPIED_BOOKING_STATUSES = ("confirmed", "completed")`
([`models.py:12`](../backend/app/models.py#L12)). `pending`, `cancelled`, and `expired` bookings
free their seats.

### `bookings.payment_status`

```
pending ──▶ awaiting_payment ──▶ paid ──▶ refunded
   │               │
   └───────────────┴──▶ failed
```

`pending` → `awaiting_payment` happens in `POST /payments/initiate`. Note that `paid` is a
separate axis from `booking_status`: `get_unavailable_seats` requires **both**
`booking_status IN ('confirmed','completed')` **and** `payment_status = 'paid'`, while the
`booked_seats` field on trip responses only checks the former.

### `trips.status`

```
scheduled ──▶ ongoing ──▶ completed
     │            │
     └────────────┴──▶ cancelled
```

Set only by `PATCH /trips/{id}/status`, manually, by an owner/conductor/admin. Nothing advances it
automatically — a trip that has departed and arrived stays `scheduled` unless somebody presses the
button. `ongoing` and `cancelled` fan out notifications to every confirmed passenger; `cancelled`
tells them "a refund has been initiated", which nothing actually does.

Booking is blocked when status is `completed` or `cancelled`, and independently by the 30-minute
pre-departure cutoff.

### Seat hold lifecycle

```
POST /seat-holds ──▶ active ──┬── expires_at passes ──▶ inert (row remains)
                              ├── is_released = true  ──▶ inert
                              └── payment completes   ──▶ released, seat now permanently booked
```

A seat is unavailable if it appears in a paid confirmed/completed booking **or** in a hold that is
neither released nor expired. Bookings win on overlap. Every hold write first releases the same
user's other holds on that trip, so a user has at most one live hold per trip.

### Trip materialisation

```
GET /trips?date=D
      │
      ├── D within [today, today+5] ?
      │        │
      │        yes ──▶ for each active schedule matching D's weekday:
      │                    exists trip(schedule_id, departure within D)?
      │                        no ──▶ apply bus_override if any ──▶ INSERT trip ──▶ COMMIT
      │
      └──▶ SELECT trips departing on D  (+ in-progress overnight runs, for staff)
```

The generator honours `schedule_type`, `effective_from`/`effective_until`, `is_active`, and
overnight arrival times (arrival before departure ⇒ next day). It runs on a **read** endpoint,
commits inside the loop, and has no uniqueness guard.

---

## JSONB shapes

**`vehicles.seat_layout`**

```json
{ "seats": [ { "row": 1, "col": 0, "label": "1" }, { "row": 1, "col": 1, "label": "2" } ] }
```

`label` is the join key to `bookings.selected_seats`, `trips.boarded_seats`, and
`seat_holds.seat_labels`. `col == 2` is the aisle in the generator that backfills missing layouts.
`migrate_db.py` renumbers every label to `"1".."N"` in array order on every boot — see
[CODE_QUALITY.md](CODE_QUALITY.md) C4.

**`bookings.passenger_details`**

```json
{
  "primary": { "name": "…", "gender": "male", "phone": "…" },
  "guests":  [ { "name": "…", "gender": "female", "phone": "…", "seat": "12" } ]
}
```

The primary passenger implicitly takes `selected_seats[0]`; guests take `seat` if present, else
`selected_seats[i+1]`. This is the source for the conductor manifest and for the seat-map gender
colouring — which is served **unauthenticated** by `GET /seat-holds/trip/{id}`.

**`routes.stops`**

```json
[ { "name": "Kalutara", "offset_minutes": 45, "distance_km": 42 } ]
```

Only `name` is read (substring-matched for origin/destination search). Ordering in the array
defines the direction check.

**`payments.gateway_response`** — either `{"sandbox": true, "message": "…", "completed_at": "…"}`
or whatever the webhook caller supplied, stored verbatim and unvalidated.

---

## Schema drift

Three sources of DDL, and they do not agree. This is the single most important thing to know
before changing the schema.

| Source | Runs when | What it does |
| ------ | --------- | ------------ |
| `backend/schema.sql` | Only on **first boot of an empty `db` volume** (baked into the image at `/docker-entrypoint-initdb.d/`) | Creates 15 tables, indexes, `updated_at` triggers, RLS policies |
| `Base.metadata.create_all` | Every backend start ([`main.py:10`](../backend/app/main.py#L10)) | Creates **missing tables only**. Never adds a column to an existing table |
| `backend/migrate_db.py` | Every backend start (via `start.sh`) | Ad-hoc `ALTER`s and 3 `CREATE TABLE IF NOT EXISTS`, all inside one swallowing `try` |

Coverage per table:

| Table | `schema.sql` | `migrate_db.py` | `models.py` |
| ----- | :----------: | :-------------: | :---------: |
| bus_companies, users, vehicles, routes, trip_schedules, bus_overrides, trips, bookings, payments, seat_holds, platform_settings, notifications, vehicle_locations | ✅ | — | ✅ |
| hero_banners | ✅ | ✅ | ✅ |
| vehicle_location_history | ✅ | ✅ | ✅ |
| user_favourites | ❌ | ✅ | ✅ |
| **reviews** | ❌ | ❌ | ✅ |

`reviews` therefore only ever comes from `create_all`, which is why its columns are `varchar`
instead of `text`, its `id` has no database default, and its `created_at` is nullable — while
every hand-written table gets `gen_random_uuid()` and `now()`.

### The fresh-deploy blocker

**`users.fcm_token` is in `models.py` and in neither DDL source.** On a fresh volume:

1. `schema.sql` creates `users` without the column.
2. `create_all` sees the table exists and does nothing.
3. `migrate_db.py` never mentions it.
4. Every query touching `fcm_token` — login, `/auth/me`, any notification send — fails with
   `UndefinedColumn`.

The live database has it (verified: it is present, as `character varying`, unlike every
neighbouring `text` column) because somebody added it by hand. Until it is in both files, a
rebuild from scratch does not boot correctly. Interim fix:

```bash
docker compose exec db psql -U postgres -d seaty \
  -c "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;"
```

### Adding a column, correctly

1. Add it to `models.py`.
2. Add a guarded `ALTER TABLE … ADD COLUMN IF NOT EXISTS` to `migrate_db.py`, **inside its own
   `try`** (an unguarded statement that fails aborts every later step — the outer `try` swallows
   it and the backend still starts).
3. Add it to `schema.sql` so fresh volumes match.
4. Verify: `docker compose logs backend | grep -i migration`.

Adding a **table** only needs steps 1 and 3, since `create_all` will create it — but the column
types will then differ from the hand-written ones, as `reviews` demonstrates.

---

## Row-level security

`schema.sql` enables RLS on most tables and defines policies against a Supabase-style `auth.uid()`,
backed by a local shim reading `request.jwt.claim.sub`. The backend connects as the `postgres`
superuser, which bypasses RLS entirely, and never sets that setting. **The policies are enabled
and completely inert.** All access control lives in Python. See [SECURITY.md](SECURITY.md) #20.

## Missing constraints worth adding

| Constraint | Prevents |
| ---------- | -------- |
| `UNIQUE (schedule_id, departure_time)` on `trips` | Duplicate materialisation under concurrency |
| `UNIQUE (booking_id)` on `reviews` | Double reviews via a check-then-insert race |
| `UNIQUE (gateway_transaction_id)` on `payments` | Ambiguous lookup by transaction ID |
| `CHECK (rating BETWEEN 1 AND 5)` on `reviews` | Out-of-range ratings from any non-Pydantic writer |
| `CHECK` on `trip_schedules.schedule_type` | Silent no-match schedules that generate nothing |
| `CHECK` on `notifications.type` | Unroutable notification types in the app |
| Normalised-phone unique index on `users` | Two accounts on one phone in the same role |
| `NOT NULL` on `vehicles.company_id` | The `None == None` authorisation bypass |
