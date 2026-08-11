"""Create or reset a platform admin. The only way an admin account comes into
existence.

No API endpoint can mint an admin: /auth/register is admin-only and pinned to
"owner", phone signup is pinned to "passenger", and /conductors hardcodes
"conductor". That is deliberate (docs/SECURITY.md #2) - and it means this script
is the sole path, including the recovery path if the last admin is locked out.

Usage, from the repo root:

    docker compose exec backend python create_admin.py ops@example.com "Ops Team"

The password is read from the terminal, never passed as an argument (arguments
land in shell history and in `docker inspect`). Re-running for an existing email
resets that account's password and promotes it to admin, after confirmation.

Pass --allow-weak-password to skip the length minimum. Only reasonable for a
throwaway development credential: /auth/login has no rate limiting or lockout
(docs/SECURITY.md #32), so a guessable admin password is guessable in one try.
"""

import getpass
import sys
import uuid

from app import auth, models
from app.database import SessionLocal

MIN_PASSWORD_LENGTH = 12


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--allow-weak-password"]
    allow_weak = "--allow-weak-password" in sys.argv

    if len(args) != 2:
        print(__doc__)
        return 2

    email = args[0].strip().lower()
    full_name = args[1].strip()
    if "@" not in email or not full_name:
        print("A valid email and a non-empty name are required.")
        return 2

    password = getpass.getpass("Password: ")
    if len(password) < MIN_PASSWORD_LENGTH:
        if not allow_weak:
            print(f"Password must be at least {MIN_PASSWORD_LENGTH} characters.")
            print("Pass --allow-weak-password to override (development only).")
            return 1
        print(f"WARNING: password is under {MIN_PASSWORD_LENGTH} characters. "
              f"Change it before this deployment is public.")
    if password != getpass.getpass("Confirm password: "):
        print("Passwords do not match.")
        return 1

    db = SessionLocal()
    try:
        existing = db.query(models.User).filter(models.User.email == email).first()
        if existing:
            print(f"{email} already exists with role '{existing.role}'.")
            if input("Reset its password and set role=admin? [y/N] ").strip().lower() != "y":
                print("Aborted.")
                return 1
            existing.hashed_password = auth.get_password_hash(password)
            existing.role = "admin"
            existing.full_name = full_name
            db.commit()
            print(f"Updated {email} -> admin.")
            return 0

        db.add(models.User(
            id=uuid.uuid4(),
            email=email,
            hashed_password=auth.get_password_hash(password),
            full_name=full_name,
            role="admin",
        ))
        db.commit()
        print(f"Created admin {email}.")
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
