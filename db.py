from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor

from config import DB_HOST, DB_NAME, DB_PASSWORD, DB_PORT, DB_USER


def get_connection():
    return psycopg2.connect(
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
    )


@contextmanager
def get_cursor(dict_cursor: bool = False):
    connection = None
    cursor = None
    try:
        connection = get_connection()
        cursor_factory = RealDictCursor if dict_cursor else None
        cursor = connection.cursor(cursor_factory=cursor_factory)
        yield connection, cursor
        connection.commit()
    except Exception:
        if connection:
            connection.rollback()
        raise
    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()
