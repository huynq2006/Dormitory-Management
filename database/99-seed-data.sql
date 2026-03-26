-- RUN TESTS

SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE contracts;
TRUNCATE TABLE students;
TRUNCATE TABLE rooms;

SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO students (student_id, student_code, full_name, email)
VALUES 
(1, 'SV001', 'Nguyen Van A', 'a@gmail.com'),
(2, 'SV002', 'Nguyen Van B', 'b@gmail.com'),
(3, 'SV003', 'Nguyen Van C', 'c@gmail.com');


INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, status)
VALUES (101, 2, 0, 0.00, 'available');

-- ADD 1 NGƯỜI
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1, 101, CURDATE(), 'active');

-- ĐỦ 2 NGƯỜI
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (2, 101, CURDATE(), 'active');

-- INVALID (OCCUPANCY > CAPACITY, PHÒNG ĐẦY) 
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (3, 101, CURDATE(), 'active');

SELECT * FROM rooms;

-- TEST HỢP ĐỒNG ACTIVE
INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, status)
VALUES (102, 2, 0, 0.00, 'available');

-- KẾT QUẢ TEST: SINH VIÊN ĐÃ CÓ HỢP ĐỒNG ACTIVE!
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (1, 102, CURDATE(), 'active');

-- HẾT HẠN/CHẤM DỨT HỢP ĐỒNG
UPDATE contracts
SET status = 'ended'
WHERE student_id = 2 AND room_id = 101 AND status = 'active';

-- PHÒNG 101 CÒN ĐÚNG 1 NGƯỜI
SELECT * FROM rooms;

-- ADD HỢP LỆ 
INSERT INTO contracts (student_id, room_id, start_date, status)
VALUES (3, 101, CURDATE(), 'active');