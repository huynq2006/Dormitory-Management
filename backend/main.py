import pymysql

def transfer_student(student_id, new_room_id):
    try:    
        connection = pymysql.Connection(
            host='localhost',
            user='root',
            password='3306',
            database='dormitory_management',
            cursorclass=pymysql.cursors.DictCursor  # returns results as dict
        )

        with connection.cursor() as cursor:
            # Gọi stored procedure
            cursor.callproc('sp_transfer_room', [student_id, new_room_id])

        # Nếu không lỗi → commit
        connection.commit()
        print("✅ Transfer successful")

    except pymysql.MySQLError as e:
        # Rollback nếu có lỗi
        connection.rollback()

        # In mã lỗi + message từ MySQL
        print("Transfer failed")
        print(f"Error code: {e.args[0]}")
        print(f"Error message: {e.args[1]}")

    finally:
        connection.close()
        
        
transfer_student(1, 103)