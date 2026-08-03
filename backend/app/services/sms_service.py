import logging
import urllib.parse
import urllib.request
import json
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

def send_sms(to_phone: str, message: str) -> bool:
    """
    Send an SMS using the Notify.lk Gateway API.
    API Specs:
    Endpoint: https://app.notify.lk/api/v1/send
    Params: user_id, api_key, sender_id, to, message
    """
    formatted_to = format_phone_number(to_phone)
    if not formatted_to:
        logger.error(f"Cannot send SMS: invalid phone number '{to_phone}'")
        return False

    params = {
        "user_id": settings.NOTIFYLK_USER_ID,
        "api_key": settings.NOTIFYLK_API_KEY,
        "sender_id": settings.NOTIFYLK_SENDER_ID,
        "to": formatted_to,
        "message": message,
    }

    url = f"{settings.NOTIFYLK_API_URL}?{urllib.parse.urlencode(params)}"
    logger.info(f"Sending SMS to {formatted_to} via Notify.lk Gateway...")

    try:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": "Seaty-Backend/1.0", "Accept": "application/json"},
            method="GET",
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            res_body = response.read().decode("utf-8")
            logger.info(f"Notify.lk response ({response.status}): {res_body}")
            return response.status == 200
    except Exception as e:
        logger.error(f"Failed to send SMS via Notify.lk to {formatted_to}: {e}")
        return False
