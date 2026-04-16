import pymysql
import os
try:
     from .db_helper import get_connection
except ImportError:
     from db_helper import get_connection

def transfer_student(student_id, new_room_id): 
    connection = get_connection()
    if connection is None:
         raise ConnectionError("Failed to establish a database connection.")
        
    if not connection:
        return False, "Can't connect to the correct database."
        
    try:
        with connection.cursor() as cursor:
            sql_check = "SELECT room_id FROM contracts WHERE student_id = %s AND status = 'active'"
            cursor.execute(sql_check, (student_id,))
            result = cursor.fetchone()
            
            if result:
                current_room = result['room_id'] 
                
                if new_room_id == current_room:
                    print(f"Student {student_id} is already in room {new_room_id}")
                    return
            
            cursor.callproc('sp_transfer_room', [student_id, new_room_id])
            
        connection.commit()
        print("Transfer successful")
        print(f"Transfer student with ID {student_id} to room {new_room_id}")

    except pymysql.MySQLError as e:
        if connection:   #  check before rollback
            connection.rollback()

        print("Transfer failed")
        print(f"Error's detail: {e}")

    finally:
        if connection:   # check before close
            connection.close()

# Example: Room 101 has the capacity of 2
# Result 
transfer_student(3, 101)