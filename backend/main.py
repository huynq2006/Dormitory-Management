import pymysql
import os
from dotenv import load_dotenv

load_dotenv()

def transfer_student(student_id, new_room_id): 
    db_pass = os.getenv('DB_PASSWORD')
      
    connection = pymysql.connect(
        host='localhost',
        user='root',
        port=3306,
        password=db_pass,
        database='dormitory_management',
        cursorclass=pymysql.cursors.DictCursor
    )
        
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
        print(f"Error code: {e.args[0]}")
        print(f"Error message: {e.args[1]}")
        # print(f"Chi tiết lỗi: {e}")

    finally:
        if connection:   # check before close
            connection.close()

# Example: Room 101 has the capacity of 2
# Result 
transfer_student(3, 101)