USE dormitory_management;

DELIMITER //

-- 1. Trigger after INSERT on contracts (When a new contract is created)
DROP TRIGGER IF EXISTS trg_contracts_after_insert //
CREATE TRIGGER trg_contracts_after_insert
AFTER INSERT ON contracts
FOR EACH ROW
BEGIN
    -- Only update occupancy if the new contract is active
    IF NEW.status = 'active' THEN
        UPDATE rooms 
        SET current_occupancy = current_occupancy + 1 
        WHERE room_id = NEW.room_id;
        
        -- Log the contract creation action
        CALL sp_add_audit_log(USER(), 'INSERT_CONTRACT', 
            CONCAT('Student ', NEW.student_id, ' assigned to room ', NEW.room_id), 'SUCCESS');
    END IF;
END //

-- 2. Trigger after UPDATE on contracts (When a contract is updated, e.g., status change or room change)
DROP TRIGGER IF EXISTS trg_contracts_after_update //
CREATE TRIGGER trg_contracts_after_update
AFTER UPDATE ON contracts
FOR EACH ROW
BEGIN
    -- Case 1: Update status from non-active to active (e.g., new contract or re-activation)
    IF OLD.status <> 'active' AND NEW.status = 'active' THEN
        UPDATE rooms SET current_occupancy = current_occupancy + 1 WHERE room_id = NEW.room_id;
        CALL sp_add_audit_log(USER(), 'ACTIVATE_CONTRACT', CONCAT('Contract ', NEW.contract_id, ' activated'), 'SUCCESS');
    
    -- Case 2: Ending or deactivating a contract (status changes from active to non-active)
    ELSEIF OLD.status = 'active' AND NEW.status <> 'active' THEN
        UPDATE rooms SET current_occupancy = current_occupancy - 1 WHERE room_id = OLD.room_id;
        CALL sp_add_audit_log(USER(), 'DEACTIVATE_CONTRACT', CONCAT('Contract ', OLD.contract_id, ' ended'), 'SUCCESS');

    -- Case 3: Room change while contract is active
    ELSEIF OLD.status = 'active' AND NEW.status = 'active' AND OLD.room_id <> NEW.room_id THEN
        UPDATE rooms SET current_occupancy = current_occupancy - 1 WHERE room_id = OLD.room_id;
        UPDATE rooms SET current_occupancy = current_occupancy + 1 WHERE room_id = NEW.room_id;
        
        CALL sp_add_audit_log(USER(), 'TRANSFER_ROOM', 
            CONCAT('Student ', NEW.student_id, ' moved from room ', OLD.room_id, ' to ', NEW.room_id), 'SUCCESS');
    END IF;
END //

DELIMITER ;