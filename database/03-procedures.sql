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

-- 2. Procedure: sp_trasfer_room
DELIMITER //

DELIMITER //

CREATE PROCEDURE sp_transfer_room(
    IN p_student_id INT,
    IN p_new_room_id INT
)
BEGIN
    DECLARE v_old_contract_id INT;
    DECLARE v_end_date DATE;
    DECLARE v_curr_occ TINYINT UNSIGNED;
    DECLARE v_capacity INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errmsg = MESSAGE_TEXT;
        RESIGNAL; 
    END;

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
    
    -- 2.5. Lock new room and check capacity (BR-01, BR-03)
    SELECT current_occupancy, capacity
    INTO v_curr_occ, v_capacity
    FROM rooms
    WHERE room_id = p_new_room_id
    FOR UPDATE;

    IF v_curr_occ >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Room is full or exceeds capacity';
    END IF;

    -- 3. Create a new contract (Trigger BR-02 will check if step 2 freed the student)
    INSERT INTO contracts (student_id, room_id, start_date, status)
    VALUES (p_student_id, p_new_room_id, CURDATE(), 'active');

    -- Write log Success
    CALL sp_add_audit_log(
        'sp_transfer_room', 
        'TRANSFER_ROOM', 
        CONCAT('Successfully transferred student ', p_student_id, ' from room ', v_old_room_id, ' to room ', p_new_room_id), 
        NULL
    );

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
        RESIGNAL SET MESSAGE_TEXT = v_message;
	END;
    
    -- 3.3. Check input     
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
        GREATEST(0, COALESCE(m.electric_new - m.electric_old, 0)) * v_elec_price ,
        GREATEST(0, COALESCE(m.water_new - m.water_old, 0)) * v_water_price,
        v_service_fee,
        
        -- Calculate total amount sum
        (r.base_price + 
        GREATEST(0, COALESCE(m.electric_new - m.electric_old, 0)) * v_elec_price +
        GREATEST(0, COALESCE(m.water_new - m.water_old, 0)) * v_water_price +
        v_service_fee),
        
        DATE_ADD(DATE_ADD(p_month, INTERVAL 1 MONTH), INTERVAL 14 DAY),
        'unpaid'
    FROM rooms r
    LEFT JOIN meter_readings m ON r.room_id = m.room_id AND m.month = p_month
    WHERE r.status <> 'maintenance' AND r.current_occupancy > 0
		AND (p_room_id IS NULL OR r.room_id = p_room_id) -- Filter by specific room or ALL
        
	-- If invoice already exists for this month, update the amount instead of duplicating
    ON DUPLICATE KEY UPDATE
		room_fee     = IF(paid_status = 'paid', invoices.room_fee, VALUES(room_fee)),
		electric_fee = IF(paid_status = 'paid', invoices.electric_fee, VALUES(electric_fee)),
        water_fee    = IF(paid_status = 'paid', invoices.water_fee, VALUES(water_fee)),
        service_fee  = IF(paid_status = 'paid', invoices.service_fee, VALUES(service_fee)),
        total_amount = IF(paid_status = 'paid', invoices.total_amount, VALUES(total_amount)),
        due_date     = IF(paid_status = 'paid', invoices.due_date, VALUES(due_date));
    CALL sp_add_audit_log(
    'sp_generate_monthly_invoices',
    'SUCCESS', 
    CONCAT('Generated monthly invoice for month ', p_month, '. Room Filter: ', IFNULL(p_room_id, 'ALL')), 
    NULL);
    
END //

DELIMITER ;