USE dormitory_management;


-- XÓA CÁC TRIGGER CŨ NẾU ĐÃ TỒN TẠI (Đảm bảo môi trường sạch)

DROP TRIGGER IF EXISTS trg_contracts_before_insert;
DROP TRIGGER IF EXISTS trg_contracts_after_insert;
DROP TRIGGER IF EXISTS trg_contracts_after_update;
DROP TRIGGER IF EXISTS trg_contracts_after_delete;

DELIMITER //


-- 1. TRIGGER BEFORE INSERT: Kiểm tra logic nghiệp vụ trước khi tạo hợp đồng

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
 
    -- Lock dòng dữ liệu của phòng để tránh Race Condition khi có nhiều luồng cùng insert
    SELECT capacity, current_occupancy, status
    INTO v_capacity, v_occupancy, v_room_status
    FROM rooms
    WHERE room_id = NEW.room_id
    FOR UPDATE; 
 
    -- Check BR: Phòng không tồn tại
    IF v_not_found = 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room does not exist';
    END IF;
 
    -- Check BR: Phòng đang bảo trì
    IF v_room_status = 'maintenance' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is under maintenance';
    END IF;
 
    -- Check BR: Phòng đã đầy
    IF LOWER(NEW.status) = 'active' AND v_occupancy >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Room is full';
    END IF;
 
    -- Check BR: Sinh viên đã có hợp đồng active khác
    SELECT COUNT(*) INTO v_active_count
    FROM contracts
    WHERE student_id = NEW.student_id AND status = 'active';
 
    IF LOWER(NEW.status) = 'active' AND v_active_count >= 1 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Student already has an active contract';
    END IF;
END //


-- 2. TRIGGER AFTER INSERT: Cập nhật số người và trạng thái phòng sau khi thêm

CREATE TRIGGER trg_contracts_after_insert
AFTER INSERT ON contracts
FOR EACH ROW
BEGIN
    IF LOWER(NEW.status) = 'active' THEN
        UPDATE rooms
<<<<<<< HEAD
        SET current_occupancy = current_occupancy + 1,
            -- Đánh giá trực tiếp trên giá trị vừa cộng
            status = IF(current_occupancy >= capacity, 'full', 'available')
=======
        SET status = IF((current_occupancy + 1) >= capacity, 'full', 'available'),
            current_occupancy = current_occupancy + 1
>>>>>>> origin/develop
        WHERE room_id = NEW.room_id;
        
        CALL sp_add_audit_log(USER(), 'INSERT_CONTRACT', CONCAT('Contract ', NEW.contract_id, ' inserted'), 'SUCCESS');
    END IF;
END //
 
-- 3. TRIGGER AFTER UPDATE: Xử lý khi hợp đồng thay đổi trạng thái

<<<<<<< HEAD
=======
-- 3. Trigger after Update on contracts (support test case 2: new room is available, change room successfully. test case 6: update contract to end it, occupancy should decrease and room status should update)
>>>>>>> origin/develop
CREATE TRIGGER trg_contracts_after_update
AFTER UPDATE ON contracts
FOR EACH ROW
BEGIN
    -- Case A: Hợp đồng từ trạng thái khác chuyển sang 'active' (Kích hoạt hợp đồng)
    IF LOWER(OLD.status) <> 'active' AND LOWER(NEW.status) = 'active' THEN
        UPDATE rooms 
<<<<<<< HEAD
        SET current_occupancy = current_occupancy + 1,
            status = IF(current_occupancy >= capacity, 'full', 'available')
=======
        SET status = IF((current_occupancy + 1) >= capacity, 'full', 'available'),
            current_occupancy = current_occupancy + 1
>>>>>>> origin/develop
        WHERE room_id = NEW.room_id;
        
        CALL sp_add_audit_log(USER(), 'ACTIVATE_CONTRACT', CONCAT('Contract ', NEW.contract_id, ' activated'), 'SUCCESS');
    
    -- Case B: Hợp đồng đang 'active' bị chuyển thành 'ended' hoặc 'cancelled' (Kết thúc/Hủy hợp đồng)
    ELSEIF LOWER(OLD.status) = 'active' AND LOWER(NEW.status) IN ('ended', 'cancelled') THEN
        UPDATE rooms 
<<<<<<< HEAD
        SET current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0),
            status = CASE
               WHEN status = 'maintenance' THEN 'maintenance'
               WHEN current_occupancy >= capacity THEN 'full'
               ELSE 'available'
            END
=======
        SET status = Case
               when status = 'maintenance' then 'maintenance'
               when GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0) >= capacity then 'full'
               else 'available'
			end,
            current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0)
>>>>>>> origin/develop
        WHERE room_id = OLD.room_id;
        
        CALL sp_add_audit_log(USER(), 'DEACTIVATE_CONTRACT', CONCAT('Contract ', OLD.contract_id, ' ended'), 'SUCCESS');
   END IF;
END //

<<<<<<< HEAD

-- 4. TRIGGER AFTER DELETE: Xử lý dọn dẹp khi lỡ xóa cứng (Hard Delete) hợp đồng

=======
-- 4. Trigger after DELETE on contracts (Test Case 6 - incorrectly deleting a contract)
>>>>>>> origin/develop
CREATE TRIGGER trg_contracts_after_delete
AFTER DELETE ON contracts
FOR EACH ROW
BEGIN
    -- Chỉ cập nhật lại số người nếu hợp đồng bị xóa đang ở trạng thái 'active'
    IF LOWER(OLD.status) = 'active' THEN
        UPDATE rooms 
<<<<<<< HEAD
        SET current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0),
            status = CASE
               WHEN status = 'maintenance' THEN 'maintenance'
               WHEN current_occupancy >= capacity THEN 'full'
               ELSE 'available'
            END
=======
        SET status = Case
           when status = 'maintenance' then 'maintenance'
           else 'available'
           end,
            current_occupancy = GREATEST(CAST(current_occupancy AS SIGNED) - 1, 0)
>>>>>>> origin/develop
        WHERE room_id = OLD.room_id;    

        CALL sp_add_audit_log(USER(), 'DELETE_CONTRACT', CONCAT('Active contract ', OLD.contract_id, ' deleted. Occupancy restored.'), 'WARNING');
    END IF;
END //

DELIMITER ;