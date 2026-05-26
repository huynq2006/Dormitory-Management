import os
import pymysql
from urllib.parse import urlparse
from dotenv import load_dotenv
from datetime import datetime
import calendar

# Load environment variables from .env (once)
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '..', '.env'))

def _get_connection(url_env):
    """Open and return a PyMySQL connection described by an environment variable."""
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
    except pymysql.MySQLError as e:
        print(f"[SLAVE READ ERROR]: {e}")
        raise Exception(f"Database Read Error: {e}")
    except Exception as e:
        print(f"[SYSTEM ERROR] Unexpected error during read operation: {e}")
        raise Exception(f"SYSTEM Error: {e}")
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
    except pymysql.MySQLError as e:
        if conn:
            conn.rollback() # Rollback immediately if an error occurs to maintain data integrity
        print(f"[MASTER WRITE ERROR]: {e}")
        raise Exception(f"Database Write Error: {e}")
    except Exception as e:
        if conn:
            conn.rollback()
        print(f"[SYSTEM ERROR] Unexpected error during write operation: {e}")
        raise Exception(f"SYSTEM Error: {e}")
        
    finally:
        if conn:
            conn.close()

def fetch_rooms():
    """
    Query room list (for dashboard/frontend).
    """
    return fetch_data("SELECT * FROM rooms")

def fetch_overdue():
    """
    Fetch all overdue invoices.
    """
    query = """
        SELECT * FROM invoices 
        WHERE paid_status = 'overdue' 
           OR (paid_status = 'unpaid' AND due_date < CURDATE())
    """
    return fetch_data(query)

def generate_monthly_invoices():
    """Call the stored procedure to generate invoices for the current month."""
    today = datetime.today()
    first_day_of_month = f"{today.year}-{today.month:02d}-01"

    query = "CALL sp_generate_monthly_invoices(%s, %s)"
    return execute_write(query, (None, first_day_of_month))

def fetch_current_month_invoices():
    """Fetch this month's invoices."""
    today = datetime.today()
    first_day_of_month = f"{today.year}-{today.month:02d}-01"
    
    query = "SELECT * FROM invoices WHERE month = %s"
    return fetch_data(query, (first_day_of_month,))

def transfer_student(student_id, new_room_id):
    """Call the stored procedure to transfer a student to a new room, effective at the end of the current month."""
    today = datetime.today()
    last_day = calendar.monthrange(today.year, today.month)[1]
    effective_date = f"{today.year}-{today.month:02d}-{last_day:02d}"
    
    query = "CALL sp_transfer_room(%s, %s, %s)"
    return execute_write(query, (student_id, new_room_id, effective_date))

def fetch_student_info(student_code):
    """
    Fetch student personal information and their contract details by student code.
    """
    query = """
        SELECT 
            c.contract_id, 
            c.room_id, 
            r.building,
            c.start_date, 
            c.end_date, 
            c.status AS contract_status, 
            CONCAT(s.first_name, ' ', s.last_name) AS full_name, 
            s.gender, 
            s.email, 
            s.phone
        FROM students s
        LEFT JOIN contracts c ON s.student_id = c.student_id
        LEFT JOIN rooms r ON c.room_id = r.room_id
        WHERE s.student_code = %s
        ORDER BY c.start_date DESC
    """
    return fetch_data(query, (student_code,))

def assign_room_to_student(student_id, room_id):
    """
    Assign an inactive student (status=0) to a room.
    Calls sp_assign_room which:
      - Validates the student is inactive and room is available
      - Sets student status from 0 to 1 (active)
      - Creates a new active contract starting today
    """
    query = "CALL sp_assign_room(%s, %s)"
    return execute_write(query, (student_id, room_id))

def fetch_inactive_students():
    """
    Fetch all inactive students (status = 0).
    """
    query = """
        SELECT 
            student_id, 
            student_code, 
            CONCAT(first_name, ' ', last_name) AS full_name, 
            gender, 
            email, 
            phone, 
            status
        FROM students
        WHERE status = 0
    """
    return fetch_data(query)

