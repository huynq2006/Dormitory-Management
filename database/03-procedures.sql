-- Procedure: sp_generate_monthly_invoices

DELIMITER //

CREATE PROCEDURE sp_generate_monthly_invoices(
    IN p_room_id INT,
    IN p_month DATE
)
BEGIN
    DECLARE v_room_fee DECIMAL(12,2);

    -- Get room price
    SELECT base_price INTO v_room_fee
    FROM rooms
    WHERE room_id = p_room_id;

    -- Insert or update (IDEMPOTENT)
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