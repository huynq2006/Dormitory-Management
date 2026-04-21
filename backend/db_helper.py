import os
import pymysql
from dotenv import load_dotenv

# Load environment variables from .env (once)
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

def get_connection(host_env): # sửa hàm _get_connection thành get_connection để dễ sử dụng hơn
    """
    Internal private function to initialize a standard database connection.
    Retrieves credentials dynamically from environment variables.
    """
    return pymysql.connect(
        host=os.getenv(host_env),
        user='root',
        password=os.getenv('MYSQL_PASSWORD'),
        database=os.getenv('MYSQL_DATABASE'),
        port=int(os.getenv('DB_PORT', 3306)),
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )

def get_slave_connection():
    """Returns a connection to the Read-Only Replica (Slave)."""
    return get_connection('DB_SLAVE_HOST')

def get_master_connection():
    """Returns a connection to the Primary Database (Master)."""
    return get_connection('DB_MASTER_HOST')

def fetch_data(query, params=None):
    """
    READ data function (Routes to SLAVE).
    Used exclusively for read-only workloads such as SELECT statements.
    """
    conn = get_slave_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(query, params)
            result = cursor.fetchall()
            return result
    except Exception as e:
        print(f"[SLAVE READ ERROR]: {e}")
        raise e
    finally:
        conn.close()

def execute_write(query, params=None):
    """
    WRITE data function (Routes to MASTER).
    Used for transactions that modify data: INSERT, UPDATE, DELETE, CALL PROCEDURE.
    Includes built-in ACID transaction management (commit/rollback).
    """
    conn = get_master_connection()
    try:
        with conn.cursor() as cursor:
            cursor.execute(query, params)
        conn.commit() # Commit transaction if successful
        return cursor.lastrowid # Return the ID of the newly inserted row (if applicable)
    except Exception as e:
        conn.rollback() # Rollback immediately if an error occurs to maintain data integrity
        print(f"[MASTER WRITE ERROR]: {e}")
        raise e
    finally:
        conn.close()

def fetch_rooms():
    """
    Query room list (for dashboard/frontend).
    """
    return fetch_data("SELECT * FROM rooms")