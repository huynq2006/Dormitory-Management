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
        ROLLBACK; -- If an error occurs (e.g., new room is full), rollback the transaction
    END;

    START TRANSACTION;

	-- 1. Find the student's active contract
    SELECT contract_id, end_date INTO v_old_contract_id, v_end_date
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    LIMIT 1;

    IF v_old_contract_id IS NOT NULL THEN
	-- 2. Your logic: Check if contract is expired
	-- If today > end_date, consider the old contract naturally ended
	-- Here we update the old contract to 'ended' to free the student
        UPDATE contracts 
        SET status = 'ended', 
            end_date = IF(v_end_date < CURDATE(), v_end_date, CURDATE())
        WHERE contract_id = v_old_contract_id;
    END IF;

    -- 3. Create a new contract (Trigger BR-02 will check if step 2 freed the student)
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