DELIMITER //

DROP PROCEDURE IF EXISTS sp_transfer_room //

CREATE PROCEDURE sp_transfer_room(
    IN p_student_id INT,
    IN p_new_room_id INT,
    IN p_effective_date DATE
)
BEGIN
    DECLARE v_current_count INT;
    DECLARE v_capacity INT;
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_old_contract_id INT;
    DECLARE v_old_room_id INT;
    DECLARE v_start_next_month DATE;

    DECLARE v_sqlstate CHAR(5); 
    DECLARE v_errmsg TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errmsg = MESSAGE_TEXT;

        ROLLBACK;

        CALL sp_add_audit_log(USER(), 'sp_transfer_room', v_errmsg, v_sqlstate);
        
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Select current active contract for the student
    SELECT contract_id, room_id INTO v_old_contract_id, v_old_room_id
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    LIMIT 1
    FOR UPDATE;

    IF v_old_contract_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student has no active contract';
    END IF;

    IF v_old_room_id = p_new_room_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student is already in this room';
    END IF;

    -- Take room lock and check capacity + maintenance status
    SELECT capacity, current_occupancy, status 
    INTO v_capacity, v_current_count, v_room_status
    FROM rooms 
    WHERE room_id = p_new_room_id 
    FOR UPDATE;

    IF v_room_status = 'maintenance' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room under maintenance';
    END IF;

    IF v_current_count >= v_capacity THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room is full';
    END IF;

    IF p_effective_date <> LAST_DAY(p_effective_date) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer only allowed at month end';
    END IF;

    -- End old contract and create new one
    SET v_start_next_month = DATE_ADD(p_effective_date, INTERVAL 1 DAY);

    UPDATE contracts SET end_date = p_effective_date, status = 'ended'
    WHERE contract_id = v_old_contract_id;

    INSERT INTO contracts (student_id, room_id, start_date, status)
    VALUES (p_student_id, p_new_room_id, v_start_next_month, 'active');

    CALL sp_add_audit_log(
        USER(), 
        'TRANSFER_ROOM', 
        CONCAT('Successfully transferred student ', p_student_id, ' from room ', v_old_room_id, ' to room ', p_new_room_id), 
        NULL
    );

    COMMIT; 
END //

DELIMITER ;

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