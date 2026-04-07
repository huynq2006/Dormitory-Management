from faker import Faker
import random
from datetime import date, timedelta

fake = Faker('vi_VN')

def generated_students(n):
    students = []
    
    if n > 400:
        print("Số lượng người không được vượt quá 400")
        n = 400
    
    for _ in range(n):
        
        data = {
            "student_code": str(random.randint(19020000, 26020000)), # giữ đuôi
            "first_name" : fake.first_name(),
            "last_name" : fake.last_name(), 
            "gender" : fake.random_element(elements=('M', 'F', 'O')),
            "dob" : fake.date_of_birth(minimum_age=18, maximum_age=25),
            "email": fake.unique.email(),
            "phone": fake.phone_number(),
            "status": 1        
        }
        students.append(data)
        
    print(students)
    
    return students

def generated_rooms(n):
    rooms = []
    
    # rand_building = ["Building A", "Building B", "Building C", "Building D"]
    # rand_status = ['available', 'full', 'maintenance']
    
    if n > 200:
        print("Cảnh báo: Số lượng phòng không được vượt quá 200")
        n = 200
    
    for _ in range(n):
        
        data = {
            "building" : random.choice(["Building A", "Building B", "Building C", "Building D"]),
            "capacity": random.randint(1, 6),
            "current_occupancy": 0,
            "base_price": round(random.uniform(50.0, 200.0), 2),
            "status": random.choice(['available', 'full', 'maintenance'])
        }
        rooms.append(data)
        
    return rooms

# Generate a list of rooms and save their original ID
list_rooms = generated_rooms(50)
all_room_ids = [r['room_id'] for r in list_rooms] 

# Generate a list of students and save their original ID
list_students = generated_students(100)
all_student_ids = [s['student_id'] for s in list_students]

def generated_contracts(n):
    contracts = []  
    old_contract_ids = set()
    today = date.today()
    
    if n > 200:
        print("Cảnh báo: Số lượng hợp đồng không được vượt quá 200")
        n = 200
        
    for _ in range(n):
        
        start_date = fake.date_between(start_date='-6m', end_date='today')
        
        # Calculate intended end date (~ roughly 6 months)
        intended_end_date = start_date + timedelta(days=180)
        
        # Decided status based on logic, current time and 5 percent of being cancelled
        rand_val = random.random() # return randomly from 0.0 to 1.0
        
        if rand_val < 0.05:
            # CANCELLED (5%): Contract cancelled in between 10-60 days
            status = 'cancelled'
            final_end_date = start_date + timedelta(days=random.randint(10, 60))
        elif intended_end_date < today:
            # ENDED: Contract ended  
            status = 'ended'
            final_end_date = intended_end_date
        else:
            # ACTIVE: Contract active
            status = 'active'
            final_end_date = intended_end_date
        
        data = {
            "student_id" : random.choice(all_student_ids),
            "room_id" : random.choice(all_room_ids),
            "start_date" : start_date,
            "end_date" : final_end_date,
            "status" : status
        }
        contracts.append(data)
        
    return contracts


def generated_meter_readings(all_room_ids, months_back=3):
    meter_readings = []
    today = date.today()
    
    for room_id in all_room_ids:
        for i in range(months_back):
            # 1. Tính toán tháng theo quy ước YYYY-MM-01
            # Lấy ngày đầu tiên của tháng hiện tại, sau đó trừ đi i tháng
            first_day_this_month = today.replace(day=1)
            # Trừ i tháng (khoảng i * 30 ngày để lùi tháng, sau đó ép về ngày 01)
            reading_month = (first_day_this_month - timedelta(days=i*31)).replace(day=1)
            
            # 2. Sinh chỉ số điện (Đảm bảo electric_new >= electric_old)
            electric_old = random.randint(1000, 5000)
            electric_new = electric_old + random.randint(50, 200) # Tiêu thụ 50-200 số điện
            
            # 3. Sinh chỉ số nước (Đảm bảo water_new >= water_old)
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
            
    return meter_readings
    
list_readings = generated_meter_readings(all_room_ids, 3)
print(list_readings)

def generated_invoices(list_readings, list_rooms):
    invoices = []
    
    # Tạo một từ điển để tra cứu nhanh base_price của từng phòng
    room_prices = {r['room_id']: r['base_price'] for r in list_rooms}
    
    # Định giá điện nước (ví dụ thực tế tại VN)
    ELECTRIC_UNIT_PRICE = 3.5  # 3.50 mỗi số điện
    WATER_UNIT_PRICE = 12.0    # 12.00 mỗi khối nước
    SERVICE_FEE = 10.0         # Phí dịch vụ cố định

    for reading in list_readings:
        room_id = reading['room_id']
        month = reading['month']
        
        # Tính toán chi phí
        room_fee = room_prices.get(room_id, 0)
        electric_qty = reading['electric_new'] - reading['electric_old']
        water_qty = reading['water_new'] - reading['water_old']
        
        electric_fee = round(electric_qty * ELECTRIC_UNIT_PRICE, 2)
        water_fee = round(water_qty * WATER_UNIT_PRICE, 2)
        
        total_amount = room_fee + electric_fee + water_fee + SERVICE_FEE
        
        # Hạn thanh toán thường là ngày 15 của tháng đó (theo logic Procedure của bạn)
        due_date = month + timedelta(days=14) 
        
        # Ngẫu nhiên trạng thái thanh toán
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
        
    return invoices