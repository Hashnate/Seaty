"""Payment gateway abstraction.

One interface, three implementations, chosen by `PAYMENT_MODE`:

    off   DisabledGateway - every call raises 503. The default, and what a
          deployment runs until the integration is deliberately switched on.
    mock  MockGateway     - speaks the same shapes as Bancstac without any
          network call. Bancstac has no sandbox for this merchant account, so
          this is how the booking flow gets tested without spending money.
          Refuses to load when ENVIRONMENT=production.
    live  BancstacGateway - real Paycenter Web 4.0 calls, real money.

Callers only ever see `InitResult` / `CompleteResult`, so the routers contain no
gateway-specific branching and mock exercises the identical code path.

Amounts are handled in **cents** end to end. Bancstac's API is in cents
(`paymentAmount: 400` is LKR 4.00) and `bookings.total_price` is
`Numeric(10,2)`; converting once at the boundary keeps float rounding out of
money maths entirely.
"""

from __future__ import annotations

import datetime
import hashlib
import hmac
import json
import logging
import uuid
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Any, Optional

import httpx

from app.config import settings

logger = logging.getLogger(__name__)

# Bancstac's "approved" response code (technical guide §6.9.1). Everything else
# is a decline or an error - never treat an unrecognised code as success.
APPROVED_CODE = "00"

BANCSTAC_MSG_VERSION = "1.5"


class PaymentGatewayError(Exception):
    """Gateway could not be reached, or answered in a shape we don't accept."""


class PaymentGatewayUnavailable(PaymentGatewayError):
    """Payments are switched off for this deployment (PAYMENT_MODE=off)."""


@dataclass
class InitResult:
    """Outcome of PAYMENT_INIT — a payment session, not a payment."""
    reqid: str
    payment_page_url: str
    expires_at: Optional[str] = None
    raw: dict = field(default_factory=dict)


@dataclass
class CompleteResult:
    """Outcome of PAYMENT_COMPLETE — the authoritative result of the payment.

    `approved` is the only field a caller should branch on, and it is true only
    for an exact match on Bancstac's approval code.
    """
    approved: bool
    response_code: str
    response_text: str
    amount_cents: int
    currency: str
    txn_reference: Optional[str] = None
    client_ref: Optional[str] = None
    card_masked: Optional[str] = None
    card_type: Optional[str] = None
    auth_code: Optional[str] = None
    raw: dict = field(default_factory=dict)


def to_cents(amount: Decimal | float | int) -> int:
    """LKR to cents, rounded once, via Decimal.

    Bancstac takes integer cents. Doing this with floats is how you end up
    charging 1 cent less than you recorded.
    """
    return int((Decimal(str(amount)) * 100).quantize(Decimal("1")))


def _msg_envelope(operation: str, request_data: dict) -> dict:
    """Common Bancstac message wrapper (technical guide §6.5, §6.8)."""
    return {
        "version": BANCSTAC_MSG_VERSION,
        "msgId": str(uuid.uuid4()).upper(),
        "operation": operation,
        "requestDate": datetime.datetime.now(datetime.timezone.utc)
                               .strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
        "validateOnly": False,
        "requestData": request_data,
    }


def _first(data: dict, *paths, default=None):
    """Read the first present value among several possible locations.

    Bancstac's PAYMENT_COMPLETE response is documented one way in the technical
    guide (nested `transactionAmount` / `creditCard` / `txnReference`) and
    observed another way in a working integration (flat `paymentAmount`,
    `maskedCardNumber`, `transactionId`). Rather than bet on one shape and fail
    silently against the other, accept both.
    """
    for path in paths:
        node = data
        for key in (path if isinstance(path, tuple) else (path,)):
            if not isinstance(node, dict):
                node = None
                break
            node = node.get(key)
        if node not in (None, ""):
            return node
    return default


# =====================================================================
# Implementations
# =====================================================================
class DisabledGateway:
    """PAYMENT_MODE=off. Fails closed."""

    mode = "off"

    async def init_payment(self, **_: Any) -> InitResult:
        raise PaymentGatewayUnavailable("Online payment is not enabled on this deployment.")

    async def complete_payment(self, reqid: str) -> CompleteResult:
        raise PaymentGatewayUnavailable("Online payment is not enabled on this deployment.")


class MockGateway:
    """Local stand-in for Bancstac. No network, no money.

    Bancstac provides a single live-only credential set for this merchant, so
    there is no vendor sandbox to point at. This mode exists so the booking
    flow - holds, confirmation, SMS, push, reconciliation, decline handling -
    can be exercised end to end for free, on the same code path as live.

    The reqid is prefixed `MOCK-` so a mock payment is obvious in the database
    and can never be mistaken for a real Bancstac reference.
    """

    mode = "mock"

    # reqid -> session, so complete_payment can echo back the real amount and
    # clientRef. Without that the caller's amount-verification step would be
    # untested in mock, which is exactly the check most worth exercising.
    _sessions: dict[str, dict] = {}

    def __init__(self, allow_in_production: bool = False) -> None:
        # PAYMENT_MODE=mock is a platform-wide free-bookings switch, so it stays
        # barred in production. `allow_in_production` is only ever set for a
        # phone number explicitly listed in PAYMENT_MOCK_ACCOUNTS - bounded to
        # named test and store-review accounts rather than everybody.
        if not allow_in_production and settings.ENVIRONMENT.lower() in ("prod", "production"):
            raise RuntimeError(
                "PAYMENT_MODE=mock is not permitted when ENVIRONMENT=production. "
                "To simulate payments for specific test accounts, list their phone "
                "numbers in PAYMENT_MOCK_ACCOUNTS instead."
            )
        logger.warning("Payment gateway running in MOCK mode - no real payments are processed.")

    async def init_payment(
        self,
        *,
        amount_cents: int,
        currency: str,
        client_ref: str,
        return_url: str,
        comment: str = "",
        **_: Any,
    ) -> InitResult:
        reqid = f"MOCK-{uuid.uuid4().hex[:16]}"
        self._sessions[reqid] = {
            "amount_cents": amount_cents,
            "currency": currency,
            "client_ref": client_ref,
            "return_url": return_url,
            "outcome": "approve",
        }
        logger.warning("MOCK init_payment ref=%s amount=%s %s", client_ref, amount_cents, currency)
        return InitResult(
            reqid=reqid,
            # Served by our own router so the whole flow - the WebView
            # hand-off, the gateway redirect, the return handler - is exercised.
            payment_page_url=f"/api/v1/payments/mock/pay/{reqid}",
            raw={"mock": True, "amount_cents": amount_cents, "client_ref": client_ref},
        )

    @classmethod
    def set_outcome(cls, reqid: str, outcome: str) -> None:
        """Choose what the next complete_payment returns: approve | decline."""
        cls._sessions.setdefault(reqid, {
            "amount_cents": 0, "currency": "LKR", "client_ref": None, "return_url": "",
        })["outcome"] = outcome

    @classmethod
    def restore_session(cls, reqid: str, *, amount_cents: int, currency: str,
                        client_ref: str) -> None:
        """Re-prime a session from the caller's own record.

        Sessions live in process memory, so a backend restart between opening a
        payment and completing it would otherwise lose it and the payment would
        fail for no real reason - a restart mid-test is routine. The payment row
        holds everything needed, so the caller can hand it back.
        """
        if reqid not in cls._sessions:
            cls._sessions[reqid] = {
                "amount_cents": amount_cents,
                "currency": currency,
                "client_ref": client_ref,
                "return_url": "",
                "outcome": "approve",
            }

    async def complete_payment(self, reqid: str) -> CompleteResult:
        session = self._sessions.get(reqid)
        if session is None:
            # Unknown session: behave like the real gateway would - not approved.
            return CompleteResult(
                approved=False, response_code="26", response_text="UNKNOWN REQID (MOCK)",
                amount_cents=0, currency="LKR", raw={"mock": True, "reqid": reqid},
            )

        declined = session["outcome"] == "decline"
        return CompleteResult(
            approved=not declined,
            response_code=APPROVED_CODE if not declined else "51",
            response_text="TRANSACTION APPROVED (MOCK)" if not declined else "DECLINED (MOCK)",
            amount_cents=session["amount_cents"],
            currency=session["currency"],
            txn_reference=f"MOCKTXN{uuid.uuid4().hex[:12].upper()}",
            client_ref=session["client_ref"],
            card_masked="400000******0002",
            card_type="VISA",
            auth_code="000000",
            raw={"mock": True, "reqid": reqid, "outcome": session["outcome"]},
        )


class BancstacGateway:
    """Bancstac Paycenter Web 4.0 — live.

    Auth is a header pair, confirmed against a working integration on the same
    merchant account:

        authtoken:  <AuthToken>                      raw, no scheme prefix
        hmac:       HMAC-SHA256(body, HMAC_SECRET)   lowercase hex

    `clientIdHash` inside `requestData` stays an empty string; the headers are
    what the gateway validates. Standard one-way TLS - no client certificate,
    despite what response code 22's wording suggests.
    """

    mode = "live"

    def __init__(self) -> None:
        missing = [
            name for name, value in (
                ("BANCSTAC_ENDPOINT", settings.BANCSTAC_ENDPOINT),
                ("BANCSTAC_CLIENT_ID", settings.BANCSTAC_CLIENT_ID),
                ("BANCSTAC_AUTH_TOKEN", settings.BANCSTAC_AUTH_TOKEN),
                ("BANCSTAC_HMAC_SECRET", settings.BANCSTAC_HMAC_SECRET),
                ("BANCSTAC_RETURN_URL", settings.BANCSTAC_RETURN_URL),
            ) if not value
        ]
        if missing:
            raise RuntimeError(f"PAYMENT_MODE=live but not configured: {', '.join(missing)}")

    # -- transport ----------------------------------------------------------
    @staticmethod
    def sign(payload_str: str) -> str:
        """HMAC-SHA256 of the request body, lowercase hex."""
        return hmac.new(
            settings.BANCSTAC_HMAC_SECRET.encode("utf-8"),
            payload_str.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    async def _post(self, payload: dict) -> dict:
        # Serialised exactly once. The signature covers the byte sequence that
        # is actually sent - re-serialising for the body would let a stray
        # space invalidate the hmac, which is the classic way this integration
        # fails with a bare "invalid credentials".
        payload_str = json.dumps(payload, separators=(",", ":"))
        headers = {
            "Content-Type": "application/json",
            "Cache-Control": "no-cache",
            "authtoken": settings.BANCSTAC_AUTH_TOKEN,
            "hmac": self.sign(payload_str),
        }

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    settings.BANCSTAC_ENDPOINT, content=payload_str, headers=headers
                )
        except Exception as e:
            logger.error("Bancstac request failed: %s", e)
            raise PaymentGatewayError("Could not reach the payment gateway.") from e

        if resp.status_code != 200:
            # Never log the body at info level: it echoes request metadata.
            logger.error("Bancstac HTTP %s: %s", resp.status_code, resp.text[:500])
            raise PaymentGatewayError(f"Gateway returned HTTP {resp.status_code}")

        try:
            return resp.json()
        except Exception as e:
            logger.error("Bancstac returned non-JSON: %s", resp.text[:500])
            raise PaymentGatewayError("Gateway returned an unreadable response.") from e

    # -- operations ---------------------------------------------------------
    async def init_payment(
        self,
        *,
        amount_cents: int,
        currency: str,
        client_ref: str,
        return_url: str,
        comment: str = "",
        extra_data: Optional[dict] = None,
        **_: Any,
    ) -> InitResult:
        payload = _msg_envelope("PAYMENT_INIT", {
            "clientId": str(settings.BANCSTAC_CLIENT_ID),
            "clientIdHash": "",
            "transactionType": "PURCHASE",
            "transactionAmount": {
                # Both carry the amount. The technical guide's sample zeroes
                # paymentAmount, but the working integration sets both and is
                # the one proven against this merchant account.
                "totalAmount": amount_cents,
                "paymentAmount": amount_cents,
                "serviceFeeAmount": 0,
                "currency": currency,
            },
            "redirect": {
                "returnUrl": return_url,
                "cancelUrl": settings.BANCSTAC_CANCEL_URL or "",
                "returnMethod": "GET",
            },
            "clientRef": client_ref[:50],   # guide: 50 char max
            "comment": comment[:100],       # guide: 100 char max
            "tokenize": False,
            "useReliability": True,
            "extraData": extra_data or {},
        })

        body = await self._post(payload)
        data = (body or {}).get("responseData") or {}
        reqid, url = data.get("reqid"), data.get("paymentPageUrl")
        if not reqid or not url:
            logger.error(
                "Bancstac PAYMENT_INIT gave no session (code=%s): %s",
                body.get("responseCode"), str(data)[:300],
            )
            raise PaymentGatewayError("Gateway did not return a payment session.")

        return InitResult(
            reqid=str(reqid),
            payment_page_url=str(url),
            expires_at=data.get("expireAt"),
            raw=data,
        )

    async def complete_payment(self, reqid: str) -> CompleteResult:
        payload = _msg_envelope("PAYMENT_COMPLETE", {
            "clientId": str(settings.BANCSTAC_CLIENT_ID),
            "reqid": reqid,
        })
        body = await self._post(payload)
        data = (body or {}).get("responseData") or {}

        # Two documented shapes — see _first().
        amount_cents = int(_first(
            data, ("transactionAmount", "paymentAmount"), "paymentAmount",
            ("transactionAmount", "totalAmount"), default=0,
        ) or 0)

        code = str(_first(data, "responseCode", default="")
                   or body.get("responseCode", ""))

        return CompleteResult(
            approved=(code == APPROVED_CODE),
            response_code=code,
            response_text=str(_first(data, "responseText", default="") or ""),
            amount_cents=amount_cents,
            currency=str(_first(data, ("transactionAmount", "currency"), "currency",
                                default="LKR")),
            txn_reference=_first(data, "txnReference", "transactionId"),
            client_ref=data.get("clientRef"),
            card_masked=_first(data, ("creditCard", "number"), "maskedCardNumber"),
            card_type=_first(data, ("creditCard", "type"), "cardType"),
            auth_code=data.get("authCode"),
            raw=data,
        )


_GATEWAYS = {"off": DisabledGateway, "mock": MockGateway, "live": BancstacGateway}


def _normalise_phone(raw: str) -> str:
    """Last 9 digits, matching routes/auth.normalize_phone_digits.

    Duplicated rather than imported: routes import services, and the reverse
    would be a cycle.
    """
    digits = "".join(c for c in (raw or "") if c.isdigit())
    return digits[-9:] if len(digits) >= 9 else digits


def is_mock_account(phone: Optional[str]) -> bool:
    """Is this number on the simulated-payment allowlist?"""
    if not phone:
        return False
    allow = {
        _normalise_phone(p)
        for p in (settings.PAYMENT_MOCK_ACCOUNTS or "").split(",")
        if _normalise_phone(p)
    }
    return _normalise_phone(phone) in allow


def get_gateway(for_user: Any = None, force_mode: Optional[str] = None):
    """Pick the gateway for this request.

    `for_user` opts a listed test or store-review account into the simulated
    gateway without changing anything for real customers. `force_mode` is used
    when completing a payment, so it resolves against the gateway that created
    it - a mock payment must never be completed against the live gateway, or
    vice versa.

    Constructed per call rather than cached at import, so a misconfiguration
    surfaces as one failed request with a clear message rather than a container
    that will not boot.
    """
    if force_mode is None and for_user is not None and is_mock_account(
        getattr(for_user, "phone_number", None)
    ):
        logger.warning(
            "Simulated payment for allowlisted account %s - no real charge.",
            getattr(for_user, "phone_number", "?"),
        )
        return MockGateway(allow_in_production=True)

    mode = (force_mode or settings.PAYMENT_MODE or "off").strip().lower()
    impl = _GATEWAYS.get(mode)
    if impl is None:
        raise RuntimeError(
            f"Unknown PAYMENT_MODE '{mode}'. Expected one of: {', '.join(_GATEWAYS)}"
        )
    if impl is MockGateway and force_mode == "mock":
        # Completing a payment that a listed account created.
        return MockGateway(allow_in_production=True)
    return impl()
