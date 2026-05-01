USE dormitory_management;

DROP TRIGGER IF EXISTS trg_contracts_before_insert;
DROP TRIGGER IF EXISTS trg_contracts_after_insert;
DROP TRIGGER IF EXISTS trg_contracts_after_update;
DROP TRIGGER IF EXISTS trg_contracts_after_delete;

DELIMITER //
 -- 1. Trigger before insert on contracts
CREATE TRIGGER trg_contracts_before_insert
BEFORE INSERT ON contracts
FOR EACH ROW
BEGIN
    DECLARE v_capacity INT;
    DECLARE v_occupancy INT;
    DECLARE v_room_status VARCHAR(20);
    DECLARE v_active_count INT;
    DECLARE v_not_found INT DEFAULT 0;

     DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = 1;
 
    -- Check room exists + get info
    SELECT capacity, current_occupancy, status
    INTO v_capacity, v_occupancy, v_room_status
    FROM rooms
    WHERE room_id = NEW.room_id
    FOR UPDATE; -- Sử dụng để khóa dữ liệu khi có 1 sinh viên thực hiện đăng ký vào phòng, tránh tình trạng race condition
 
    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room does not exist';
    END IF;
 
    -- Check room under maintenance
    IF v_room_status = 'maintenance' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is under maintenance';
    END IF;
 
    -- Check BR-01: room full
    IF LOWER(NEW.status) = 'active' AND v_occupancy >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is full';
    END IF;
 
    -- Check BR-02: student already has active contract
    SELECT COUNT(*) INTO v_active_count
    FROM contracts
    WHERE student_id = NEW.student_id AND status = 'active';
 
    IF LOWER(NEW.status) = 'active' AND v_active_count >= 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Student already has an active contract';
    END IF;
END //

-- 2. TRigger after insert on Contracts
CREATE TRIGGER trg_contracts_after_insert
AFTER INSERT ON contracts
FOR EACH ROW
BEGIN
    IF LOWER(NEW.status) = 'active' THEN
        UPDATE rooms
        SET status = IF((current_occupancy + 1) >= capacity, 'full', 'available'),
            current_occupancy = current_occupancy + 1
        WHERE room_id = NEW.room_id;
        call sp_add_audit_log(USER(), 'INSERT_CONTRACT', CONCAT('Contract ', NEW.contract_id, ' inserted'), 'SUCCESS');
    END IF;
END //

-- 3. Trigger after Update on contracts (support test case 2: new room is available, change room successfully. test case 6: update contract to end it, occupancy should decrease and room status should update)
CREATE TRIGGER trg_contracts_after_update
AFTER UPDATE ON contracts
FOR EACH ROW
BEGIN
    -- case A: activate contract 
    IF LOWER(OLD.status) <> 'active' AND LOWER(NEW.status) = 'active' THEN
        UPDATE rooms 
        SET status = IF((current_occupancy + 1) >= capacity, 'full', 'available'),
            current_occupancy = current_occupancy + 1
        WHERE room_id = NEW.room_id;
        CALL sp_add_audit_log(USER(), 'ACTIVATE_CONTRACT', CONCAT('Contract ', NEW.contract_id, ' activated'), 'SUCCESS');
    
    -- case B: end contract (Always set to available)
    ELSEIF LOWER(OLD.status) = 'active' AND LOWER(NEW.status) IN ('ended', 'cancelled') THEN
        UPDATE rooms 
        SET status = Case
               when status = 'maintenance' then 'maintenance'
               when GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0) >= capacity then 'full'
               else 'available'
			end,
            current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0)
        WHERE room_id = OLD.room_id;
        CALL sp_add_audit_log(USER(), 'DEACTIVATE_CONTRACT', CONCAT('Contract ', OLD.contract_id, ' ended'), 'SUCCESS');
   END IF;
END //

-- 4. Trigger after DELETE on contracts (Test Case 6 - incorrectly deleting a contract)
CREATE TRIGGER trg_contracts_after_delete
AFTER DELETE ON contracts
FOR EACH ROW
BEGIN
    -- Only update occupancy if the deleted contract was active
    IF LOWER(OLD.status) = 'active' THEN
        UPDATE rooms 
        SET status = Case
           when status = 'maintenance' then 'maintenance'
           else 'available'
           end,
            current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0)
        WHERE room_id = OLD.room_id;    

        call sp_add_audit_log(USER(), 'DELETE_CONTRACT', CONCAT('Active contract ', OLD.contract_id, ' deleted. Occupancy restored.'), 'WARNING');
	end if;
END //

DELIMITER ;
