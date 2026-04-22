use dormitory_management;

-- ALTER TABLE invoices
-- ADD INDEX idx_invoices_overdue_lookup(paid_status, due_date, room_id);

-- drop index idx_invoices_overdue_lookup on invoices;

ALTER TABLE contracts
ADD INDEX idx_contracts_active_lookup(room_id, status, start_date, end_date);

ALTER TABLE invoices ADD INDEX idx_invoices_due_status (due_date, paid_status);

ALTER TABLE invoices ADD INDEX idx_invoices_covering 
(due_date, paid_status, room_id, month, total_amount);

ALTER TABLE invoices ADD INDEX idx_invoices_optimized (paid_status, due_date, room_id, month, total_amount);

EXPLAIN ANALYZE SELECT * FROM vw_overdue_debtors;