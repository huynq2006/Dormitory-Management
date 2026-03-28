-- CONDITION TO CHECK A ROOM (EXISTS, CURRENT NUMBER OF OCCUPANTS)
-- CONDITION TO ENSURE A STUDENT RENTS ONLY ONE ROOM

DELIMITER //

-- If a contract changes from 'active' to 'ended' or 'cancelled', decrease room occupancy
CREATE TRIGGER trg_decrease_occupancy
AFTER UPDATE ON contracts
FOR EACH ROW
BEGIN
    IF OLD.status = 'active' AND NEW.status IN ('ended','cancelled') THEN
        UPDATE rooms
        SET current_occupancy = GREATEST(current_occupancy - 1, 0)
        WHERE room_id = OLD.room_id;
    END IF;
END //

DELIMITER ;

DELIMITER //

CREATE TRIGGER trg_before_insert_contract
BEFORE INSERT ON contracts
FOR EACH ROW
BEGIN
    DECLARE cur_occupance INT;
    DECLARE cur_capacity INT;
    DECLARE active_count INT;

-- Check if room exists + get capacity
    SELECT capacity, current_occupancy
    INTO cur_capacity, cur_occupance
    FROM rooms
    WHERE room_id = NEW.room_id;

    IF cur_capacity IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room does not exist';
    END IF;
-- Check if room is full
    IF cur_occupance >= cur_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is full';
    END IF;

-- Check 1 active contract
    SELECT COUNT(*) INTO active_count 
    FROM contracts 
    WHERE student_id = NEW.student_id AND status = 'active';

    IF active_count >= 1 AND NEW.status = 'active' THEN
        SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Student already has an active contract';
    END IF;

END //

DELIMITER ;

-- CONDITION TO ADD ONE STUDENT TO ONE ROOM

DELIMITER //

CREATE TRIGGER update_occupancy
AFTER INSERT ON contracts
FOR EACH ROW
BEGIN 
	UPDATE rooms
    SET current_occupancy = current_occupancy + 1 
    WHERE room_id = NEW.room_id;
END //

DELIMITER ;