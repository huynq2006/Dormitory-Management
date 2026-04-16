import os
import pymysql
from faker import Faker
import random
from urllib.parse import urlparse

# Initialize Faker with Vietnamese locale to ensure culturally accurate mock data
fake = Faker('vi_VN')

def get_db_connection():
    # Retrieve the complete database connection URL from environment variables
    db_url = os.getenv('DB_MASTER_URL')
    
    if not db_url:
        raise ValueError("Error: DB_MASTER_URL environment variable is missing!")

    # Parse the connection URL to extract individual credentials
    parsed = urlparse(db_url)

    # Establish and return the PyMySQL connection using extracted parameters
    return pymysql.connect(
        host=parsed.hostname,              # e.g., 'mysql-master'
        user=parsed.username,              # e.g., 'app_user'
        password=parsed.password,          # e.g., 'App_Pass@123'
        database=parsed.path.lstrip('/'),  # Remove the leading slash from the path
        port=parsed.port or 3306,          # Fallback to default MySQL port if missing
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )

def seed_students(n=50):
    conn = get_db_connection()
    try:
        with conn.cursor() as cursor:
            inserted_count = 0
            while inserted_count < n:
                max_attempts = 5
                attempt = 0
                while attempt < max_attempts:
                    try:
                        # 1. Data Generation strictly conforming to the Database Schema
                        
                        # Generate student code format: 'SV' followed by 6 random digits
                        student_code = f"SV{random.randint(100000, 999999)}"
                        
                        # Separate first name and last name attributes
                        first_name = fake.first_name()
                        last_name = fake.last_name()
                        
                        # Randomly assign gender based on the defined ENUM constraints ('M', 'F', 'O')
                        gender = random.choice(['M', 'F', 'O'])
                        
                        # Generate a realistic date of birth for university demographic (18-25 years old)
                        dob = fake.date_of_birth(minimum_age=18, maximum_age=25)
                        
                        # Utilize the .unique property to prevent duplicate entry errors for UNIQUE keys
                        email = fake.unique.free_email()
                        phone = fake.unique.phone_number()[:20] # Truncate to satisfy VARCHAR(20) limit
                        
                        # 2. Execute Parameterized INSERT Query
                        sql = """
                        INSERT INTO students 
                        (student_code, first_name, last_name, gender, dob, email, phone) 
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """
                        cursor.execute(sql, (student_code, first_name, last_name, gender, dob, email, phone))
                        # Commit transaction sequentially
                        conn.commit()
                        inserted_count += 1
                        break  # Exit the retry loop on successful insertion

                    except pymysql.IntegrityError as ie:
                        # Catch and log schema constraint violations (e.g., duplicates, null values)
                        conn.rollback()
                        attempt += 1
                        print(f"Database Constraint Error: {ie}")
                
        print(f"Successfully inserted {n} students into the Master database.")
        
    except Exception as e:
        # Catch and log general runtime errors
        print(f"An error occurred during data generation: {e}")
        
    finally:
        # Ensure database resources are released safely
        conn.close()

if __name__ == "__main__":
    print("Starting the data generation process...")
    # Initialize batch insertion
    seed_students(100)