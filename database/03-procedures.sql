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
	-- 2.1 Variable declarations
    DECLARE v_old_contract_id INT;
    DECLARE v_old_room_id INT;
    DECLARE v_curr_occ TINYINT UNSIGNED;
    DECLARE v_capacity INT UNSIGNED;
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_end_date DATE;
    
	DECLARE v_sqlstate VARCHAR(5);
    DECLARE v_message TEXT;
    -- 2.2 Error handling
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
		GET DIAGNOSTICS CONDITION 1
			v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
            
		ROLLBACK TO SAVEPOINT sp_start_transfer;

        CALL sp_add_audit_log(
			'sp_transfer_room', 
            'ERROR',
			CONCAT('User: ', USER(), ' | Error: ', v_message),
            v_sqlstate);
		COMMIT;
        RESIGNAL;
    END;

	-- 2.3 Start Transaction & Set Savepoint
	START TRANSACTION;
    SAVEPOINT sp_start_transfer;

	-- 2.4. Validate student's current contract
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
    
    -- 2.5. Lock new room and check capacity (BR-01, BR-03)
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
    
    -- 2.6. Execute transfer (BR-06)
	UPDATE contracts
	SET status = 'ended',
	end_date = LAST_DAY(CURDATE())
	WHERE contract_id = v_old_contract_id;

    -- 2.7. Create a new contract on 1st of next month
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
	IN p_room_id INT,
    IN p_month DATE
)
BEGIN
	-- 3.1. Pricing configuration & Variable declarations
	DECLARE v_elec_price DECIMAL(12,2) DEFAULT 3000.00;
    DECLARE v_water_price DECIMAL(12,2) DEFAULT 10000.00;
    DECLARE v_service_fee DECIMAL(12,2) DEFAULT 100000.00;
    
    DECLARE v_sqlstate VARCHAR(5);
    DECLARE v_message TEXT;
    
    -- 3.2. Error handling
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
		GET DIAGNOSTICS CONDITION 1
			v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
		ROLLBACK;   
		CALL sp_add_audit_log(USER(), 'sp_generate_monthly_invoices', v_message, v_sqlstate);
        RESIGNAL;
	END;
    
    -- 3.3. Start financial transaction 
    START TRANSACTION;
    
    IF DAY(p_month) != 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Month parameter must be the 1st day of the month (YYYY-MM-01).';
    END IF;

	IF p_room_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM rooms WHERE room_id = p_room_id) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room ID does not exist.';
    END IF;
    
    -- 3.4. Insert or update (IDEMPOTENT) & Calculate Ulities
    INSERT INTO invoices (
        room_id, month, room_fee,
        electric_fee, water_fee, service_fee,
        total_amount, due_date, paid_status
    )
    SELECT
        r.room_id,
        p_month,
        r.base_price,
        
        -- Calculate utility fees = ( new reading - old reading) * price
        (m.electric_new - m.electric_old) * v_elec_price ,
        (m.water_new - m.water_old) * v_water_price,
        v_service_fee,
        
        -- Calculate total amount sum
        (r.base_price + (m.electric_new - m.electric_old) * v_elec_price +
        (m.water_new - m.water_old) * v_water_price +
        v_service_fee),
        
        DATE_ADD(p_month, INTERVAL 15 DAY),
        'unpaid'
    FROM rooms r
    JOIN meter_readings m ON r.room_id = m.room_id AND m.month = p_month
    WHERE r.status <> 'maintenance' AND r.current_occupancy > 0
		AND (p_room_id IS NULL OR r.room_id = p_room_id) -- Filter by specific room or ALL
        
	-- If invoice already exists for this month, update the amount instead of duplicating
    ON DUPLICATE KEY UPDATE
        room_fee = VALUES(room_fee),
        electric_fee = VALUES(electric_fee),
        water_fee = VALUES(water_fee),
        service_fee = VALUES(service_fee),
        total_amount = VALUES(total_amount),
        due_date = VALUES(due_date);
	
    COMMIT;

    CALL sp_add_audit_log(
    USER(),
    'sp_generate_monthly_invoices', 
    CONCAT('Generated monthly invoice for month ', p_month, '. Room Filter: ', IFNULL(p_room_id, 'ALL')), 
    NULL);
END //

DELIMITER ;