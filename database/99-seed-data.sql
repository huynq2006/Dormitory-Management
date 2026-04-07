USE dormitory_management;

-- Part 1: Clear existing data 
-- Clear existing data
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE invoices;
TRUNCATE TABLE meter_readings;
TRUNCATE TABLE contracts;
TRUNCATE TABLE students;
TRUNCATE TABLE rooms;
TRUNCATE TABLE audit_log;
SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO students (student_code, first_name, last_name, gender, email, status)
VALUES
  ('SV001', 'An',    'Nguyen', 'M', 'an@test.com',    1), -- active, có nợ
  ('SV002', 'Binh',  'Tran',   'F', 'binh@test.com',  1), -- active, đã paid
  ('SV003', 'Cam',   'Le',     'F', 'cam@test.com',   0), -- inactive, không hiện dù có nợ
  ('SV004', 'Dung',  'Pham',   'M', 'dung@test.com',  1), -- active, invoice chưa tới due_date
  ('SV005', 'Em',    'Hoang',  'F', 'em@test.com',    1), -- active, contract cancelled
  ('SV006', 'Phuc',  'Vo',     'M', 'phuc@test.com',  1), -- active, contract đã ended trước tháng invoice
  ('SV007', 'Giang', 'Do',     'F', 'giang@test.com', 1), -- active, paid_status='overdue'
  ('SV008', 'Hung',  'Bui',    'M', 'hung@test.com',  1), -- phòng nhiều người, cùng phòng SV001
  ('SV009', 'Lan',   'Ngo',    'F', 'lan@test.com',   1), -- active, due_date đúng hôm nay (edge)
  ('SV010', 'Khanh', 'Dinh', 'M', 'khanh@test.com', 1), -- contract ended LAST_DAY tháng invoice → hiện ra
  ('SV011', 'Linh',  'Phan', 'F', 'linh@test.com',  1), -- ended cuối tháng 1 → không hiện tháng 2
  ('SV012', 'Minh',  'Tran', 'M', 'minh@test.com',  1); -- bắt đầu đầu tháng 2 → hiện ra

INSERT INTO rooms (capacity, current_occupancy, base_price, status)
VALUES
  (4, 0, 1500000.00, 'available'), -- room_id=1: phòng nhiều người (SV001 + SV008)
  (2, 0, 1200000.00, 'available'), -- room_id=2: SV002 đã paid
  (2, 0, 1200000.00, 'available'), -- room_id=3: SV003 inactive
  (2, 0, 1000000.00, 'available'), -- room_id=4: SV004 chưa tới due_date
  (2, 0, 1000000.00, 'available'), -- room_id=5: SV005 contract cancelled
  (2, 0, 1000000.00, 'available'), -- room_id=6: SV006 contract ended cuối tháng 1 (trước tháng invoice 2)
  (2, 0, 1300000.00, 'available'), -- room_id=7: SV007 status='overdue'
  (2, 0, 1100000.00, 'available'), -- room_id=8: SV009 due_date hôm nay
  (2, 0, 1000000.00, 'available'), -- room_id=9: case 9
  (2, 0, 1200000.00, 'available'); -- room_id=10: case 10

INSERT INTO contracts (student_id, room_id, start_date, end_date, status)
VALUES
  -- Phòng 1: 2 sinh viên active cùng phòng
  (1, 1, '2026-01-01', NULL, 'active'),
  (8, 1, '2026-01-01', NULL, 'active'),
  -- Phòng 2: paid
  (2, 2, '2026-01-01', NULL, 'active'),
  -- Phòng 3: SV003 inactive
  (3, 3, '2026-01-01', NULL, 'active'),
  -- Phòng 4: chưa tới due_date
  (4, 4, '2026-01-01', NULL,  'active'),
  -- Phòng 5: contract cancelled
  (5, 5, '2026-01-01', NULL, 'cancelled'),
  -- Phòng 6: contract ended cuối tháng 1 (trước tháng invoice 2) → không hiện
  (6, 6, '2026-01-01', '2026-01-31', 'ended'),
  -- Phòng 7: overdue
  (7, 7, '2026-01-01', NULL, 'active'),
  -- Phòng 8: due_date đúng hôm nay
  (9, 8, '2026-01-01', NULL, 'active'),
  -- Phòng 9: ended cuối tháng 2 → vẫn active cuối tháng → hiện ra
  (10, 9, '2026-01-01', '2026-02-28', 'ended'),
  -- Case 10: A ended cuối tháng 1, B bắt đầu đầu tháng 2
(11, 10, '2026-01-01', '2026-01-31', 'ended'),
(12, 10, '2026-02-01', NULL, 'active');

INSERT INTO invoices (room_id, month, room_fee, electric_fee, water_fee, total_amount, due_date, paid_status)
VALUES
  -- CASE 1: Phòng nhiều người, unpaid, quá hạn → hiện cả SV001 và SV008
  (1, '2026-02-01', 1500000, 100000, 50000, 1650000.00, '2026-03-10', 'unpaid'),

  -- CASE 2: Đã paid → không hiện
  (2, '2026-02-01', 1200000,  80000, 40000, 1320000.00, '2026-03-05', 'paid'),

  -- CASE 3: SV003 inactive → không hiện dù invoice quá hạn
  (3, '2026-02-01', 1200000,  80000, 40000, 1320000.00, '2026-03-05', 'unpaid'),

  -- CASE 4: due_date chưa tới → không hiện
  (4, '2026-03-01', 1000000,  60000, 30000, 1090000.00, '2026-04-30', 'unpaid'),

  -- CASE 5: contract cancelled → không hiện
  (5, '2026-02-01', 1000000,  60000, 30000, 1090000.00, '2026-03-05', 'unpaid'),

  -- CASE 6: contract ended cuối tháng 1 (trước tháng invoice 2) → không hiện
  (6,  '2026-02-01', 1000000, 60000, 30000, 1090000.00, '2026-03-05', 'unpaid'),

  -- CASE 7: paid_status='overdue' → vẫn hiện
  (7, '2026-02-01', 1300000,  90000, 45000, 1435000.00, '2026-03-01', 'overdue'),

  -- 	CASE 8: due_date đúng hôm nay (CURDATE()) → không hiện vì điều kiện là < CURDATE()
  (8, '2026-03-01', 1100000,  70000, 35000, 1205000.00, CURDATE(), 'unpaid'),
  
  -- CASE 9: Contract ended đúng LAST_DAY tháng invoice (2026-02-28) → vẫn active cuối tháng 2 → hiện ra
  (9,  '2026-02-01', 1000000, 60000, 30000, 1090000.00, '2026-03-05', 'unpaid'),
  
  -- CASE 10:A ended cuối tháng 1, B bắt đầu đầu tháng 2 → vẫn hiện B vì còn active cuối tháng 2
  -- chỉ B còn active vào LAST_DAY(2026-02) = 28/02
  -- A đã ended 31/01 → không có contract tháng 2 → bị loại → không trùng dòng
  (10, '2026-02-01', 1200000, 80000, 40000, 1320000.00, '2026-03-05', 'unpaid');

  
-- Xem view
SELECT * FROM vw_overdue_debtors;


-- kiểm tra từng case lẻ
-- CASE 1: Phòng nhiều người → phải ra đúng 2 rows, không thiếu không thừa
SELECT * FROM vw_overdue_debtors WHERE room_id = 1;
-- Expected: 2 rows (SV001 + SV008)

-- CASE 2: Đã paid → 0 rows
SELECT * FROM vw_overdue_debtors WHERE room_id = 2;
-- Expected: 0 rows

--  CASE 3: SV inactive → 0 rows dù invoice quá hạn
SELECT * FROM vw_overdue_debtors WHERE room_id = 3;
-- Expected: 0 rows

-- CASE 4: Due date chưa tới → 0 rows
SELECT * FROM vw_overdue_debtors WHERE room_id = 4;
-- Expected: 0 rows

-- CASE 5: Contract cancelled → 0 rows
SELECT * FROM vw_overdue_debtors WHERE room_id = 5;
-- Expected: 0 rows

-- CASE 6: contract ended cuối tháng 1 (trước tháng invoice 2) → không hiện
-- Lý do: end_date = 31/01 < LAST_DAY(2026-02) = 28/02 → không còn active cuối tháng → không hiện
SELECT * FROM vw_overdue_debtors WHERE room_id = 6;
-- Expected: 0 rows

-- CASE 7: paid_status='overdue' → vẫn phải hiện
SELECT * FROM vw_overdue_debtors WHERE room_id = 7;
-- Expected: 1 row (SV007)

-- CASE 8: Due date đúng hôm nay → 0 rows (boundary: < không phải <=)
SELECT * FROM vw_overdue_debtors WHERE room_id = 8;
-- Expected: 0 rows

-- CASE 9: Contract ended đúng LAST_DAY tháng invoice (28/02) → vẫn hiện
-- Expected: 1 row (SV010)
-- Lý do: end_date = 28/02 = LAST_DAY(2026-02) → còn active cuối tháng → hiện ra
SELECT * FROM vw_overdue_debtors WHERE room_id = 9;

-- CASE 10: A ended cuối tháng 1, B bắt đầu đầu tháng 2 → vẫn hiện B vì còn active cuối tháng 2
SELECT * FROM vw_overdue_debtors WHERE room_id = 10;
-- Expected: 1 row — chỉ Student B
-- Lý do: chỉ B còn active vào LAST_DAY(2026-02) = 28/02
  -- A đã ended 31/01 → không có contract tháng 2 → bị loại → không trùng dòng


SELECT COUNT(*) AS total FROM vw_overdue_debtors;
-- Expected: 5 (Case 1: 2 rows + Case 7: 1 row + Case 9: 1 row + Case 10: 1 row)