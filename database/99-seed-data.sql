DROP TRIGGER update_occupancy;
DROP TRIGGER trg_decrease_occupancy;
-- Part 2: Test Trigger
-- 1. Clean old data for testing triggers
-- Phải xoá cái này để các Part 2, 3 không cộng dồn vào Part 4
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE contracts;
TRUNCATE TABLE rooms;
TRUNCATE TABLE students;
TRUNCATE TABLE audit_log;
SET FOREIGN_KEY_CHECKS = 1;
-- 2. Set up initial data for testing triggers
-- Rooms cho trigger test
INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, status) VALUES
  (101, 4, 0, 1500000.00, 'available'),    -- Room A: test case 1, 2
  (102, 4, 0, 1200000.00, 'available'),    -- Room B: test case 2, 4
  (103, 2, 0, 1000000.00, 'available'),    -- Room C: test case 1
  (104, 2, 0, 1000000.00, 'maintenance'),  -- Room D: test case 4 (maintenance)
  (201, 2, 0, 1100000.00, 'available'),    -- Room X: test case 5
  (202, 2, 0, 1100000.00, 'available'),    -- Room X2: test case 5 (SV2001 đang ở)
  (203, 2, 0, 1100000.00, 'available'),    -- Room X3: test case 5 (SV2002 đang ở)
  (301, 3, 0, 1300000.00, 'available');    -- Room T: test case 6
 
-- Students cho trigger test
INSERT INTO students (student_id, student_code, first_name, last_name, gender, email, status) VALUES
  (1001, 'SV1001', 'Anh',   'Nguyen', 'M', 'anh@vnu.edu.vn',   1),
  (1002, 'SV1002', 'Binh',  'Le',     'F', 'binh@vnu.edu.vn',  1),
  (1005, 'SV1005', 'Cuong', 'Tran',   'M', 'cuong@vnu.edu.vn', 1),
  (2001, 'SV2001', 'Dung',  'Pham',   'M', 'dung@vnu.edu.vn',  1),
  (2002, 'SV2002', 'Em',    'Hoang',  'F', 'em@vnu.edu.vn',    1),
  (3001, 'SV3001', 'An',    'Dang',   'M', 'an@vnu.edu.vn',    1),
  (3002, 'SV3002', 'Bao',   'Hoang',  'M', 'bao@vnu.edu.vn',   1),
  (3003, 'SV3003', 'Chi',   'Vu',     'F', 'chi@vnu.edu.vn',   1);
 
-- TEST CASE 6: Trigger occupancy & status
-- Mục tiêu: Kiểm tra trigger cập nhật occupancy đúng
-- khi INSERT/UPDATE/DELETE contract
 
-- Bước 1: Thêm 3 contract active vào Room T (capacity=3)
INSERT INTO contracts (student_id, room_id, start_date, status) VALUES
  (3001, 301, '2026-03-01', 'active'),
  (3002, 301, '2026-03-01', 'active'),
  (3003, 301, '2026-03-01', 'active');
  -- Nếu báo Room 301 is full, chạy để kiểm tra tình trạng
  SELECT room_id, capacity, current_occupancy, status 
FROM rooms WHERE room_id = 301;
SELECT * FROM contracts WHERE room_id = 301;
SHOW TRIGGERS FROM dormitory_management; -- -> nếu dư 2 trigger thì xóa như ở trên đầu
 
SELECT 'TC6-Step1: Insert 3 active contracts' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 301;
-- Expected: current_occupancy=3, status='full'
 
-- Bước 2: Update 1 contract thành ended → occupancy giảm
UPDATE contracts
SET status = 'ended', end_date = LAST_DAY('2026-03-01')
WHERE student_id = 3003 AND room_id = 301 AND status = 'active';
 
SELECT 'TC6-Step2: End contract SV3003' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 301;
-- Expected: current_occupancy=2, status='available'
 
-- Bước 3: Xóa 1 contract đang active → occupancy giảm
DELETE FROM contracts WHERE student_id = 3002 AND room_id = 301 AND status = 'active';
 
SELECT 'TC6-Step3: Delete active contract SV3002' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 301;
-- Expected: current_occupancy=1, status='available'
 
-- Bước 4: Xóa 1 contract đã ended → occupancy KHÔNG đổi
DELETE FROM contracts WHERE student_id = 3003 AND room_id = 301 AND status = 'ended';
 
SELECT 'TC6-Step4: Delete ended contract SV3003' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 301;
-- Expected: current_occupancy=1, status='available' (không đổi)
 

-- TEST CASE 1 (TRIGGER PART): BR-01 phòng full
-- Mục tiêu: BEFORE INSERT trigger chặn insert
-- khi current_occupancy >= capacity
 
-- Setup: Điền đầy room 101 (capacity=4) bằng cách cập nhật trực tiếp
UPDATE rooms SET current_occupancy = 4, status = 'full' WHERE room_id = 101;
 
-- Thử insert contract vào phòng full → phải bị chặn
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1001, 101, CURDATE(), 'active');
-- Expected: ERROR 'Room is full'
 
SELECT 'TC1: Room 101 sau khi thử insert vào phòng full' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 101;
-- Expected: current_occupancy=4, status='full' (không đổi)
 
-- Reset room 101 cho các test tiếp theo
UPDATE rooms SET current_occupancy = 0, status = 'available' WHERE room_id = 101;
 
-- TEST CASE 4 (TRIGGER PART): Phòng maintenance
-- Mục tiêu: BEFORE INSERT trigger chặn insert
-- khi phòng đang bảo trì
 
-- Thử insert contract vào phòng maintenance → phải bị chặn
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1001, 104, CURDATE(), 'active');
-- Expected: ERROR 'Room is under maintenance'
 
SELECT 'TC4: Room 104 sau khi thử insert vào phòng maintenance' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 104;
-- Expected: current_occupancy=0, status='maintenance' (không đổi)
-- Nếu Kết quả hiển thị thành 1, kiểm tra
SHOW TRIGGERS FROM dormitory_management 
WHERE `Table` = 'contracts';
SELECT * FROM rooms WHERE room_id = 104;
SELECT * FROM contracts WHERE student_id = 1001;
 
-- TEST CASE BR-02 (TRIGGER PART): 1 student 1 active contract
-- Mục tiêu: BEFORE INSERT trigger chặn insert
-- khi student đã có active contract
 
-- Setup: SV1001 đang có contract active tại room 103
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1001, 103, CURDATE(), 'active');
 
SELECT 'BR-02 Setup: SV1001 vào room 103' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 103;
-- Expected: current_occupancy=1
 
-- Thử insert thêm 1 contract active cho SV1001 → phải bị chặn
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1001, 102, CURDATE(), 'active');
-- Expected: ERROR 'Student already has an active contract'
 
SELECT 'BR-02: Room 102 sau khi thử insert contract thứ 2' AS test_step,
       room_id, current_occupancy, status FROM rooms WHERE room_id = 102;
-- Expected: current_occupancy=0 (không đổi)
