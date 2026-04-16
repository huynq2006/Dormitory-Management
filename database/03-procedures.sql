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


-- 2.Procedure: sp_generate_monthly_invoices

DELIMITER //

DROP PROCEDURE IF EXISTS sp_generate_monthly_invoices //

CREATE PROCEDURE sp_generate_monthly_invoices(
	IN p_room_id INT,
    IN p_month DATE
)
BEGIN
	-- 2.1. Pricing configuration & Variable declarations
	DECLARE v_elec_price DECIMAL(12,2) DEFAULT 3000.00;
    DECLARE v_water_price DECIMAL(12,2) DEFAULT 10000.00;
    DECLARE v_service_fee DECIMAL(12,2) DEFAULT 100000.00;
    
    DECLARE v_sqlstate VARCHAR(5);
    DECLARE v_message TEXT;
    
    -- 2.2. Error handling
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
		GET DIAGNOSTICS CONDITION 1
			v_sqlstate = RETURNED_SQLSTATE,
            v_message = MESSAGE_TEXT;
		ROLLBACK TO SAVEPOINT sp_generate_monthly_invoices;   
		CALL sp_add_audit_log('sp_generate_monthly_invoices', 'ERROR', CONCAT('User: ', USER(), ' | ', v_message), v_sqlstate);
        COMMIT;
        RESIGNAL;
	END;
    
    -- 2.3. Start financial transaction 
    START TRANSACTION;
    SAVEPOINT sp_generate_monthly_invoices;
    
    IF DAY(p_month) != 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Month parameter must be the 1st day of the month (YYYY-MM-01).';
    END IF;

	IF p_room_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM rooms WHERE room_id = p_room_id) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Room ID does not exist.';
    END IF;
    
    -- 2.4. Insert or update (IDEMPOTENT) & Calculate Ulities
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
        
        DATE_ADD(DATE_ADD(p_month, INTERVAL 1 MONTH), INTERVAL 14 DAY),
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
	
    CALL sp_add_audit_log(
    'sp_generate_monthly_invoices',
    'SUCCESS', 
    CONCAT('Generated monthly invoice for month ', p_month, '. Room Filter: ', IFNULL(p_room_id, 'ALL')), 
    NULL);
    
	COMMIT;
END //

DELIMITER ;