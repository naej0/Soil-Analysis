from fastapi import HTTPException
from passlib.hash import pbkdf2_sha256

from db import get_cursor


def hash_password(password: str) -> str:
    return pbkdf2_sha256.hash(password)


def verify_password(plain_password: str, stored_password: str) -> bool:
    if not stored_password:
        return False
    if stored_password == plain_password:
        return True
    if stored_password.startswith("$pbkdf2-sha256$"):
        return pbkdf2_sha256.verify(plain_password, stored_password)
    return False


def register_user(payload) -> dict:
    with get_cursor() as (_, cursor):
        cursor.execute("SELECT id FROM users WHERE email = %s;", (payload.email,))
        existing_user = cursor.fetchone()
        if existing_user:
            raise HTTPException(status_code=400, detail="Email already registered")

        cursor.execute(
            """
            INSERT INTO users (full_name, email, password_hash)
            VALUES (%s, %s, %s)
            RETURNING id, full_name, email, role, created_at;
            """,
            (payload.full_name, payload.email, hash_password(payload.password)),
        )
        user = cursor.fetchone()

    return {
        "id": user[0],
        "full_name": user[1],
        "email": user[2],
        "role": user[3],
        "created_at": user[4],
    }


def login_user(payload) -> dict:
    with get_cursor() as (_, cursor):
        cursor.execute(
            """
            SELECT id, full_name, email, password_hash, role, created_at
            FROM users
            WHERE email = %s;
            """,
            (payload.email,),
        )
        user = cursor.fetchone()

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not verify_password(payload.password, user[3]):
        raise HTTPException(status_code=401, detail="Invalid password")

    return {
        "id": user[0],
        "full_name": user[1],
        "email": user[2],
        "role": user[4],
        "created_at": user[5],
    }
