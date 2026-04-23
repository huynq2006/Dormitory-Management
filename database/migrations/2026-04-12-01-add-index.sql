ALTER TABLE invoices
ADD INDEX idx_invoices_overdue_lookup(paid_status, due_date, room_id);

ALTER TABLE contracts
ADD INDEX idx_contracts_active_lookup(room_id, status, start_date, end_date);