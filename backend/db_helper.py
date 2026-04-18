import pymysql
import os
from dotenv import load_dotenv

load_dotenv()

def _get_connection(host_env):
    """
    Internal private function to initialize a standard database connection.
    Retrieves credentials dynamically from environment variables.
    """
    try:
        db_host = os.getenv('DB_HOST')
        db_user = os.getenv('DB_USER')
        db_port = int(os.getenv('DB_PORT', 3306))
        db_name = os.getenv('DB_NAME')
        db_pass = os.getenv('DB_PASSWORD')
        
        return pymysql.connect(
            host=db_host,
            user=db_user,
            port=db_port,
            password=db_pass,
            database=db_name,
            cursorclass=pymysql.cursors.DictCursor
        )
        
    except pymysql.MySQLError as e:
        print(f"Lỗi kết nối Database: {e}")
        return None

def get_slave_connection():
    """Returns a connection to the Read-Only Replica (Slave)."""
    return _get_connection('DB_SLAVE_HOST')

def get_master_connection():
    """Returns a connection to the Primary Database (Master)."""
    return _get_connection('DB_MASTER_HOST')

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
