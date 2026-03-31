import pymysql

def transfer_student(student_id, new_room_id):   
    connection = pymysql.Connection(
        host='localhost',
        user='root',
        password='061411wowwi%',
        port=3306,
        database='dormitory_management',
        cursorclass=pymysql.cursors.DictCursor
    )
        
    try:
        with connection.cursor() as cursor:
            cursor.callproc('sp_transfer_room', [student_id, new_room_id])

        connection.commit()
        print("Transfer successful")

    except pymysql.MySQLError as e:
        if connection:   #  check before rollback
            connection.rollback()

        print("Transfer failed")
        print(f"Error code: {e.args[0]}")
        print(f"Error message: {e.args[1]}")

    finally:
        if connection:   # check before close
            connection.close()
            
transfer_student(1, 101)