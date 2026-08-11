import json
import logging
import time
import urllib.parse
import urllib.request
from typing import Tuple

from app.config import settings

logger = logging.getLogger(__name__)


def format_phone_number(raw_phone: str) -> str:
    """
    Format phone number to Sri Lankan international standard format (947XXXXXXXX).
    Examples:
    0771234567 -> 94771234567
    771234567  -> 94771234567
    +94771234567 -> 94771234567
    """
    if not raw_phone:
        return ""
    digits = "".join(c for c in raw_phone if c.isdigit())
    if digits.startswith("94") and len(digits) == 11:
        return digits
    elif digits.startswith("0") and len(digits) == 10:
        return "94" + digits[1:]
    elif len(digits) == 9 and digits.startswith("7"):
        return "94" + digits
    return digits


def send_sms(to_phone: str, message: str) -> Tuple[bool, str]:
    """Send an SMS through the Notify.lk gateway.

    Returns ``(ok, detail)``. `detail` is safe to log but not to show a user
    verbatim - it can carry gateway wording.

    Two things this deliberately does that the previous version did not:

    * **Reads the response body.** Notify.lk answers HTTP 200 with
      ``{"status": "error", ...}`` for a rejected send - out of credit, bad
      number, unapproved sender. Treating HTTP 200 as success meant a failed
      SMS was reported as sent and the user waited for a code that was never
      going to arrive.
    * **Logs at a level that is actually emitted, with timing.** These calls
      used to log at INFO while the root logger sat at WARNING, so the gateway's
      reply - the only record of whether a message was accepted - was discarded.

    Credentials go in the query string because that is what the vendor's API
    requires; they will appear in any intermediary's access log.
    """
    formatted_to = format_phone_number(to_phone)
    if not formatted_to:
        logger.error("SMS not sent: could not parse phone number %r", to_phone)
        return False, "invalid phone number"

    params = {
        "user_id": settings.NOTIFYLK_USER_ID,
        "api_key": settings.NOTIFYLK_API_KEY,
        "sender_id": settings.NOTIFYLK_SENDER_ID,
        "to": formatted_to,
        "message": message,
    }
    url = f"{settings.NOTIFYLK_API_URL}?{urllib.parse.urlencode(params)}"

    started = time.perf_counter()
    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Seaty-Backend/1.0", "Accept": "application/json"},
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            body = response.read().decode("utf-8")
            status = response.status
    except Exception as e:
        elapsed = (time.perf_counter() - started) * 1000
        logger.error("SMS to %s failed after %.0fms: %s", formatted_to, elapsed, e)
        return False, str(e)

    elapsed = (time.perf_counter() - started) * 1000

    ok, detail = False, body[:200]
    if status == 200:
        try:
            parsed = json.loads(body)
            ok = str(parsed.get("status", "")).lower() == "success"
            detail = str(parsed.get("data") or parsed.get("message") or body)[:200]
        except ValueError:
            detail = f"unparseable response: {body[:200]}"

    if ok:
        logger.info("SMS accepted by Notify.lk for %s in %.0fms (%s)",
                    formatted_to, elapsed, detail)
    else:
        logger.error("SMS REJECTED by Notify.lk for %s after %.0fms (HTTP %s): %s",
                     formatted_to, elapsed, status, detail)

    return ok, detail
