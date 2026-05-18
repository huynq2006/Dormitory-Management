ALTER TABLE contracts
ADD INDEX idx_contracts_active_lookup(room_id, status, start_date, end_date);

ALTER TABLE invoices
ADD INDEX idx_invoices_covering (due_date, paid_status, room_id, month, total_amount);

ALTER TABLE students
ADD INDEX idx_student_status(status);

ALTER TABLE invoices
ADD INDEX idx_invoices_optimized (paid_status, due_date, room_id, month, total_amount);

SHOW INDEXES FROM invoices;

DROP index idx_contracts_active_lookup ON contracts;
DROP index idx_invoices_covering ON invoices;
DROP index idx_invoices_optimized ON invoices;
DROP index idx_student_status ON students;


-- Truy vấn tất cả hóa đơn chưa thanh toán để tính tổng nợ
-- Mong đợi: Sử dụng idx_invoices_optimized và "Using index" trong cột Extra
EXPLAIN ANALYZE
SELECT 
    paid_status, 
    SUM(total_amount) as total_debt,
    COUNT(*) as invoice_count
FROM invoices
WHERE paid_status IN ('unpaid', 'overdue')
GROUP BY paid_status;

-- Tìm danh sách nợ trong một khoảng thời gian cụ thể
-- Mong đợi: Sử dụng idx_invoices_due_status hoặc idx_invoices_optimized với type "range"
EXPLAIN ANALYZE
SELECT room_id, month, total_amount, due_date
FROM invoices
WHERE due_date BETWEEN '2026-01-01' AND '2026-06-30'
  AND paid_status = 'unpaid';
  
-- Kiểm tra xem vào một ngày nhất định, những phòng nào có hợp đồng hợp lệ
-- Mong đợi: Sử dụng idx_contracts_active_lookup thay vì idx_contracts_room_status
EXPLAIN ANALYZE
SELECT *
FROM contracts
WHERE status = 'active'
  AND start_date <= '2026-04-01'
  AND (end_date IS NULL OR end_date >= '2026-04-01');
  
-- Lấy 10 hóa đơn nợ gần nhất
-- Mong đợi: Extra không có "Using filesort" vì index đã được sắp xếp theo due_date
EXPLAIN ANALYZE
SELECT invoice_id, room_id, total_amount, due_date
FROM invoices
WHERE paid_status = 'overdue'
ORDER BY due_date DESC
LIMIT 10;