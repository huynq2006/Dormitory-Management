USE dormitory_management;

SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE audit_log;
TRUNCATE TABLE invoices; 
TRUNCATE TABLE meter_readings;
TRUNCATE TABLE audit_log;
DELETE FROM rooms WHERE room_id IN (101, 102, 103);
SET FOREIGN_KEY_CHECKS = 1;

insert into rooms (room_id, capacity, current_occupancy,base_price, status) VALUES
(101, 2, 2, 1500000, 'available'), -- phong binh thuong 
(102, 4, 0, 1000000, 'available'), -- phong trong
(103, 2, 0, 2000000,'maintenance'); -- phong trong + bao tri

INSERT INTO meter_readings (room_id, month, electric_old, electric_new, water_old, water_new)
VALUES 
(101, '2026-04-01', 100, 200, 50, 60), 
(102, '2026-04-01', 200, 250, 40, 70), 
(103, '2026-04-01', 105, 220, 30, 80);

-- Test 1: Kiểm tra Event ghi vào audit_log 
SELECT * 
FROM audit_log; 

-- Test 2: Giả lập Server sập và Chạy lại 
-- Thay đổi giá phòng 101 xuống 1.100.000đ
UPDATE rooms SET base_price = 1100000 WHERE room_id = 101;

select * 
from invoices; 

