
-- 1. Event scheduler evt_monthly_billing_process

DELIMITER // 

DROP EVENT IF EXISTS evt_monthly_billing_process // 

CREATE EVENT IF NOT EXISTS evt_monthly_billing_process
ON SCHEDULE EVERY 1 MONTH
STARTS LAST_DAY((CURENT_DATE) + INTERVAL 1 DAY + INTERVAL 1 MINUTE)
COMMENT 'Auto monthly bililng system'
DO 
BEGIN 
	DECLARE v_target_month DATE; 
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN 
		CALL sp_add_audit_log ('EVENT_SCHEDULE', 'ERROR', 'System eorror during monthly billing process', 'SQL_ERROR');
        COMMIT; 
	END; 
	SET v_target_month = DATE_FORMAT(CURRENT_DATE, '%Y-%m-01'); 
	CALL sp_add_audit_log('EVENT_SCHEDULE', 'START_BILLING', CONCAT('Starting invoice generation for: ', v_target_month), NULL);

	CALL sp_generate_monthly_invoices(NULL, v_target_month);
END // 

DELIMITER ; 
