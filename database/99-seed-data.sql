DROP TRIGGER IF EXISTS update_occupancy;
DROP TRIGGER IF EXISTS trg_decrease_occupancy;
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
 
-- TEST CASE 1:  Phòng mới đã full (Vi phạm BR-01, phải ROLLBACK)


