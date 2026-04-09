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

-- 2. Procedure: sp_transfer_room
DELIMITER //

DROP PROCEDURE IF EXISTS sp_transfer_room //

CREATE PROCEDURE sp_transfer_room(
    IN p_student_id INT,
    IN p_new_room_id INT
)
BEGIN
    DECLARE v_old_contract_id INT;
    DECLARE v_old_room_id INT;
    DECLARE v_curr_occ TINYINT UNSIGNED;
    DECLARE v_capacity INT UNSIGNED;
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_end_date DATE;
    
    -- audit_log handler added to transfer room
	DECLARE v_sqlstate VARCHAR(5);
    DECLARE v_message TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
		GET DIAGNOSTICS CONDITION 1
			v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
		ROLLBACK TO SAVEPOINT sp_start_transfer;
		-- Log the failure
        CALL sp_add_audit_log(
			'sp_transfer_room', 
            'ERROR',
			CONCAT('User: ', USER(), ' | Error: ', v_message),
            v_sqlstate);
		COMMIT;
        RESIGNAL;
    END;

	START TRANSACTION;
    SAVEPOINT sp_start_transfer;

	-- 2.1. Find the student's active contract
    SELECT contract_id, room_id, end_date INTO v_old_contract_id, v_old_room_id, v_end_date
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    ORDER BY contract_id DESC
    LIMIT 1 FOR UPDATE;

    IF v_old_contract_id IS NULL THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student does not have an active contract to transfer.';
	END IF;
	IF v_old_room_id = p_new_room_id THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student is already in this room.';
	END IF;
    
    -- 2.2. Lock new room and check capacity (BR-01, BR-03)
    SELECT current_occupancy, capacity, status
    INTO v_curr_occ, v_capacity, v_room_status
    FROM rooms
    WHERE room_id = p_new_room_id
    FOR UPDATE;

	IF v_room_status = 'maintenance' THEN
	SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room under maintenance';
    END IF;
    
    IF v_curr_occ >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Room is full';
	END IF;
    
    -- 2.3. Execute updates (BR-06)
	UPDATE contracts
	SET status = 'ended',
	end_date = LAST_DAY(CURDATE())
	WHERE contract_id = v_old_contract_id;

    -- 2.4. Create a new contract on 01 of next month
    INSERT INTO contracts (student_id, room_id, start_date, status)
    VALUES (p_student_id, p_new_room_id, DATE_ADD(LAST_DAY(CURDATE()), INTERVAL 1 DAY), 'active');

    CALL sp_add_audit_log(
    USER(), 
    'sp_transfer_room', 
    CONCAT('Transferred student ', p_student_id, ' from room ', v_old_room_id, ' to room ', p_new_room_id), NULL);
	COMMIT;
END //

DELIMITER ;

-- 3.Procedure: sp_generate_monthly_invoices

DELIMITER //

DROP PROCEDURE IF EXISTS sp_generate_monthly_invoices //

CREATE PROCEDURE sp_generate_monthly_invoices(
    IN p_month DATE
)
BEGIN
    -- audit_log handler added to financial transaction
    DECLARE v_sqlstate VARCHAR(5);
    DECLARE v_message TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
		GET DIAGNOSTICS CONDITION 1
			v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
		ROLLBACK;   
		CALL sp_add_audit_log(USER(), 'sp_generate_monthly_invoices', v_message, v_sqlstate);
        RESIGNAL;
	END;
    
    IF DAY(p_month) != 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Month parameter must be the 1st day of the month (YYYY-MM-01).';
    END IF;

    -- Insert or update (IDEMPOTENT)
    INSERT INTO invoices (
        room_id, month, room_fee,
        electric_fee, water_fee, service_fee,
        total_amount, due_date, paid_status
    )
    SELECT
        room_id,
        p_month,
        base_price,
        0, 0, 0,
        base_price,
        DATE_ADD(p_month, INTERVAL 15 DAY),
        'unpaid'
    FROM rooms
    WHERE status = 'active' AND current_occupancy > 0
    ON DUPLICATE KEY UPDATE
        room_fee = VALUES(room_fee),
        total_amount = VALUES(room_fee) + electric_fee + water_fee + service_fee,
        due_date = VALUES(due_date);

    CALL sp_add_audit_log(
    USER(),
    'sp_generate_monthly_invoices', 
    CONCAT('Generated monthly invoice for all active rooms for month ', p_month), 
    NULL);
END //

DELIMITER ;