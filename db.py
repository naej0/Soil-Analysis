import os
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor


def get_connection():
    database_url = os.getenv("DATABASE_URL")

    if database_url:
        if database_url.startswith("postgres://"):
            database_url = database_url.replace("postgres://", "postgresql://", 1)

        return psycopg2.connect(
            database_url,
            connect_timeout=10
        )

    return psycopg2.connect(
        dbname=os.getenv("PGDATABASE") or os.getenv("DB_NAME") or "postgres",
        user=os.getenv("PGUSER") or os.getenv("DB_USER") or "postgres",
        password=os.getenv("PGPASSWORD") or os.getenv("DB_PASSWORD") or "",
        host=os.getenv("PGHOST") or os.getenv("DB_HOST") or "127.0.0.1",
        port=os.getenv("PGPORT") or os.getenv("DB_PORT") or "5432",
        connect_timeout=10
    )


# Backward-compatible alias para sa mga old imports/calls
def get_db_connection():
    return get_connection()


@contextmanager
def get_cursor(dict_cursor=False):
    conn = get_connection()
    cursor = None
    try:
        if dict_cursor:
            cursor = conn.cursor(cursor_factory=RealDictCursor)
        else:
            cursor = conn.cursor()

        yield conn, cursor
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        if cursor:
            cursor.close()
        conn.close()