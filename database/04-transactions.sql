DELIMITER //

DROP PROCEDURE IF EXISTS sp_transfer_room $$

CREATE PROCEDURE sp_transfer_room(
    IN p_student_id INT,
    IN p_new_room_id INT
)
BEGIN
    DECLARE v_current_count INT;
    DECLARE v_capacity INT;
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_old_contract_id INT;
    DECLARE v_old_room_id INT;

    DECLARE v_sqlstate CHAR(5); 
    DECLARE v_errmsg TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errmsg = MESSAGE_TEXT;

        ROLLBACK TO SAVEPOINT sp_start_transfer;

        INSERT INTO audit_log (log_time, actor, action, detail, error_code)
        VALUES (NOW(), 'sp_transfer_room', 'ERROR', v_errmsg, v_sqlstate);

        COMMIT;
        
        RESIGNAL;
    END;

    START TRANSACTION;

    SAVEPOINT sp_start_transfer;

    -- Select current active contract for the student
    SELECT contract_id, room_id INTO v_old_contract_id, v_old_room_id
    FROM contracts
    WHERE student_id = p_student_id AND status = 'active'
    LIMIT 1;
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

    -- End old contract and create new one
    UPDATE contracts SET status = 'ended', end_date = CURRENT_DATE 
    WHERE contract_id = v_old_contract_id;

    INSERT INTO contracts (student_id, room_id, start_date, status) 
    VALUES (p_student_id, p_new_room_id, CURRENT_DATE, 'active');

    INSERT INTO audit_log (log_time, actor, action, detail, error_code)
    VALUES (NOW(), 'sp_transfer_room', 'TRANSFER_ROOM', CONCAT('Transferred student ', p_student_id, ' to room ', p_new_room_id), NULL);

    COMMIT;
END //

DELIMITER ;