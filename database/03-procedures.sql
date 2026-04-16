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
    DECLARE v_room_exists INT;
    DECLARE v_is_active_student INT DEFAULT 0;
    DECLARE v_active_contract_count INT DEFAULT 0;

    DECLARE v_sqlstate CHAR(5); 
    DECLARE v_errmsg TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errmsg = MESSAGE_TEXT;

        ROLLBACK;

        CALL sp_add_audit_log('sp_transfer_room','ERROR', v_errmsg, v_sqlstate);
        
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_is_active_student 
    FROM students 
    WHERE student_id = p_student_id AND status = 1;

    IF v_is_active_student = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student does not exist or is inactive';
    END IF;

    SELECT COUNT(*) INTO v_active_contract_count 
    FROM contracts 
    WHERE student_id = p_student_id AND status = 'active';

    IF v_active_contract_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student has no active contract';
    
    ELSEIF v_active_contract_count > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Data integrity issue: student has multiple active contracts';
    END IF;

    -- Select current active contract for the student
    SELECT contract_id, room_id INTO v_old_contract_id, v_old_room_id
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    FOR UPDATE;

    IF v_old_contract_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student has no active contract';
    END IF;

    IF v_old_room_id = p_new_room_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student is already in this room';
    END IF;

    SELECT COUNT(*) INTO v_room_exists FROM rooms WHERE room_id = p_new_room_id;
    IF v_room_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room does not exist';
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

    IF CURDATE() <> LAST_DAY(CURDATE()) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer only allowed exactly on the last day of the month';
    END IF;
    
    IF p_effective_date <> LAST_DAY(CURDATE()) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer only allowed at current month end';
    END IF;

    -- End old contract and create new one
    SET v_start_next_month = DATE_ADD(p_effective_date, INTERVAL 1 DAY);

    UPDATE contracts SET end_date = p_effective_date, status = 'ended'
    WHERE contract_id = v_old_contract_id;

    INSERT INTO contracts (student_id, room_id, start_date, status)
    VALUES (p_student_id, p_new_room_id, v_start_next_month, 'active');

    CALL sp_add_audit_log(
        'sp_transfer_room', 
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