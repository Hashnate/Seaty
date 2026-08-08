import datetime

# Seaty only operates within Sri Lanka, which has used a single fixed UTC+5:30
# offset with no DST since 1996 - a fixed offset avoids any dependency on the
# system tzdata database being present in the container image.
SRI_LANKA_TZ = datetime.timezone(datetime.timedelta(hours=5, minutes=30))


def now_sl() -> datetime.datetime:
    """Current time as a Sri Lanka-aware datetime."""
    return datetime.datetime.now(SRI_LANKA_TZ)


def to_sl(dt: "datetime.datetime | None") -> "datetime.datetime | None":
    """Interpret a naive datetime as Sri Lanka local time, or convert an aware
    one to Sri Lanka local time. Naive values only ever come from wall-clock
    input (a schedule's departure time, a client-submitted trip time) that was
    always meant as Sri Lanka local time, never UTC."""
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=SRI_LANKA_TZ)
    return dt.astimezone(SRI_LANKA_TZ)
