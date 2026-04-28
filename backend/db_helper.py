import os
import pymysql
from urllib.parse import urlparse
from dotenv import load_dotenv
from datetime import datetime
import calendar

# Load environment variables from .env (once)
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

def _get_connection(url_env):
    # Retrieve the complete database connection URL from environment variables
    db_url = os.getenv(url_env)
    
    if not db_url:
        raise ValueError(f"Error: {url_env} environment variable is missing!")

    # Parse the connection URL to extract individual credentials
    parsed = urlparse(db_url)

    # Establish and return the PyMySQL connection using extracted parameters
    try:
        return pymysql.connect(
            host=parsed.hostname,              # e.g., 'mysql-master'
            user=parsed.username,              # e.g., 'app_user'
            password=parsed.password,          # e.g., 'App_Pass@123'
            database=parsed.path.lstrip('/'),  # Remove the leading slash from the path
            port=parsed.port or 3306,          # Fallback to default MySQL port if missing
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor
        )
    except pymysql.Error as e:
        # Catch network/authentication errors early for clear logging
        print(f"[CONNECTION ERROR] Cannot connect to DB via {url_env}: {e}")
        raise e

def get_slave_connection():
    """Returns a connection to the Read-Only Replica (Slave)."""
    return _get_connection('DB_SLAVE_URL')

def get_master_connection():
    """Returns a connection to the Primary Database (Master)."""
    return _get_connection('DB_MASTER_URL')

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
        return [] 
    except Exception as e:
        print(f"[SYSTEM ERROR] Unexpected error during read operation: {e}")
        return []
    finally:
        # Ensure the connection exists before attempting to close it
        if conn:
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
        if conn:
            conn.rollback() # Rollback immediately if an error occurs to maintain data integrity
        print(f"[MASTER WRITE ERROR]: {e}")
        return None 
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"[SYSTEM ERROR] Unexpected error during write operation: {e}")
        return None
        
    finally:
        if conn:
            conn.close()

def fetch_rooms():
    """
    Query room list (for dashboard/frontend).
    """
    return fetch_data("SELECT * FROM rooms")

def fetch_overdue():
    query = """
        SELECT * FROM invoices 
        WHERE paid_status = 'overdue' 
           OR (paid_status = 'unpaid' AND due_date < CURDATE())
    """
    return fetch_data(query)

def generate_monthly_invoices():
    today = datetime.today()
    first_day_of_month = f"{today.year}-{today.month:02d}-01"

    query = "CALL sp_generate_monthly_invoices(%s, %s)"
    return execute_write(query, (None, first_day_of_month))

def fetch_current_month_invoices():
    """Print this month's invoice to the screen."""
    today = datetime.today()
    first_day_of_month = f"{today.year}-{today.month:02d}-01"
    
    query = "SELECT * FROM invoices WHERE month = %s"
    return fetch_data(query, (first_day_of_month,))

def transfer_student(student_id, new_room_id):
    today = datetime.today()
    last_day = calendar.monthrange(today.year, today.month)[1]
    effective_date = f"{today.year}-{today.month:02d}-{last_day:02d}"
    
    query = "CALL sp_transfer_room(%s, %s, %s)"
    return execute_write(query, (student_id, new_room_id, effective_date))
