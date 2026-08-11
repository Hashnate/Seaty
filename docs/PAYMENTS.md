# Payments

Seaty takes card payments through **Bancstac Paycenter Web 4.0** (Paycorp/CBC). This document
covers the integration design, why it is shaped the way it is, and what is still unresolved.

Status: **foundation built, live path blocked.** `PAYMENT_MODE` defaults to `off`; no deployment
takes payments until it is switched on deliberately.

---

## Modes

`PAYMENT_MODE` in `backend/.env`. There is deliberately **no `test`**.

| Mode | Behaviour | Where |
| ---- | --------- | ----- |
| `off` | Every gateway call raises `503`. Fails closed. | Default everywhere |
| `mock` | Local stand-in speaking Bancstac's shapes. No network, no money. | Development only — **refuses to load when `ENVIRONMENT=production`** |
| `live` | Real Paycenter calls, real money. | Production, once verified |

### Why there is no sandbox

Bancstac issues **one credential set per merchant**, and switches that account between test and
live **on their side**. Seaty's account (`14000228`, "Prime Business Network LKR") is currently
live, and repeatedly asking Bancstac to toggle it is not workable.

So `mock` replaces the vendor sandbox. It is not a second code path: the routers call the same
`init_payment` / `complete_payment` interface, and only the outbound HTTP client differs. That
exercises everything except the network hop — holds, confirmation, SMS, push, reconciliation,
declines, and the app's WebView hand-off.

### Simulating payments for specific accounts

`PAYMENT_MODE=mock` is platform-wide and barred in production, which left no way to exercise the
payment flow at all on the only deployment there is. Two things need one:

- **App Store and Play reviewers must complete a booking to review the app**, and cannot be charged.
- Internal testing, while Bancstac issues live-only credentials.

`PAYMENT_MOCK_ACCOUNTS` in `backend/.env` is a comma-separated list of phone numbers that always
get the simulated gateway, whatever `PAYMENT_MODE` says:

```
PAYMENT_MOCK_ACCOUNTS=0756371472,0771234567,0777140803
```

| Caller | Gateway |
| ------ | ------- |
| listed number | simulated — no charge, `payment_gateway = bancstac:mock` |
| anyone else | whatever `PAYMENT_MODE` is set to |

Deliberately separate from `TEST_OTP_ACCOUNTS`: a fixed OTP and a free payment are different
privileges and should be grantable apart.

A payment is always completed against the gateway that opened it —
`payments.payment_gateway` records `bancstac:mock` or `bancstac:live`, and `finalise_payment`
resolves from that. A simulated payment can never be completed against the real gateway, or the
reverse.

> [!WARNING]
> A listed number books for free. Keep the list to throwaway passenger accounts and **clear it
> before public launch** — it is on the [pre-launch checklist](DEPLOYMENT.md#pre-launch-checklist).

> [!IMPORTANT]
> The production host runs `ENVIRONMENT=production`, so platform-wide **`mock` cannot run there** — by design,
> since mock marks bookings paid without charging. Testing the payment flow needs a separate
> deployment with `ENVIRONMENT=development`, or the flow is only ever exercised against live.

Mock payments carry a `MOCK-` reqid prefix, so they can never be mistaken for a Bancstac
reference in the database.

---

## The Bancstac flow

Worth reading carefully, because it is **not** the webhook model most gateways use.

```
1. Seaty    → Bancstac   PAYMENT_INIT   clientId, amount in CENTS, returnUrl, clientRef
2. Bancstac → Seaty      reqid + paymentPageUrl        (session valid 30 min)
3. Seaty    → app        loads paymentPageUrl in an iframe / WebView
4. customer              enters card on Bancstac's page
5. Bancstac → browser    GET returnUrl?reqid=XXXX      ← carries NO payment result
6. Seaty    → Bancstac   PAYMENT_COMPLETE   clientId, reqid
7. Bancstac → Seaty      responseCode "00" = approved, txnReference, amount, masked card
8. Seaty    → app        receipt
```

**There is no server-to-server callback.** Step 5 is a browser redirect carrying only a `reqid`.

### Why that is still safe

The redirect carries no result, so a client cannot assert that it paid — it can only ask us to
re-check a `reqid`. The truth comes from step 6, our server asking Bancstac directly. That holds
provided all of the following:

- the booking is looked up by the **`reqid` we stored at step 1**, never by anything in the redirect
- the amount in the step 7 response is checked against what we computed
- `clientRef` is checked against the booking
- **only** `responseCode == "00"` counts as paid
- step 6 is idempotent — the return URL will be hit twice on a browser refresh

### The gap it creates

If the customer's browser or app dies between paying and being redirected, step 5 never fires, so
step 6 never runs: **card charged, booking not confirmed, seat released.** On mobile data this is
routine, not an edge case.

The replacement for the missing webhook is a **reconciliation sweeper**: a background task that
calls `PAYMENT_COMPLETE` for any payment still `pending` after ~2 minutes, retrying until it
resolves or the 30-minute session expires. This is required, not optional.

---

## Money handling

Bancstac works in **cents** (`paymentAmount: 400` is LKR 4.00); `bookings.total_price` is
`Numeric(10,2)`. Conversion happens once, at the boundary, through `Decimal` —
`payment_gateway.to_cents()`. No float ever touches an amount.

The charged total is `total_price + platform_fee`. Only `payments.amount` holds the combined
figure; see [DATA_MODEL.md](DATA_MODEL.md#payments).

---

## Authentication

None of this is in the technical guide. It comes from the team's working Bancstac integration in
**Prime Business Network**, which runs on the same merchant account.

```http
POST /rest/service/proxy HTTP/1.1
Host: paycorp-cbc.prod.aws.paycorp.lk
Content-Type: application/json
Cache-Control: no-cache
authtoken: <AuthToken>                                   ← raw, no scheme prefix
hmac: <HMAC-SHA256(body, HMAC_SECRET) as lowercase hex>

{"version":"1.5","msgId":"…","operation":"PAYMENT_INIT",…}
```

- **`clientIdHash` inside `requestData` stays `""`.** The header pair is what the gateway
  validates; the in-payload hash is unused in this mode.
- **No client certificate.** Plain one-way TLS, despite response code 22's wording about an "SSL
  CLIENT CERTIFICATE" — that code actually means the authtoken/clientId/HMAC triple doesn't match
  the merchant profile, the signed bytes don't match the body, or the source IP isn't whitelisted.

> [!IMPORTANT]
> **The HMAC must cover the byte-identical string that is sent as the body.** The adapter
> serialises once with `json.dumps(..., separators=(",", ":"))`, signs that string, and posts that
> same string. Re-serialising for the body — or letting a default separator insert a space — makes
> the signature invalid and the gateway rejects it with a bare credentials error that gives no
> hint as to why. This is the most common way this integration fails.

### Differences from the technical guide

Where the guide and the working integration disagree, the working integration wins — it is proven
against this merchant account.

| | Guide | Implemented |
| - | ----- | ----------- |
| `transactionAmount` | `totalAmount` set, `paymentAmount: 0` | **both** set to the amount |
| `extraData` | a string, `"{1,2,3}"` | an object |
| `requestDate` | `+0530` offset | UTC, `+0000` |
| `cssLocation1/2` | present, empty | omitted |

### Two response shapes

The guide (§6.9.1) documents `PAYMENT_COMPLETE` with nested `transactionAmount`, `creditCard` and
`txnReference`. The reference integration shows a flat `paymentAmount`, `maskedCardNumber` and
`transactionId`. The adapter reads **both** via `_first()` rather than betting on one and failing
silently against the other — worth revisiting once a real response has been captured, since only
one of them is what this endpoint actually returns.

## Still unresolved

- **`validateOnly`** — present in every sample, never explained. If it is a dry run it would allow
  verifying credentials and message format against live without moving money. Untested.
- **Refunds** — the guide documents no refund operation (only init, complete, tokenization,
  real-time). Likely portal-only. `POST /payments/{id}/refund` currently just flips database rows
  and moves no money, which becomes actively misleading once live; it should record an intent and
  say so until an API is confirmed.
- **IP whitelisting** — flagged as a possible cause of code 22. If Bancstac whitelists per merchant,
  this server's egress IP may need registering.

---

## Shared merchant account

Client ID `14000228` is labelled "Prime Business Network LKR" and is already in use by another
application. Consequences:

- Seaty bookings **settle into that merchant account**
- both apps' transactions appear in one Bancstac portal
- `clientRef` must distinguish them — Seaty prefixes its references accordingly

Separate settlement would need a second client ID from Bancstac.

---

## What replaces the old sandbox endpoints

`POST /payments/sandbox/complete/{txn}` and `/sandbox/fail/{txn}` were unauthenticated and could
confirm or cancel any booking by transaction ID ([SECURITY.md](SECURITY.md) #3, #27). They are
superseded by `mock` mode, which is guarded, logged, and impossible to enable in production. They
must be deleted as part of the live cutover — see the checklist in
[DEPLOYMENT.md](DEPLOYMENT.md#pre-launch-checklist).

## Testing without a sandbox

1. **`mock` mode** on a development deployment — covers the booking flow, declines, reconciliation
   and idempotency, for free. This is the day-to-day loop.
2. **`validateOnly` against live** — if Bancstac confirms it is a dry run, this is the only way to
   verify credentials and message format without a charge.
3. **Two or three small real transactions**, own card, refunded afterwards — the final proof
   before launch. Unavoidable with a live-only merchant account.
