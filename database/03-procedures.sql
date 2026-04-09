-- 1. Procedure: sp_add_audit_log
DELIMITER //

DROP PROCEDURE IF EXISTS sp_add_audit_log //

CREATE PROCEDURE sp_add_audit_log(
	IN actor VARCHAR(50),
    IN action VARCHAR(50),
    IN detail TEXT,
    IN error_code VARCHAR(20)
)
BEGIN
	INSERT INTO audit_log (log_time, actor, action, detail, error_code)
    VALUES (NOW(), actor, action, detail, error_code);
END //

DELIMITER ;

-- 2. Procedure: sp_auto_generate_all_invoices
DELIMITER //

DROP PROCEDURE IF EXISTS sp_auto_generate_all_invoices //

CREATE PROCEDURE sp_auto_generate_all_invoices(
    IN p_target_month DATE -- Định dạng YYYY-MM-01
)
BEGIN
    -- 1. Khai báo các biến đơn giá (Có thể đưa vào bảng cấu hình nếu cần)
    DECLARE v_elec_price DECIMAL(10,2) DEFAULT 3500.00;  -- 3500đ/kwh
    DECLARE v_water_price DECIMAL(10,2) DEFAULT 15000.00; -- 15000đ/m3
    DECLARE v_service_fee DECIMAL(10,2) DEFAULT 50000.00; -- Phí dịch vụ cố định
    
    -- Biến hỗ trợ Handler
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_message TEXT;

    -- 2. Handler xử lý lỗi
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_message = MESSAGE_TEXT;
        ROLLBACK;
        -- Ghi log lỗi vào hệ thống
        INSERT INTO audit_log (log_time, actor, action, detail, error_code)
        VALUES (NOW(), 'EVENT_AUTO_INVOICE', 'ERROR', 
                CONCAT('Lỗi tạo hóa đơn tháng ', p_target_month, ': ', v_message), v_sqlstate);
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 3. Logic tính toán và chèn dữ liệu hàng loạt
    -- Sử dụng INSERT INTO ... SELECT để quét toàn bộ phòng có chỉ số điện nước
    INSERT INTO invoices (
        room_id, month, room_fee, 
        electric_fee, water_fee, service_fee, 
        total_amount, due_date, paid_status
    )
    SELECT 
        r.room_id,
        p_target_month,
        r.base_price,
        -- Tiền điện = (Số mới - Số cũ) * Đơn giá
        (m.electric_new - m.electric_old) * v_elec_price,
        -- Tiền nước = (Số mới - Số cũ) * Đơn giá
        (m.water_new - m.water_old) * v_water_price,
        v_service_fee,
        -- Tổng tiền = Giá phòng + Tiền điện + Tiền nước + Dịch vụ
        (r.base_price + 
         (m.electric_new - m.electric_old) * v_elec_price + 
         (m.water_new - m.water_old) * v_water_price + 
         v_service_fee),
        DATE_ADD(p_target_month, INTERVAL 15 DAY),
        'unpaid'
    FROM rooms r
    JOIN meter_readings m ON r.room_id = m.room_id
    WHERE m.month = p_target_month
    -- Chống trùng lặp nếu Event chạy lại nhiều lần
    ON DUPLICATE KEY UPDATE
        room_fee = VALUES(room_fee),
        electric_fee = VALUES(electric_fee),
        water_fee = VALUES(water_fee),
        service_fee = VALUES(service_fee),
        total_amount = VALUES(total_amount),
        due_date = VALUES(due_date);

    -- 4. Ghi log thành công
    INSERT INTO audit_log (log_time, actor, action, detail, error_code)
    VALUES (NOW(), 'EVENT_AUTO_INVOICE', 'SUCCESS', 
            CONCAT('Đã hoàn thành tính toán hóa đơn tự động cho tháng ', p_target_month), NULL);

    COMMIT;
END //

DELIMITER ;