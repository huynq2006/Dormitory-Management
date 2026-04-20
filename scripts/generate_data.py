import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from faker import Faker
from faker.providers import BaseProvider
from backend.db_helper import get_master_connection
import random
from datetime import date, timedelta
from unidecode import unidecode

class VietnameseNameProvider(BaseProvider):
    def vn_first_name(self):
        return random.choice(["Huy", "Linh", "Trang", "Minh"])

fake = Faker('vi_VN')
fake.add_provider(VietnameseNameProvider)
connection = get_master_connection()
cursor = connection.cursor()

def normalize_name(name):
    name = unidecode(name)
    name = name.lower()
    name = name.replace(" ", "")
    return name

def generated_students(n):
    students = []
    
    if n > 10000:
        print("Số lượng người không được vượt quá 10000")
        n = 10000
    
    for _ in range(n):
        first_name = fake.vn_first_name()
        last_name = fake.last_name()
        student_code = fake.unique.bothify(text='#####')
        prefix = random.choice(["1902", "2002", "2102", "2202", "2302", "2402", "2502"]) 
        full_student_code = prefix + student_code
        dob = fake.date_of_birth(minimum_age=18, maximum_age=25)
        base_email = normalize_name(first_name) + normalize_name(last_name) + full_student_code
        email = f"{base_email}@vnu.edu.vn"
        
        data = {
            "student_code": full_student_code,
            "first_name" : first_name,
            "last_name" : last_name,
            "gender" : fake.random_element(elements=('M', 'F', 'O')),
            "dob" : dob,
            "email": email,
            "phone": fake.unique.phone_number()[:20],
            "status": 1        
        }
        students.append(data)
      
    for student in students:   
        print(student)
    print('\n')
    
    return students

def generated_rooms(n):
    rooms = []
    
    if n > 1000:
        print("Cảnh báo: Số lượng phòng không được vượt quá 1000")
        n = 1000
    
    for _ in range(n):
        
        data = {
            "building" : random.choice(["Building A", "Building B", "Building C", "Building D"]),
            "capacity": random.randint(1, 6),
            "current_occupancy": 0,
            "base_price": round(random.uniform(50.0, 200.0), 2),
            "status": "available"
        }
        rooms.append(data)
    
    for room in rooms:   
        print(room)
    print('\n')
        
    return rooms

def generated_contracts(n, all_room_ids, all_student_ids, room_caps):
    contracts = []  
    today = date.today()
    
    if n > 10000:
        print("Cảnh báo: Số lượng hợp đồng không được vượt quá 10000")
        n = 10000
    
    n = min(n, len(all_student_ids))
    selected_students = random.sample(all_student_ids, n)
        
    cursor.execute("SELECT room_id, capacity, current_occupancy FROM rooms")
    room_rows = cursor.fetchall()
    room_caps = {r['room_id']: r['capacity'] for r in room_rows}
    room_current = {r['room_id']: r['current_occupancy'] for r in room_rows}
    active_counts = {r_id: room_current.get(r_id, 0) for r_id in all_room_ids} # Count existing active occupancy plus generated active contracts

    for i in range(n):
        student_id = selected_students[i]
        
        start_date = fake.date_between(start_date='-6m', end_date='today')
        
        # Calculate intended end date (~ roughly 6 months)
        intended_end_date = start_date + timedelta(days=180)
        
        # Decided status based on logic, current time and 5 percent of being cancelled
        rand_val = random.random() # return randomly from 0.0 to 1.0
        
        if rand_val < 0.05:
            # Cancelled (5%): Contract cancelled in between 10-60 days
            status = 'cancelled'
            final_end_date = start_date + timedelta(days=random.randint(10, 60))
        elif intended_end_date < today:
            # Ended: Contract ended  
            status = 'ended'
            final_end_date = intended_end_date
        else:
            # Active: Contract active
            status = 'active'
            final_end_date = intended_end_date
        
        room_id = None
        if status == 'active':
            # Find rooms that still have available capacity
            available_rooms = [r for r in all_room_ids if active_counts[r] < room_caps.get(r, 0)]
            
            if not available_rooms:
                # If no rooms are available, force the contract status to 'ended'
                # to maintain data integrity and avoid database constraint violations
                status = 'ended'
                final_end_date = start_date + timedelta(days=10)
                room_id = random.choice(all_room_ids)
            else:
                # If rooms are available, pick one at random and increment its occupancy count
                room_id = random.choice(available_rooms)
                active_counts[room_id] += 1
        else:
            # For cancelled/ended contracts, database triggers typically do not 
            # include these in the current_occupancy calculation
            room_id = random.choice(all_room_ids)
        
        data = {
            "student_id" : student_id,
            "room_id" : room_id,
            "start_date" : start_date,
            "end_date" : final_end_date,
            "status" : status
        }
        contracts.append(data)
    for contract in contracts[:10]:    
        print(contract)
    print(f"... (và {len(contracts) - 10} hợp đồng khác)\n")
        
    return contracts

def generated_meter_readings(all_room_ids, months_back=3):
    meter_readings = []
    today = date.today()
    
    for room_id in all_room_ids:
        for i in range(months_back):
            # 1. Calculate the month in YYYY-MM-01 format
            y = today.year
            m = today.month - i
            while m <= 0:
                m += 12
                y -= 1
            reading_month = date(y, m, 1)
            
            # 2. Generate electricity readings (Ensure electric_new >= electric_old)
            electric_old = random.randint(1000, 5000)
            electric_new = electric_old + random.randint(50, 200) # Tiêu thụ 50-200 số điện
            
            # 3. Generate water readings (Ensure water_new >= water_old)
            water_old = random.randint(500, 2000)
            water_new = water_old + random.randint(5, 25) # Tiêu thụ 5-25 khối nước
            
            data = {
                "room_id": room_id,
                "month": reading_month,
                "electric_old": electric_old,
                "electric_new": electric_new,
                "water_old": water_old,
                "water_new": water_new
            }
            meter_readings.append(data)
    
    for meter_reading in meter_readings:
        print(meter_reading)
    print('\n')
            
    return meter_readings


def generated_invoices(list_readings, list_rooms):
    invoices = []
    
    # Declare a dictionary to map each room_id to its base price
    room_prices = {r['room_id']: r['base_price'] for r in list_rooms}
    
    # Utility pricing (example values in Vietnam)
    ELECTRIC_UNIT_PRICE = 3.5  # 3.50 per kWh
    WATER_UNIT_PRICE = 12.0    # 12.00 per cubic meter
    SERVICE_FEE = 10.0         # Fixed service fee

    for reading in list_readings:
        room_id = reading['room_id']
        month = reading['month']
        
        # Calculate costs
        room_fee = room_prices.get(room_id, 0)
        electric_qty = reading['electric_new'] - reading['electric_old']
        water_qty = reading['water_new'] - reading['water_old']
        
        electric_fee = round(electric_qty * ELECTRIC_UNIT_PRICE, 2)
        water_fee = round(water_qty * WATER_UNIT_PRICE, 2)
        
        total_amount = room_fee + electric_fee + water_fee + SERVICE_FEE
        
        # Due date is typically the 15th of the month (based on your stored procedure logic)
        due_date = month + timedelta(days=14) 
        
        # Randomize payment status
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
            "room_id": room_id,
            "month": month,
            "room_fee": room_fee,
            "electric_fee": electric_fee,
            "water_fee": water_fee,
            "service_fee": SERVICE_FEE,
            "total_amount": total_amount,
            "due_date": due_date,
            "payment_date": payment_date,
            "paid_status": paid_status
        }
        invoices.append(data)
    
    for invoice in invoices:  
        print(invoice)
    print('\n\n')   
    
    return invoices

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
    amt_of_students = int(input("Số lượng học sinh:"))
    amt_of_rooms = int(input("Số lượng phòng:"))
    amt_of_contracts = int(input("Số lượng hợp đồng:"))
    cnt_months_mtr_readings = int(input("Số lượng tháng tính điện nước:"))
    
    try: 
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
        cursor.execute("TRUNCATE TABLE invoices;")
        cursor.execute("TRUNCATE TABLE meter_readings;")
        cursor.execute("TRUNCATE TABLE contracts;")
        cursor.execute("TRUNCATE TABLE students;")
        cursor.execute("TRUNCATE TABLE rooms;")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
        
        raw_student = generated_students(amt_of_students)
        raw_rooms = generated_rooms(amt_of_rooms)
    
        insert_students(connection, raw_student)
        insert_rooms(connection, raw_rooms)
        
        cursor.execute("SELECT student_id FROM students")
        all_student_ids = [stu_ID["student_id"] for stu_ID in cursor.fetchall()]
    
        cursor.execute("SELECT room_id, capacity FROM rooms")
        rooms_data = cursor.fetchall()
        # Tạo dictionary để tra cứu sức chứa: {room_id: capacity}
        room_caps = {r["room_id"]: r["capacity"] for r in rooms_data}
        all_room_ids = list(room_caps.keys())
        
        raw_contracts = generated_contracts(amt_of_contracts, all_room_ids, all_student_ids, room_caps)
        insert_contracts(connection, raw_contracts)
        
        raw_readings = generated_meter_readings(all_room_ids, cnt_months_mtr_readings)
        insert_readings(connection, raw_readings)
        
        cursor.execute("SELECT room_id, base_price from rooms")
        db_rooms = [{"room_id": r["room_id"], "base_price": float(r["base_price"])} for r in cursor.fetchall()]
            
        raw_invoices = generated_invoices(raw_readings, db_rooms)
        insert_invoices(connection, raw_invoices)
    finally:
        connection.close()
        
if __name__ == "__main__":
    main()