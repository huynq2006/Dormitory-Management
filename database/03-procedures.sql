-- contracts Procedure

DELIMITER //

CREATE PROCEDURE sp_transfer_room(
    IN p_student_id INT,
    IN p_new_room_id INT
)
BEGIN
    DECLARE v_old_contract_id INT;
    DECLARE v_end_date DATE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK; -- Nếu có lỗi (ví dụ: phòng mới đầy), hủy toàn bộ thao tác
    END;

    START TRANSACTION;

    -- 1. Tìm hợp đồng đang active của sinh viên
    SELECT contract_id, end_date INTO v_old_contract_id, v_end_date
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    LIMIT 1;

    IF v_old_contract_id IS NOT NULL THEN
        -- 2. Logic của bạn: Kiểm tra quá hạn
        -- Nếu hôm nay > end_date, coi như hợp đồng cũ đã kết thúc tự nhiên
        -- Ở đây ta cập nhật hợp đồng cũ về 'ended' để giải phóng sinh viên
        UPDATE contracts 
        SET status = 'ended', 
            end_date = IF(v_end_date < CURDATE(), v_end_date, CURDATE())
        WHERE contract_id = v_old_contract_id;
    END IF;

    -- 3. Tạo hợp đồng mới (Trigger BR-02 sẽ kiểm tra xem bước 2 đã giải phóng chưa)
    INSERT INTO contracts (student_id, room_id, start_date, status)
    VALUES (p_student_id, p_new_room_id, CURDATE(), 'active');

    COMMIT;
END //

DELIMITER ;

-- audit_log Procedure

DELIMITER //

CREATE PROCEDURE sp_generate_invoice(
    IN p_room_id INT,
    IN p_month DATE
)
BEGIN
    DECLARE v_room_fee DECIMAL(12,2);

    -- Lấy giá phòng
    SELECT base_price INTO v_room_fee
    FROM rooms
    WHERE room_id = p_room_id;

    -- Insert hoặc update (IDEMPOTENT)
    INSERT INTO invoices (
        room_id, month, room_fee,
        electric_fee, water_fee, service_fee,
        total_amount, due_date, paid_status
    )
    VALUES (
        p_room_id,
        p_month,
        v_room_fee,
        0, 0, 0,
        v_room_fee,
        DATE_ADD(p_month, INTERVAL 15 DAY),
        'unpaid'
    )
    ON DUPLICATE KEY UPDATE
        room_fee = VALUES(room_fee),
        total_amount = VALUES(total_amount),
        due_date = VALUES(due_date);
END //

DELIMITER ;