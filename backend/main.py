import pymysql
import os
from db_helper import get_master_connection

def transfer_student(student_id, new_room_id): 
    connection = get_master_connection()
    
    if not connection:
        return False, "Can't connect to database"    
    
    try:
        with connection.cursor() as cursor:
            sql_check = "SELECT room_id FROM contracts WHERE student_id = %s AND status = 'active'"
            cursor.execute(sql_check, (student_id,))
            result = cursor.fetchone()
            
            if result:
                current_room = result['room_id'] 
                
                if new_room_id == current_room:
                    return False, f"Student {student_id} is already in room {new_room_id}"
            
            cursor.callproc('sp_transfer_room', [student_id, new_room_id])
            
            connection.commit()
            return True, f"Transfer student with ID {student_id} to room {new_room_id}"

    except pymysql.MySQLError as e:
        if connection:   #  check before rollback
            connection.rollback()

        error_args = getattr(e, "args", ())
        error_code = error_args[0] if len(error_args) > 0 else "Unknown"
        error_message = error_args[1] if len(error_args) > 1 else str(e)
        
        print("Transfer failed")
        print(f"Error code: {error_code}")
        print(f"Error message: {error_message}")

    finally:
        if connection:   # check before close
            connection.close()

# Example: Room 101 has the capacity of 2
# Result 
if __name__ == "__main__":
    transfer_student(3, 101)
from db_helper import fetch_data, execute_write

def test_database_routing():
    print("STARTING DATABASE ROUTING TEST (READ/WRITE SPLIT)...\n")

    # TEST 1: Testing WRITE flow (Routing to Master)
    print("[TEST 1]: Attempting to WRITE data (Master)...")
    try:
        insert_query = """
        INSERT INTO audit_log (actor, action, detail) 
        VALUES (%s, %s, %s)
        """
        # Secure parameterized input against SQL Injection
        log_id = execute_write(insert_query, ('system_test', 'TEST_ROUTING', 'Testing write routing to Master'))
        print(f"WRITE SUCCESSFUL! Created new log entry with ID = {log_id}\n")
    except Exception as e:
        print(f"WRITE FAILED! Error: {e}\n")

    # TEST 2: Testing READ flow (Routing to Slave)
    print("[TEST 2]: Attempting to READ data (Slave)...")
    try:
        # Retrieve the total number of rooms as per project requirements
        select_query = "SELECT COUNT(*) as total_rooms FROM rooms"
        result = fetch_data(select_query)
        print(f"READ SUCCESSFUL! Result from DB: {result}\n")
    except Exception as e:
        print(f"READ FAILED! Error: {e}\n")

if __name__ == "__main__":
    test_database_routing()
