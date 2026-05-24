import sys
import os
# Add parent directory to path to allow importing from 'backend'
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from faker import Faker
from faker.providers import BaseProvider
from backend.db_helper import get_master_connection
import random
from datetime import date, timedelta
from unidecode import unidecode

class VietnameseNameProvider(BaseProvider):
    """
    Custom Faker provider to generate realistic Vietnamese first and last names.
    """
    def vn_first_name(self):
        first_names = [
            "An", "Anh", "Bình", "Bảo", "Cường", "Chi", "Chương", "Dũng", "Dương", "Duy", 
            "Đạt", "Đông", "Giang", "Hà", "Hải", "Hạnh", "Hiếu", "Hiền", "Hoa", "Hùng", 
            "Huy", "Hương", "Hường", "Huyền", "Khang", "Khánh", "Khoa", "Kiên", "Lan", "Linh", 
            "Long", "Lâm", "Lộc", "Mai", "Minh", "Nam", "Nghĩa", "Ngân", "Ngọc", "Nhi", 
            "Nhung", "Oanh", "Phong", "Phúc", "Phương", "Quân", "Quang", "Quốc", "Quỳnh", "Sơn", 
            "Thảo", "Thắng", "Thịnh", "Thông", "Thu", "Thành", "Thảo", "Thủy", "Tiến", "Trâm", 
            "Trang", "Trung", "Trình", "Tú", "Tuấn", "Tùng", "Tuyết", "Vinh", "Việt", "Vy", "Yến"
        ]
        return random.choice(first_names)
        
    def vn_last_name(self):
        last_names = [
            "Nguyễn", "Trần", "Lê", "Phạm", "Hoàng", "Phan", "Vũ", "Đặng", "Bùi", "Đỗ", 
            "Hồ", "Ngô", "Dương", "Lý", "Vương", "Trịnh", "Đoàn", "Lâm", "Phùng", "Mai", 
            "Tô", "Trương", "Hà", "Tạ", "Cao", "Khổng", "Quách"
        ]
        return random.choice(last_names)

# Initialize Faker with Vietnamese locale and register custom name provider
fake = Faker('vi_VN')
fake.add_provider(VietnameseNameProvider)
connection = get_master_connection()
cursor = connection.cursor()

def normalize_name(name):
    """
    Removes accents (diacritics), converts to lowercase, and removes spaces 
    to create standardized strings for emails/usernames.
    """
    name = unidecode(name)
    name = name.lower()
    name = name.replace(" ", "")
    return name

def generated_students(n):
    """
    Generates a list of student records with realistic student codes and university emails.
    """
    students = []
    
    if n > 10000:
        print("Limit reached: Student count cannot exceed 10,000")
        n = 10000
    
    for _ in range(n):
        first_name = fake.vn_first_name()
        last_name = fake.vn_last_name()
        # Generate unique 5-digit suffix
        student_code = fake.unique.bothify(text='#####')
        # Assign a random enrollment year prefix
        prefix = random.choice(["1902", "2002", "2102", "2202", "2302", "2402", "2502"]) 
        full_student_code = prefix + student_code
        dob = fake.date_of_birth(minimum_age=18, maximum_age=25)
        # Create standard VNU email format: name + code @ vnu.edu.vn
        base_email = normalize_name(first_name) + normalize_name(last_name) + full_student_code
        email = f"{base_email}@vnu.edu.vn"
        
        data = {
            "student_code": full_student_code,
            "first_name" : first_name,
            "last_name" : last_name,
            "gender" : fake.random_element(elements=('M', 'F')),
            "dob" : dob,
            "email": email,
            "phone": fake.unique.phone_number()[:20],
            "status": 1        
        }
        students.append(data)
      
    return students

def generated_rooms(n):
    """
    Generates dormitory room data across various buildings with pricing.
    """
    rooms = []
    
    if n > 1000:
        print("Warning: Room count cannot exceed 1,000")
        n = 1000
    
    building_configs = [
        {"name": "Building A", "capacity": 6, "price": 1000000, "count": 400},  # 400 phòng
        {"name": "Building B", "capacity": 8, "price": 800000, "count": 300},   # 300 phòng
        {"name": "Building C", "capacity": 14, "price": 600000, "count": 150},  # 150 phòng
        {"name": "Building D", "capacity": 14, "price": 300000, "count": 150},  # 150 phòng
    ]
    
    rooms_created = 0
        
    for config in building_configs:
        for _ in range(config["count"]):
            if rooms_created >= n: 
                return rooms    
            
            data = {
                "building" : config["name"],
                "capacity": config["capacity"],
                "current_occupancy": 0,
                "base_price": config["price"],
                "status": "available"
            }
            
            rooms.append(data)
            rooms_created += 1
        
    return rooms

def generated_contracts(n, all_room_ids, all_student_infos, room_caps):
    """
    Simulates rental contracts between students and rooms.
    Includes logic for active, ended, and cancelled statuses while respecting room capacity.
    """
    contracts = []  
    today = date.today()
    
    all_student_ids = list(all_student_infos.keys())
    
    n = min(n, len(all_student_ids))
    selected_students = random.sample(all_student_ids, n)
        
    # Track current occupancy to prevent overfilling rooms during data generation
    active_counts = {r_id: 0 for r_id in all_room_ids}
    
    odd_rooms = [r_id for r_id in all_room_ids if r_id % 2 != 0] # Seperate odd and even room_ids' from rooms 
    even_rooms = [r_id for r_id in all_room_ids if r_id % 2 == 0] # Odd rooms for male, even rooms for female

    for i in range(n):
        student_id = selected_students[i]
        student_gender = all_student_infos[student_id]
        start_date = fake.date_between(start_date='-6m', end_date='today')
        intended_end_date = start_date + timedelta(days=180)
        
        rand_val = random.random()
        
        # 5% chance of early cancellation
        if rand_val < 0.05:
            status = 'cancelled'
            final_end_date = start_date + timedelta(days=random.randint(10, 60))
        elif intended_end_date < today:
            status = 'ended'
            final_end_date = intended_end_date
        else:
            status = 'active'
            final_end_date = intended_end_date
        
        if student_gender == "M": 
            gender_spr = odd_rooms
        else:
            gender_spr = even_rooms
        
        room_id = None
        if status == 'active':
            # Only pick rooms that haven't reached their capacity limit
            available_rooms = [r for r in gender_spr if active_counts[r] < room_caps.get(r, 0)]
            
            if not available_rooms:
                # If no space left, force contract to 'ended' to maintain integrity
                status = 'ended'
                final_end_date = start_date + timedelta(days=10)
                room_id = random.choice(gender_spr) if gender_spr else random.choice(all_room_ids)
            else:
                room_id = random.choice(available_rooms)
                active_counts[room_id] += 1
        else:
            # Historical or cancelled records don't occupy current capacity
            room_id = random.choice(gender_spr) if gender_spr else random.choice(all_room_ids)
        
        data = {
            "student_id" : student_id,
            "room_id" : room_id,
            "start_date" : start_date,
            "end_date" : final_end_date,
            "status" : status
        }
        contracts.append(data)
        
    return contracts

def _subtract_months(first_day_of_month, months):
     """Helper function to calculate the first day of a month N months ago."""
     total_months = first_day_of_month.year * 12 + (first_day_of_month.month - 1) - months
     year = total_months // 12
     month = total_months % 12 + 1
     return date(year, month, 1)

def generated_meter_readings(all_room_ids, months_back=3):
    """
    Generates historical electricity and water readings for each room.
    Ensures that new readings are always greater than or equal to old readings.
    """
    meter_readings = []
    today = date.today()
    first_day_this_month = today.replace(day=1)
    
    for room_id in all_room_ids:
        for i in range(months_back):
            reading_month = _subtract_months(first_day_this_month, i)
            
            # Simulated consumption logic
            electric_old = random.randint(1000, 5000)
            electric_new = electric_old + random.randint(50, 200) 
            
            water_old = random.randint(500, 2000)
            water_new = water_old + random.randint(5, 25) 
            
            data = {
                "room_id": room_id,
                "month": reading_month,
                "electric_old": electric_old,
                "electric_new": electric_new,
                "water_old": water_old,
                "water_new": water_new
            }
            meter_readings.append(data)
            
    return meter_readings

def generated_invoices(list_readings, list_rooms):
    
    # Generates invoices based on meter readings, room base prices, and fixed service fees.
    # Randomly assigns payment statuses (paid, unpaid, overdue).

    invoices = []
    room_prices = {r['room_id']: r['base_price'] for r in list_rooms}
    
    # Utility unit pricing configuration
    ELECTRIC_UNIT_PRICE = 3.5  
    WATER_UNIT_PRICE = 12.0    
    SERVICE_FEE = 10.0         

    for reading in list_readings:
        room_id = reading['room_id']
        month = reading['month']
        
        room_fee = room_prices.get(room_id, 0)
        electric_qty = reading['electric_new'] - reading['electric_old']
        water_qty = reading['water_new'] - reading['water_old']
        
        electric_fee = round(electric_qty * ELECTRIC_UNIT_PRICE, 2)
        water_fee = round(water_qty * WATER_UNIT_PRICE, 2)
        
        total_amount = room_fee + electric_fee + water_fee + SERVICE_FEE
        due_date = month + timedelta(days=14) # Due by the 15th of the month
        
        rand_status = random.random()
        if rand_status < 0.7:
            paid_status = 'paid'
            payment_date = month + timedelta(days=random.randint(1, 10))
        elif rand_status < 0.9:
            paid_status = 'unpaid'
            payment_date = None
        else:
            paid_status = 'overdue'
            payment_date = None

        data = {
            "room_id": room_id, "month": month, "room_fee": room_fee,
            "electric_fee": electric_fee, "water_fee": water_fee,
            "service_fee": SERVICE_FEE, "total_amount": total_amount,
            "due_date": due_date, "payment_date": payment_date,
            "paid_status": paid_status
        }
        invoices.append(data)
    
    return invoices

# Database Insertion Helper Functions
def insert_students(connection, data_list):
    cursor = connection.cursor()
    sql = """INSERT INTO students (student_code, first_name, last_name, gender, dob, email, phone, status) 
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"""
    values = [(d['student_code'], d['first_name'], d['last_name'], d['gender'], 
               d['dob'], d['email'], d['phone'], d['status']) for d in data_list]
    cursor.executemany(sql, values)
    connection.commit()

def insert_rooms(connection, data_list):
    cursor = connection.cursor()
    sql = """INSERT INTO rooms (building, capacity, current_occupancy, base_price, status) 
             VALUES (%s, %s, %s, %s, %s)"""
    values = [(d['building'], d['capacity'], d['current_occupancy'], d['base_price'], d['status']) for d in data_list]
    cursor.executemany(sql, values)
    connection.commit()

def insert_contracts(connection, data_list):
    cursor = connection.cursor()
    sql = """INSERT INTO contracts (student_id, room_id, start_date, end_date, status) 
             VALUES (%s, %s, %s, %s, %s)"""
    values = [(d['student_id'], d['room_id'], d['start_date'], d['end_date'], d['status']) for d in data_list]
    cursor.executemany(sql, values)
    connection.commit()

def insert_readings(connection, data_list):
    cursor = connection.cursor()
    sql = """INSERT INTO meter_readings (room_id, month, electric_old, electric_new, water_old, water_new) 
             VALUES (%s, %s, %s, %s, %s, %s)"""
    values = [(d['room_id'], d['month'], d['electric_old'], d['electric_new'], d['water_old'], d['water_new']) for d in data_list]
    cursor.executemany(sql, values)
    connection.commit()

def insert_invoices(connection, data_list):
    cursor = connection.cursor()
    sql = """INSERT INTO invoices (room_id, month, room_fee, electric_fee, water_fee, service_fee, total_amount, due_date, payment_date, paid_status) 
             VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)"""
    values = [(d['room_id'], d['month'], d['room_fee'], d['electric_fee'], d['water_fee'], d['service_fee'], 
               d['total_amount'], d['due_date'], d['payment_date'], d['paid_status']) for d in data_list]
    cursor.executemany(sql, values)
    connection.commit()
    
def main():
    """
    Main execution flow: 
    1. Collect user input for data volume.
    2. Truncate existing tables to ensure a fresh dataset.
    3. Execute generation and insertion in dependency order.
    """
    amt_of_students = int(input("Number of students:"))
    amt_of_rooms = int(input("Number of rooms:"))
    amt_of_contracts = int(input("Number of contracts:"))
    cnt_months_mtr_readings = int(input("Months of utility readings:"))
    
    try: 
        # Temporarily disable foreign key checks to allow TRUNCATE operations
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
        cursor.execute("TRUNCATE TABLE invoices;")
        cursor.execute("TRUNCATE TABLE meter_readings;")
        cursor.execute("TRUNCATE TABLE contracts;")
        cursor.execute("TRUNCATE TABLE students;")
        cursor.execute("TRUNCATE TABLE rooms;")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
        
        # Phase 1: Students and Rooms
        raw_student = generated_students(amt_of_students)
        raw_rooms = generated_rooms(amt_of_rooms)
    
        insert_students(connection, raw_student)
        insert_rooms(connection, raw_rooms)
        
        # Refresh IDs and capacity info from DB for foreign key consistency
        cursor.execute("SELECT student_id, gender FROM students")
        all_student_infos = {stu_ID["student_id"] : stu_ID["gender"] for stu_ID in cursor.fetchall()}
    
        cursor.execute("SELECT room_id, capacity FROM rooms")
        rooms_data = cursor.fetchall()
        room_caps = {r["room_id"]: r["capacity"] for r in rooms_data}
        all_room_ids = list(room_caps.keys())
        
        # Phase 2: Contracts (requires existing students/rooms)
        raw_contracts = generated_contracts(amt_of_contracts, all_room_ids, all_student_infos, room_caps)
        insert_contracts(connection, raw_contracts)
        
        # Phase 3: Utility Readings
        raw_readings = generated_meter_readings(all_room_ids, cnt_months_mtr_readings)
        insert_readings(connection, raw_readings)
        
        # Phase 4: Invoices (calculated from readings and room prices)
        cursor.execute("SELECT room_id, base_price from rooms")
        db_rooms = [{"room_id": r["room_id"], "base_price": float(r["base_price"])} for r in cursor.fetchall()]
            
        raw_invoices = generated_invoices(raw_readings, db_rooms)
        insert_invoices(connection, raw_invoices)
        
        print("Data generation completed successfully.")
        
    finally:
        connection.close()
        
if __name__ == "__main__":
    main()