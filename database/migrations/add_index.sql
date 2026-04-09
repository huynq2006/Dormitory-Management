ALTER TABLE invoices
ADD idx_invoices_overdue_lookup(paid_status, due_date, room_id);

ALTER TABLE contracts
ADD idx_contracts_active_lookup(room_id, status, start_date, end_date);

EXPLAIN ANALYZE SELECT * FROM vw_overdue_debtors;