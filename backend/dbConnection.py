import pymysql
import os
from dotenv import load_dotenv

load_dotenv()

def get_connection(): 
    try:
        db_pass = os.getenv('DB_PASSWORD')
        
        return pymysql.connect(
            host='localhost',
            user='root',
            port=3306,
            password=db_pass,
            database='dormitory_management',
            cursorclass=pymysql.cursors.DictCursor
        )
        
    except pymysql.MySQLError as e:
        print(f"Lỗi kết nối Database: {e}")
        return None