<<<<<<< HEAD
USE dormitory_management;

-- Clear existing data
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE invoices;
TRUNCATE TABLE meter_readings;
TRUNCATE TABLE contracts;
TRUNCATE TABLE students;
TRUNCATE TABLE rooms;
TRUNCATE TABLE audit_log;
SET FOREIGN_KEY_CHECKS = 1;

-- Insert data
-- Insert a student, a room, a contract, and an unpaid invoice to test the view for overdue debtors
INSERT IGNORE INTO students (student_id, student_code, first_name, last_name, gender, email) 
VALUES (1, 'SV001', 'Nguyen Van', 'A', 'M', 'sv001@vnu.edu.vn');

INSERT IGNORE INTO rooms (room_id, capacity, current_occupancy, base_price, status) 
VALUES (1, 4, 0, 500000.00, 'available');

INSERT INTO contracts (student_id, room_id, start_date, status) 
VALUES (1, 1, '2026-03-01', 'active');

INSERT INTO invoices (room_id, month, total_amount, due_date, paid_status) 
VALUES (1, '2026-03-01', 650000.00, '2026-03-10', 'unpaid');

-- Test Views


-- Case 1:Students left the dormitory but still have overdue invoices
-- Update the contract to ended and check if the student still appears in the overdue debtors view
UPDATE contracts
SET STATUS = 'ended', end_date = '2026-03-20' 
WHERE student_id = 1;
-- Result: The student should still appear in the overdue debtors view for the month of 03/2026 since they had an active contract during that month and the invoice is unpaid
SELECT * FROM vw_overdue_debtors WHERE student_id = 1;


-- Case 2: New student added to the same room but with a later contract start date, should not appear in the overdue debtors view for the month of 03/2026
-- Add a new student and contract for the same room starting in April 2026, then check the overdue debtors view for March 2026
INSERT INTO students (student_id, student_code, first_name, last_name, gender, email) 
VALUES (4, 'SV004', 'Le Thi', 'D', 'F', 'sv004@vnu.edu.vn');
INSERT INTO contracts (student_id, room_id, start_date, status) 
VALUES (4, 1, '2026-04-01', 'active');
-- Result: The new student should not appear in the overdue debtors view for March 2026 since their contract starts in April
SELECT * FROM vw_overdue_debtors WHERE room_id = 1 AND month = '2026-03-01';


-- Case 3: Update the contract back to active and check if the student appears again in the overdue debtors view
UPDATE contracts 
SET status = 'active', end_date = NULL WHERE student_id = 1;
-- Result: The student should appear again in the overdue debtors view for March 2026 since their contract is active again and the invoice is still unpaid
SELECT * FROM vw_overdue_debtors WHERE student_id = 1;
=======
-- RUN TESTS

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE contracts;
TRUNCATE TABLE students;
TRUNCATE TABLE rooms;

SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO students (student_id, student_code, last_name, first_name, email)
VALUES 
(1, 'SV001', 'Nguyen', 'Van A', 'a@gmail.com'),
(2, 'SV002', 'Nguyen', 'Van B', 'b@gmail.com'),
(3, 'SV003', 'Nguyen', 'Van C', 'c@gmail.com'),
(5, 'SV005', 'Nguyen', 'Van E', 'e@gmail.com');

INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, r_status)
VALUES (101, 2, 0, 0.00, 'available');

-- Add 1 people
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1, 101, CURDATE(), 'active');

-- Full 2 people
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (2, 101, CURDATE(), 'active');

-- Invalid (occupancy > capacity, room full)
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (3, 101, CURDATE(), 'active');

SELECT * FROM rooms;

-- Test active contact
INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, r_status)
VALUES (102, 2, 0, 0.00, 'available');

-- Test result: student already has an active account
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1, 102, CURDATE(), 'active');

-- Terminate/end contract
UPDATE contracts
SET status = 'ended'
WHERE student_id = 2 AND room_id = 101 AND status = 'active';

-- Room 101 has only 1 person
SELECT * FROM rooms;

-- Valid add
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (3, 101, CURDATE(), 'active');

-- Test Procedure sp_transfer_rooms (2.5 constraint)
INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, r_status)
VALUES (103, 2, 0, 0.00, 'available');

UPDATE contracts
SET status = 'ended'
WHERE student_id = 1 AND room_id = 101 AND status = 'active';

INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (3, 103, CURDATE(), 'active');

INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (5, 103, CURDATE(), 'active');

-- Test: Room is full or exceeds capacity
CALL sp_transfer_room(1, 103);
>>>>>>> origin/develop
