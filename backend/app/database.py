from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.config import settings

# The pool is sized explicitly rather than left at SQLAlchemy's 5 + 10 default,
# which capped the whole platform at 15 simultaneous checkouts. `pool_pre_ping`
# discards connections the database or an intermediary dropped while idle -
# without it the first query after an idle spell fails with a stale-connection
# error - and `pool_recycle` retires them before that can happen.
#
# Sizing this is only safe because nothing holds a connection for the lifetime
# of a socket any more; see `session_scope`.
engine = create_engine(
    settings.DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True,
    pool_recycle=1800,
)

# Create sessionmaker
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Declarative Base
Base = declarative_base()

# Dependency to get db session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# The same lifecycle as `get_db`, for code that cannot use dependency
# injection: WebSocket handlers and the background schedulers in `main.py`.
#
#     with session_scope() as db:
#         ...
#
# Open one around the shortest span of work that needs it, and **never** for
# the lifetime of a socket. A Session holds its pooled connection from its
# first query until commit/rollback/close, so a handler that authenticates once
# and then waits in `receive_text()` keeps a connection checked out - and an
# idle transaction open on the server - for as long as the user stays signed
# in. That is what used to make the connection pool, not the hardware, the
# limit on how many people could be signed in at once.
session_scope = contextmanager(get_db)
