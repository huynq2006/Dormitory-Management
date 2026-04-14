import pymysql
import os
from dotenv import load_dotenv

load_dotenv()

def get_connection(): 
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