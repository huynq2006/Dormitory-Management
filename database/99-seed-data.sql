-- 1. xóa dữ liệu cũ
SET FOREIGN_KEY_CHECKS = 0;
TRUNCATE TABLE contracts;
TRUNCATE TABLE rooms;
TRUNCATE TABLE students;
TRUNCATE TABLE audit_log;
TRUNCATE TABLE invoices;
TRUNCATE TABLE meter_readings;
SET FOREIGN_KEY_CHECKS = 1;

-- 2. tạo dữ liệu giả
INSERT INTO rooms (room_id, capacity, current_occupancy, base_price, status) VALUES
  (101, 4, 0, 1500000.00, 'available'),        
  (301, 3, 0, 1300000.00, 'available');    
  
INSERT INTO students (student_id, student_code, first_name, last_name, gender, email, status) VALUES
  (1001, 'SV1001', 'Anh',   'Nguyen', 'M', 'anh@vnu.edu.vn',   1),
  (3001, 'SV3001', 'An',    'Dang',   'M', 'an@vnu.edu.vn',    1),
  (3002, 'SV3002', 'Bao',   'Hoang',  'M', 'bao@vnu.edu.vn',   1),
  (3003, 'SV3003', 'Chi',   'Vu',     'F', 'chi@vnu.edu.vn',   1);
 
INSERT INTO contracts (student_id, room_id, start_date, status) VALUES
  (3001, 301, '2026-03-01', 'active'),
  (3002, 301, '2026-03-01', 'active'),
  (3003, 301, '2026-03-01', 'active');
-- Truyền số điện và số nước đã dùng trong tháng 
INSERT INTO meter_readings (room_id, month, electric_old, electric_new, water_old, water_new)
VALUES (301, '2026-03-01', 0, 100, 0, 15);

-- 3. Gọi sp_generate_monthly_invoices để chốt hóa đơn và kiểm tra kết quả tính toán
	-- CASE 1: sai định dạng ngày truyền 
    call sp_generate_monthly_invoices (301, '2026-03-15');
    
    -- CASE 2: đảm bảo Idempotent không tạo trùng 
       -- lần 1: mong muốn tạo 1 dòng hóa đơn với tổng tiền 1tr850
		call sp_generate_monthly_invoices (301, '2026-03-01');
        -- kiểm tra 
        select room_id, month, total_amount, 'chạy lần 1' as status 
        from invoices where room_id = 301 and month = '2026-03-01';
        
	   -- lần 2: mong muốn không tạo thêm, không báo lỗi
       call sp_generate_monthly_invoices (301, '2026-03-01');
        -- kiểm tra 
        select room_id, month, total_amount, 'chạy lần 2' as status 
        from invoices where room_id = 301 and month = '2026-03-01';
        
	   -- lần 3: cập nhật số điện: 80 số, số nước: 7 khối
		update meter_readings 
        set electric_new = 80,
			water_new = 7
        where room_id = 301 and month = '2026-03-01';
        call sp_generate_monthly_invoices (301, '2026-03-01');
        select * from invoices;
	
    -- kiểm tra audig_log cho CASE 1 + 2
    select * from audit_log;
    
	-- CASE 3: chốt hóa đơn cho phòng đang có sinh viên
		-- B1: tạo contract cho 1 sv phòng 101
		INSERT INTO contracts (contract_id, student_id, room_id, start_date, status)
		VALUES (4, 1001, 101, '2026-03-01', 'active');
		
		-- B2: truyền số điện và số nước đã dùng trong tháng
		INSERT INTO meter_readings (reading_id, room_id, month, electric_old, electric_new, water_old, water_new)
		VALUES (2, 101, '2026-03-01', 0, 30, 0, 3);
		
		-- B3: gọi procedure tính tiền tiền và kiểm tra
		call sp_generate_monthly_invoices (101, '2026-03-01');
		select * from invoices where room_id = 101;
  
	-- CASE 4: lưu hóa đơn còn nợ, khi hợp đồng đã kết thúc
		-- B1: Kết thúc TẤT CẢ hợp đồng của phòng 301 để đảm bảo phòng không còn ai
		UPDATE contracts
		SET status = 'ended',
			end_date = '2026-03-31'
		WHERE room_id = 301 AND status = 'active';

		-- Bước 2: Kiểm tra xem Trigger đã trả phòng về 0 người chưa
		-- Kỳ vọng: current_occupancy = 0 và status = 'available'
		SELECT room_id, current_occupancy, status 
		FROM rooms 
		WHERE room_id = 301;

		-- Bước 3: Kiểm tra hóa đơn
		-- Kỳ vọng: Bảng vẫn giữ nguyên hóa đơn của phòng 301 (số tiền nợ vẫn còn đó)
		SELECT invoice_id, room_id, month, total_amount, paid_status 
		FROM invoices 
		WHERE room_id = 301;


 


