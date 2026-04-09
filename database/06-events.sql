
SHOW VARIABLES WHERE variable_name = 'event_scheduler';
SET GLOBAL event_scheduler = ON; 
use dormitory_management;
-- 1. Event scheduler evt_monthly_billing_process

DELIMITER // 

DROP EVENT IF EXISTS evt_monthly_billing_process //

CREATE EVENT IF NOT EXISTS evt_monthly_billing_process
ON SCHEDULE EVERY 1 MINUTE -- every 1 month: hệ thống thực tế
STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE -- (LAST_DAY(CURRENT_DATE) + INTERVAL 1 DAY + INTERVAL 1 MINUTE) -- hệ thống thực tế
COMMENT 'Auto monthly billing system'  -- mục đích của evt
DO 
BEGIN 
	DECLARE done INT DEFAULT FALSE; 
    DECLARE v_room_id_loop INT; 
	DECLARE v_target_month DATE; 
    
    DECLARE cur_rooms CURSOR FOR 
		SELECT room_id
        FROM rooms; 
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE; 
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
		CALL sp_add_audit_log('EVENT_SCHEDULE', 'ERROR', 'System error during monthly billing process', 'SQL_ERROR');
	END; 
    
    SET v_target_month = DATE_FORMAT(CURRENT_DATE, '%Y-%m-01'); 
    
    CALL sp_add_audit_log('EVENT_SCHEDULE', 'START_BILLING', CONCAT('Starting invoice generation for: ', v_target_month), NULL);
    
    OPEN cur_rooms; 
    read_loop: LOOP
		FETCH cur_rooms INTO v_room_id_loop; 
        IF done THEN 
			LEAVE read_loop; 
        END IF; 
        
			CALL sp_auto_generate_all_invoices( v_target_month);
        
    END LOOP;
    CLOSE cur_rooms; 
    
    CALL sp_add_audit_log('EVENT_SCHEDULE', 'FINISH_BILLING', CONCAT('Successfully completed billing for: ', v_target_month), NULL);
END // 

DELIMITER ; 

SHOW PROCESSLIST;

select * 
from invoices; 