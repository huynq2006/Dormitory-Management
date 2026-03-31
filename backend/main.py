import pymysql

def transfer_student(student_id, new_room_id):    
        connection = pymysql.Connection(
            host='localhost',
            user='root',
            port=3306,
            password='061411wowwi%',
            database='dormitory_management',
            cursorclass=pymysql.cursors.DictCursor  # returns results as dict
        )

        connected_cursor = connection.cursor() 
        try:
            with connected_cursor as cursor:
                cursor.callproc('sp_transfer_room', [student_id, new_room_id])

            # No error → commit
            connection.commit()
            print("Transfer successful")

        except pymysql.MySQLError as e:
            # Rollback if there's a error
            connection.rollback()

            # Print error and message from MySQL
            print("Transfer failed")
            print(f"Error code: {e.args[0]}")
            print(f"Error message: {e.args[1]}")
        
transfer_student(1, 101)