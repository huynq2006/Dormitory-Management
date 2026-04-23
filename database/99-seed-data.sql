-- ========================================================
-- SEED DATA FOR DORMITORY MANAGEMENT SYSTEM TESTING
-- Organized by Test Cases 1 - 8
-- ========================================================

select count(room_id) from rooms;
select count(student_id) from students;
select count(contract_id) from contracts;
select count(reading_id) from meter_readings;
select count(invoice_id) from invoices;

USE dormitory_management;

-- Clear existing data to ensure a clean state (Disable FK checks for truncation)
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE audit_log;
TRUNCATE TABLE invoices;
TRUNCATE TABLE meter_readings;
TRUNCATE TABLE contracts;
TRUNCATE TABLE rooms;
TRUNCATE TABLE students;
SET FOREIGN_KEY_CHECKS = 1;

-- ========================================================
-- COMMON DATA SETUP (Base Students and Rooms)
-- ========================================================

INSERT INTO students (student_id, student_code, first_name, last_name, gender, email, status) VALUES
(1001, 'SV1001', 'Anh', 'Nguyen', 'M', 'anh@vnu.edu.vn', 1),
(1002, 'SV1002', 'Binh', 'Le', 'F', 'binh@vnu.edu.vn', 1),
(1005, 'SV1005', 'Cuong', 'Tran', 'M', 'cuong@vnu.edu.vn', 1),
(2001, 'SV2001', 'Dung', 'Pham', 'M', 'dung@vnu.edu.vn', 1),
(2002, 'SV2002', 'Em', 'Hoang', 'F', 'em@vnu.edu.vn', 1),
(3001, 'SV3001', 'An', 'Dang', 'M', 'an@vnu.edu.vn', 1),
(3002, 'SV3002', 'Bao', 'Hoang', 'M', 'bao@vnu.edu.vn', 1),
(3003, 'SV3003', 'Chi', 'Vu', 'F', 'chi@vnu.edu.vn', 1);

-- --------------------------------------------------------
-- TEST CASE 1: New Room is Full (Violation of BR-01)
-- --------------------------------------------------------
-- Setup: Room 101 is already at maximum capacity
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (101, 'A', 4, 4, 1500000.00, 'full');

-- Setup: Student 1001 has an active contract in Room 103
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (103, 'C', 2, 0, 1000000.00, 'available');

INSERT INTO contracts (contract_id, student_id, room_id, start_date, status) 
VALUES (5001, 1001, 103, '2026-03-01', 'active');

CALL sp_transfer_room(1001, 101, '2026-03-31');

-- EXPECTED: CALL sp_transfer_room(1001, 101) should fail/rollback.

-- --------------------------------------------------------
-- TEST CASE 2: Room Available - Successful Transfer
-- --------------------------------------------------------
-- Setup: Room 102 has space
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (102, 'B', 4, 1, 1200000.00, 'available');

CALL sp_transfer_room(1001, 102, '2026-03-31');

-- Student 1001 (setup in TC1) will attempt transfer from 103 to 102.
-- EXPECTED: sp_transfer_room succeeds. Contract 5001 ends '2026-03-31', new contract starts '2026-04-01'.

-- --------------------------------------------------------
-- TEST CASE 3: Student has no Active Contract
-- --------------------------------------------------------
-- Setup: Student 1002 exists but has no active contract.
CALL sp_transfer_room(1002, 102, '2026-03-31');
-- EXPECTED: CALL sp_transfer_room(1002, 102) should fail/rollback.

-- --------------------------------------------------------
-- TEST CASE 4: New Room under Maintenance
-- --------------------------------------------------------
-- Setup: Room 104 is under maintenance
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (104, 'B', 4, 0, 1000000.00, 'maintenance');

CALL sp_transfer_room(1001, 104, '2026-03-31');

-- EXPECTED: CALL sp_transfer_room(1001, 104) should fail due to 'maintenance' status.

-- --------------------------------------------------------
-- TEST CASE 5: Concurrent Transfer (Race Condition)
-- --------------------------------------------------------
-- Setup: Room 201 has only 1 spot left
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (201, 'X', 2, 1, 1100000.00, 'available');

-- Students 2001 and 2002 have active contracts elsewhere
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (202, 'X', 2, 0, 1100000.00, 'available'),
       (203, 'X', 2, 0, 1100000.00, 'available');

INSERT INTO contracts (student_id, room_id, start_date, status) VALUES 
(2001, 202, '2026-03-01', 'active'),
(2002, 203, '2026-03-01', 'active');

-- Session 1
CALL sp_transfer_room(2001, 201, '2026-03-31');

-- Session 2
CALL sp_transfer_room(2002, 201, '2026-03-31');

-- EXPECTED: Only one session succeeds; the second one triggers 'Room is full' error.

-- --------------------------------------------------------
-- TEST CASE 6: Trigger Occupancy & Status Synchronization
-- --------------------------------------------------------
-- Setup: Room 301 is empty
INSERT INTO rooms (room_id, building, capacity, current_occupancy, base_price, status) 
VALUES (301, 'T', 3, 0, 1300000.00, 'available');

SELECT * FROM rooms WHERE room_id = 301;

INSERT INTO contracts (contract_id, student_id, room_id, start_date, status) VALUES 
(5004, 3001, 301, '2026-03-01', 'active'),
(5005, 3002, 301, '2026-03-01', 'active'),
(5006, 3003, 301, '2026-03-01', 'active');
-- Step 1: Insert 3 active contracts (Room should become 'full')
 
-- Step 2: Update 1 contract to 'ended' (Occupancy should decrease to 2, status 'available')\
UPDATE contracts 
SET status = 'ended', end_date = '2026-03-31'
WHERE student_id = 3003 AND room_id = 301 AND status = 'active';

SELECT * FROM rooms WHERE room_id = 301;
-- Step 3: Delete 1 active contract (Occupancy should decrease to 1)
DELETE FROM contracts 
WHERE student_id = 3002 AND room_id = 301 AND status = 'active';
-- Step 4: Delete 1 already ended contract (Occupancy should remain 1)
DELETE FROM contracts 
WHERE student_id = 3003 AND room_id = 301 AND status = 'ended';

SELECT room_id, capacity, current_occupancy, status
FROM rooms
WHERE room_id = 301;
-- --------------------------------------------------------
-- TEST CASE 7: Same Room Transfer
-- --------------------------------------------------------
-- Setup: Student 1005 is already in Room 101
INSERT INTO contracts (contract_id, student_id, room_id, start_date, status) 
VALUES (7001, 1005, 101, '2026-03-01', 'active');

UPDATE rooms 
SET capacity = 5, status = "available"
WHERE room_id = 101;

CALL sp_transfer_room(1005, 101, '2026-03-31');
-- EXPECTED: CALL sp_transfer_room(1005, 101, '2026-03-31') should be blocked by logic to prevent data noise.

-- --------------------------------------------------------
-- TEST CASE 8: Block Mid-Month Transfer (BR-06)
-- --------------------------------------------------------
CALL sp_transfer_room(1001, 102, '2026-03-15');
-- EXPECTED: If p_effective_date is not the last day of the month (e.g., '2026-03-15'), 
-- the procedure should throw an error to enforce monthly alignment.

-- ========================================================
-- AUDIT LOG INITIALIZATION
-- ========================================================
INSERT INTO audit_log (actor, action, detail) 
VALUES ('system_seed', 'SEED_DATA_LOAD', 'Initial test data for cases 1-8 loaded successfully');

-- Final Verification of Setup
SELECT * FROM rooms;
SELECT * FROM students;
SELECT * FROM contracts;
SELECT * FROM audit_log;