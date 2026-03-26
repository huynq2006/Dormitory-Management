-- ĐIỀU KIỆN KIỂM TRA 1 PHÒNG (TỒN TẠI, SỐ LƯỢNG SINH VIÊN ĐANG THUÊ)
-- ĐIỀU KIỆN KIỂM TRA SINH VIÊN CHỈ THUÊ 1 PHÒNG

CREATE TRIGGER trg_before_insert_contract
BEFORE INSERT ON contracts
FOR EACH ROW
BEGIN
    DECLARE cur_occupance INT;
    DECLARE cur_capacity INT;
    DECLARE active_count INT;

    -- CHECK ROON TỒN TẠI, CAPACITY
    SELECT capacity, current_occupancy
    INTO cur_capacity, cur_occupance
    FROM rooms
    WHERE room_id = NEW.room_id;

    IF cur_capacity IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room không tồn tại';
    END IF;

    IF cur_occupance >= cur_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Phòng đã đầy';
    END IF;

    -- CHECK 1 ACTIVE ACCOUNT
    SELECT COUNT(*) INTO active_count 
    FROM contracts 
    WHERE student_id = NEW.student_id AND status = 'active';

    IF active_count >= 1 AND NEW.status = 'active' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sinh viên đã có hợp đồng active';
    END IF;

END //

DELIMITER ;

-- ĐIỀU KIỆN ADD THÊM SINH VIÊN TẠI 1 PHÒNG

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

-- ĐIỀU KIỆN HẾT HẠN/CHẤM DỨT HỢP ĐỒNG

DELIMITER //

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
